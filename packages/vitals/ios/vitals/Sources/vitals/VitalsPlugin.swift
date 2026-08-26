import Flutter
import Foundation
import HealthKit

public class VitalsPlugin: NSObject, FlutterPlugin {

  private let store = HKHealthStore()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.shakib/vitals", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(VitalsPlugin(), channel: channel)
  }

  // MARK: - Type mapping

  /// Maps a Dart type id onto its HealthKit type.
  private static func sampleType(_ id: String) -> HKSampleType? {
    if id == "workout" { return HKObjectType.workoutType() }
    if let category = categoryIdentifier(id) {
      return HKObjectType.categoryType(forIdentifier: category)
    }
    if let quantity = quantityIdentifier(id) {
      return HKObjectType.quantityType(forIdentifier: quantity)
    }
    return nil
  }

  private static func categoryIdentifier(_ id: String)
    -> HKCategoryTypeIdentifier?
  {
    switch id {
    case "sleep": return .sleepAnalysis
    case "mindfulSession": return .mindfulSession
    default: return nil
    }
  }

  private static func quantityIdentifier(_ id: String)
    -> HKQuantityTypeIdentifier?
  {
    switch id {
    case "steps": return .stepCount
    case "flightsClimbed": return .flightsClimbed
    case "distanceWalkingRunning": return .distanceWalkingRunning
    case "activeEnergyBurned": return .activeEnergyBurned
    case "basalEnergyBurned": return .basalEnergyBurned
    case "heartRate": return .heartRate
    case "restingHeartRate": return .restingHeartRate
    case "respiratoryRate": return .respiratoryRate
    case "oxygenSaturation": return .oxygenSaturation
    case "bodyTemperature": return .bodyTemperature
    case "bloodPressureSystolic": return .bloodPressureSystolic
    case "bloodPressureDiastolic": return .bloodPressureDiastolic
    case "bloodGlucose": return .bloodGlucose
    case "bodyMass": return .bodyMass
    case "leanBodyMass": return .leanBodyMass
    case "bodyFatPercentage": return .bodyFatPercentage
    case "height": return .height
    case "water": return .dietaryWater
    default: return nil
    }
  }

  /// The unit each type is exchanged in — always the canonical one the Dart
  /// side expects, so no conversion happens in two places.
  private static func unit(_ id: String) -> HKUnit? {
    switch id {
    case "steps", "flightsClimbed":
      return .count()
    case "distanceWalkingRunning", "height":
      return .meter()
    case "activeEnergyBurned", "basalEnergyBurned":
      return .kilocalorie()
    case "heartRate", "restingHeartRate", "respiratoryRate":
      return HKUnit.count().unitDivided(by: .minute())
    case "oxygenSaturation", "bodyFatPercentage":
      return .percent()
    case "bodyTemperature":
      return .degreeCelsius()
    case "bloodPressureSystolic", "bloodPressureDiastolic":
      return .millimeterOfMercury()
    case "bloodGlucose":
      return HKUnit.moleUnit(
        with: .milli, molarMass: HKUnitMolarMassBloodGlucose
      ).unitDivided(by: .liter())
    case "bodyMass", "leanBodyMass":
      return .gramUnit(with: .kilo)
    case "water":
      return .liter()
    default:
      return nil
    }
  }

  /// Sleep stage names from raw values.
  ///
  /// The named cases for core/deep/REM are marked iOS 16+, but the underlying
  /// numbers are fixed API and a device on iOS 15 simply never reports 3-5.
  /// Matching on the raw value keeps the deployment floor where it is.
  private static func sleepStageName(_ value: Int) -> String {
    switch value {
    case 0: return "inBed"
    case 1: return "asleep"
    case 2: return "awake"
    case 3: return "light"
    case 4: return "deep"
    case 5: return "rem"
    default: return "unknown"
    }
  }

  // MARK: - Dispatch

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "isAvailable":
      result(HKHealthStore.isHealthDataAvailable())

    case "requestPermissions":
      requestPermissions(args, result)

    case "writeAccess":
      result(writeAccess(args))

    case "readAccess":
      // Deliberately nil. HKAuthorizationStatus reports sharing only; Apple
      // provides no way to learn whether read access was granted, so any
      // answer here would be a guess dressed as a fact.
      result(nil)

    case "read":
      read(args, result)

    case "statistics":
      statistics(args, result)

    case "write":
      write(args, result)

    case "delete":
      delete(args, result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func fail(_ result: @escaping FlutterResult, _ code: String, _ message: String) {
    DispatchQueue.main.async {
      result(FlutterError(code: code, message: message, details: nil))
    }
  }

  private static func date(_ value: Any?) -> Date {
    Date(timeIntervalSince1970: ((value as? NSNumber)?.doubleValue ?? 0) / 1000)
  }

  private static func millis(_ date: Date) -> Int {
    Int(date.timeIntervalSince1970 * 1000)
  }

  // MARK: - Authorization

  private func requestPermissions(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable() else { return result(false) }

    let read = Set((args["read"] as? [String] ?? []).compactMap {
      Self.sampleType($0) as HKObjectType?
    })
    let write = Set((args["write"] as? [String] ?? []).compactMap {
      Self.sampleType($0)
    })

    store.requestAuthorization(toShare: write, read: read) { granted, error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "authorization", message: error.localizedDescription, details: nil))
        } else {
          // `granted` means the sheet completed, not that anything was
          // allowed. The Dart side documents that distinction.
          result(granted)
        }
      }
    }
  }

  private func writeAccess(_ args: [String: Any]) -> [String: String] {
    var out: [String: String] = [:]
    for id in args["types"] as? [String] ?? [] {
      guard let type = Self.sampleType(id) else { continue }
      switch store.authorizationStatus(for: type) {
      case .sharingAuthorized: out[id] = "granted"
      case .sharingDenied: out[id] = "denied"
      case .notDetermined: out[id] = "notDetermined"
      @unknown default: out[id] = "notDetermined"
      }
    }
    return out
  }

  // MARK: - Reading

  private func read(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["type"] as? String, let type = Self.sampleType(id) else {
      return fail(result, "unknownType", "Unknown type \(args["type"] ?? "nil").")
    }

    let start = Self.date(args["from"])
    let end = Self.date(args["to"])
    let limit = (args["limit"] as? NSNumber)?.intValue ?? HKObjectQueryNoLimit
    let predicate = HKQuery.predicateForSamples(
      withStart: start, end: end, options: .strictStartDate)
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

    let query = HKSampleQuery(
      sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]
    ) { [weak self] _, samples, error in
      guard let self else { return }
      if let error {
        return self.fail(result, "read", error.localizedDescription)
      }
      let encoded = (samples ?? []).compactMap { self.encode($0, id: id) }
      DispatchQueue.main.async { result(encoded) }
    }
    store.execute(query)
  }

  private func encode(_ sample: HKSample, id: String) -> [String: Any]? {
    var map: [String: Any] = [
      "start": Self.millis(sample.startDate),
      "end": Self.millis(sample.endDate),
      "id": sample.uuid.uuidString,
      "source": [
        "name": sample.sourceRevision.source.name,
        "bundleId": sample.sourceRevision.source.bundleIdentifier,
        "device": sample.device?.name as Any,
      ],
    ]

    if let quantity = sample as? HKQuantitySample, let unit = Self.unit(id) {
      map["value"] = quantity.quantity.doubleValue(for: unit)
      return map
    }
    if let category = sample as? HKCategorySample {
      if id == "sleep" { map["stage"] = Self.sleepStageName(category.value) }
      return map
    }
    if let workout = sample as? HKWorkout {
      map["activity"] = String(workout.workoutActivityType.rawValue)
      if #available(iOS 16.0, *) {
        if let energy = workout.statistics(
          for: HKQuantityType(.activeEnergyBurned)
        )?.sumQuantity() {
          map["energyBurned"] = energy.doubleValue(for: .kilocalorie())
        }
        if let distance = workout.statistics(
          for: HKQuantityType(.distanceWalkingRunning)
        )?.sumQuantity() {
          map["distance"] = distance.doubleValue(for: .meter())
        }
      }
      // Below iOS 16 the totals are simply absent rather than wrong; the Dart
      // side already models them as nullable.
      return map
    }
    return map
  }

  // MARK: - Statistics

  private func statistics(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["type"] as? String else {
      return fail(result, "unknownType", "A type is required.")
    }
    let start = Self.date(args["from"])
    let end = Self.date(args["to"])
    let bucket = args["bucket"] as? String ?? "daily"
    let aggregate = args["aggregate"] as? String ?? "sum"

    // Category types have no HKStatisticsCollectionQuery, so their buckets are
    // built from the samples themselves.
    if Self.categoryIdentifier(id) != nil {
      return categoryStatistics(id: id, start: start, end: end, bucket: bucket, result)
    }

    guard let quantityId = Self.quantityIdentifier(id),
      let type = HKObjectType.quantityType(forIdentifier: quantityId),
      let unit = Self.unit(id)
    else {
      return fail(result, "unknownType", "Cannot aggregate \(id).")
    }

    // Asking a cumulative type for an average, or a discrete type for a sum,
    // makes HealthKit throw. The type's own aggregation style decides.
    let cumulative = type.aggregationStyle == .cumulative
    let options: HKStatisticsOptions
    if cumulative {
      options = .cumulativeSum
    } else {
      switch aggregate {
      case "minimum": options = .discreteMin
      case "maximum": options = .discreteMax
      case "latest": options = .mostRecent
      default: options = .discreteAverage
      }
    }

    let anchor = Self.anchorDate(start, bucket: bucket)
    let query = HKStatisticsCollectionQuery(
      quantityType: type,
      quantitySamplePredicate: HKQuery.predicateForSamples(
        withStart: start, end: end, options: .strictStartDate),
      options: options,
      anchorDate: anchor,
      intervalComponents: Self.interval(bucket))

    query.initialResultsHandler = { _, collection, error in
      if let error {
        return self.fail(result, "statistics", error.localizedDescription)
      }
      var out: [[String: Any]] = []
      collection?.enumerateStatistics(from: start, to: end) { stat, _ in
        let quantity: HKQuantity? =
          cumulative
          ? stat.sumQuantity()
          : {
            switch options {
            case .discreteMin: return stat.minimumQuantity()
            case .discreteMax: return stat.maximumQuantity()
            case .mostRecent: return stat.mostRecentQuantity()
            default: return stat.averageQuantity()
            }
          }()
        out.append([
          "start": Self.millis(stat.startDate),
          "end": Self.millis(stat.endDate),
          "value": quantity?.doubleValue(for: unit) as Any,
        ])
      }
      DispatchQueue.main.async { result(out) }
    }
    store.execute(query)
  }

  /// Sums sample durations per bucket, in minutes, for sleep and mindfulness.
  private func categoryStatistics(
    id: String, start: Date, end: Date, bucket: String,
    _ result: @escaping FlutterResult
  ) {
    guard let type = Self.sampleType(id) else {
      return fail(result, "unknownType", "Unknown type \(id).")
    }
    let predicate = HKQuery.predicateForSamples(
      withStart: start, end: end, options: .strictStartDate)
    let query = HKSampleQuery(
      sampleType: type, predicate: predicate,
      limit: HKObjectQueryNoLimit, sortDescriptors: nil
    ) { _, samples, error in
      if let error {
        return self.fail(result, "statistics", error.localizedDescription)
      }
      let calendar = Calendar.current
      let interval = Self.interval(bucket)
      var out: [[String: Any]] = []
      var cursor = Self.anchorDate(start, bucket: bucket)

      while cursor < end {
        guard let next = calendar.date(byAdding: interval, to: cursor) else { break }
        let minutes = (samples ?? [])
          .filter { $0.startDate >= cursor && $0.startDate < next }
          .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) / 60 }
        var entry: [String: Any] = [
          "start": Self.millis(cursor),
          "end": Self.millis(next),
        ]
        // Omitted rather than zero: no samples and a recorded zero differ.
        if minutes > 0 { entry["value"] = minutes }
        out.append(entry)
        cursor = next
      }
      DispatchQueue.main.async { result(out) }
    }
    store.execute(query)
  }

  private static func interval(_ bucket: String) -> DateComponents {
    var components = DateComponents()
    switch bucket {
    case "hourly": components.hour = 1
    case "weekly": components.day = 7
    case "monthly": components.month = 1
    default: components.day = 1
    }
    return components
  }

  /// Buckets must start on a calendar boundary or the series drifts.
  private static func anchorDate(_ start: Date, bucket: String) -> Date {
    let calendar = Calendar.current
    switch bucket {
    case "hourly":
      return calendar.date(
        from: calendar.dateComponents([.year, .month, .day, .hour], from: start)) ?? start
    case "weekly":
      return calendar.date(
        from: calendar.dateComponents(
          [.yearForWeekOfYear, .weekOfYear], from: start)) ?? start
    case "monthly":
      return calendar.date(
        from: calendar.dateComponents([.year, .month], from: start)) ?? start
    default:
      return calendar.startOfDay(for: start)
    }
  }

  // MARK: - Writing

  private func write(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["type"] as? String else {
      return fail(result, "unknownType", "A type is required.")
    }
    let start = Self.date(args["from"])
    let end = Self.date(args["to"])
    let value = (args["value"] as? NSNumber)?.doubleValue ?? 0

    var sample: HKSample?
    if let quantityId = Self.quantityIdentifier(id),
      let type = HKObjectType.quantityType(forIdentifier: quantityId),
      let unit = Self.unit(id)
    {
      sample = HKQuantitySample(
        type: type,
        quantity: HKQuantity(unit: unit, doubleValue: value),
        start: start, end: end)
    } else if let categoryId = Self.categoryIdentifier(id),
      let type = HKObjectType.categoryType(forIdentifier: categoryId)
    {
      sample = HKCategorySample(type: type, value: Int(value), start: start, end: end)
    }

    guard let sample else {
      return fail(result, "unwritable", "\(id) cannot be written.")
    }
    store.save(sample) { _, error in
      if let error {
        return self.fail(result, "write", error.localizedDescription)
      }
      DispatchQueue.main.async { result(nil) }
    }
  }

  private func delete(_ args: [String: Any], _ result: @escaping FlutterResult) {
    guard let id = args["type"] as? String, let type = Self.sampleType(id) else {
      return fail(result, "unknownType", "Unknown type \(args["type"] ?? "nil").")
    }
    let predicate = HKQuery.predicateForSamples(
      withStart: Self.date(args["from"]), end: Self.date(args["to"]),
      options: .strictStartDate)

    // deleteObjects only removes what this app wrote; HealthKit refuses the
    // rest, which is why the Dart contract says the same.
    store.deleteObjects(of: type, predicate: predicate) { _, count, error in
      if let error {
        return self.fail(result, "delete", error.localizedDescription)
      }
      DispatchQueue.main.async { result(count) }
    }
  }
}
