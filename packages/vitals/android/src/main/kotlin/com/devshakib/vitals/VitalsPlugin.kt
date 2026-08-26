package com.devshakib.vitals

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.BloodGlucoseRecord
import androidx.health.connect.client.records.BloodPressureRecord
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.BodyTemperatureRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.FloorsClimbedRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.HydrationRecord
import androidx.health.connect.client.records.LeanBodyMassRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RespiratoryRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.reflect.KClass

/** Health Connect side of `vitals`. */
class VitalsPlugin :
  FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
  PluginRegistry.ActivityResultListener {

  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var activity: Activity? = null
  private var binding: ActivityPluginBinding? = null
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

  private var pendingPermissionResult: MethodChannel.Result? = null
  private var requestedPermissions: Set<String> = emptySet()

  private val client: HealthConnectClient? by lazy {
    if (HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE) {
      HealthConnectClient.getOrCreate(context)
    } else {
      null
    }
  }

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "dev.shakib/vitals")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    scope.cancel()
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    this.binding = binding
    binding.addActivityResultListener(this)
  }

  override fun onDetachedFromActivity() {
    binding?.removeActivityResultListener(this)
    activity = null
    binding = null
  }

  override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) =
    onAttachedToActivity(b)

  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

  // ---------------------------------------------------------------- mapping

  /**
   * Dart type id to Health Connect record class.
   *
   * Two types have no honest counterpart here and are absent on purpose
   * rather than mapped to something close: `mindfulSession`, which Health
   * Connect does not model at all, and `basalEnergyBurned`, whose nearest
   * record is a *rate* rather than an interval total. Returning approximate
   * data for either would be worse than reporting it unsupported.
   */
  private fun recordClass(id: String): KClass<out Record>? = when (id) {
    "steps" -> StepsRecord::class
    "flightsClimbed" -> FloorsClimbedRecord::class
    "distanceWalkingRunning" -> DistanceRecord::class
    "activeEnergyBurned" -> ActiveCaloriesBurnedRecord::class
    "heartRate" -> HeartRateRecord::class
    "restingHeartRate" -> RestingHeartRateRecord::class
    "respiratoryRate" -> RespiratoryRateRecord::class
    "oxygenSaturation" -> OxygenSaturationRecord::class
    "bodyTemperature" -> BodyTemperatureRecord::class
    "bloodPressureSystolic", "bloodPressureDiastolic" -> BloodPressureRecord::class
    "bloodGlucose" -> BloodGlucoseRecord::class
    "bodyMass" -> WeightRecord::class
    "leanBodyMass" -> LeanBodyMassRecord::class
    "bodyFatPercentage" -> BodyFatRecord::class
    "height" -> HeightRecord::class
    "water" -> HydrationRecord::class
    "sleep" -> SleepSessionRecord::class
    "workout" -> ExerciseSessionRecord::class
    else -> null
  }

  private fun readPermission(id: String): String? =
    recordClass(id)?.let { HealthPermission.getReadPermission(it) }

  private fun writePermission(id: String): String? =
    recordClass(id)?.let { HealthPermission.getWritePermission(it) }

  // --------------------------------------------------------------- dispatch

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "isAvailable" ->
        result.success(
          HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE
        )

      "requestPermissions" -> requestPermissions(call, result)
      "writeAccess" -> access(call, result, write = true)
      "readAccess" -> access(call, result, write = false)
      "read" -> read(call, result)
      "statistics" -> statistics(call, result)
      "write" -> result.error("unsupported", "Writing lands in a later version.", null)
      "delete" -> result.error("unsupported", "Deleting lands in a later version.", null)
      else -> result.notImplemented()
    }
  }

  private fun guard(result: MethodChannel.Result, body: suspend () -> Unit) {
    val available = client
    if (available == null) {
      result.error("unavailable", "Health Connect is not available.", null)
      return
    }
    scope.launch {
      try {
        body()
      } catch (e: Exception) {
        result.error("healthConnect", e.message ?: e.toString(), null)
      }
    }
  }

  // ------------------------------------------------------------ permissions

  private fun requestPermissions(call: MethodCall, result: MethodChannel.Result) {
    val host = activity
    if (host == null) {
      result.error("noActivity", "Permissions need a foreground activity.", null)
      return
    }
    if (pendingPermissionResult != null) {
      result.error("busy", "A permission request is already in flight.", null)
      return
    }

    val read = (call.argument<List<String>>("read") ?: emptyList())
      .mapNotNull(::readPermission)
    val write = (call.argument<List<String>>("write") ?: emptyList())
      .mapNotNull(::writePermission)
    requestedPermissions = (read + write).toSet()

    if (requestedPermissions.isEmpty()) {
      result.success(true)
      return
    }

    pendingPermissionResult = result
    val contract = PermissionController.createRequestPermissionResultContract()
    val intent: Intent = contract.createIntent(host, requestedPermissions)
    host.startActivityForResult(intent, PERMISSION_REQUEST_CODE)
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != PERMISSION_REQUEST_CODE) return false
    val result = pendingPermissionResult ?: return true
    pendingPermissionResult = null

    val contract = PermissionController.createRequestPermissionResultContract()
    val granted = contract.parseResult(resultCode, data)
    // True means the sheet completed, matching the iOS contract. Whether
    // anything was granted is a separate question, answered by readAccess.
    result.success(granted.containsAll(requestedPermissions) || granted.isNotEmpty())
    return true
  }

  private fun access(call: MethodCall, result: MethodChannel.Result, write: Boolean) {
    val ids = call.argument<List<String>>("types") ?: emptyList()
    guard(result) {
      val granted = client!!.permissionController.getGrantedPermissions()
      val out = HashMap<String, Any>()
      for (id in ids) {
        val permission = if (write) writePermission(id) else readPermission(id)
        val ok = permission != null && granted.contains(permission)
        // Health Connect can answer both questions truthfully, unlike iOS.
        out[id] = if (write) (if (ok) "granted" else "denied") else ok
      }
      withContext(Dispatchers.Main) { result.success(out) }
    }
  }

  // ---------------------------------------------------------------- reading

  private fun read(call: MethodCall, result: MethodChannel.Result) {
    val id = call.argument<String>("type") ?: return result.error(
      "unknownType", "A type is required.", null
    )
    val klass = recordClass(id) ?: return result.error(
      "unsupportedOnAndroid", "Health Connect does not model $id.", null
    )
    val from = Instant.ofEpochMilli(call.argument<Number>("from")!!.toLong())
    val to = Instant.ofEpochMilli(call.argument<Number>("to")!!.toLong())
    val limit = call.argument<Number>("limit")?.toInt()

    guard(result) {
      val response = client!!.readRecords(
        ReadRecordsRequest(
          recordType = klass,
          timeRangeFilter = TimeRangeFilter.between(from, to),
        )
      )
      var encoded = response.records.mapNotNull { encode(it, id) }
      if (limit != null && encoded.size > limit) {
        encoded = encoded.takeLast(limit)
      }
      withContext(Dispatchers.Main) { result.success(encoded) }
    }
  }

  /** One record flattened into the shape the Dart side decodes. */
  private data class Reading(
    val start: Instant,
    val end: Instant,
    val value: Double? = null,
    val stage: String? = null,
    val activity: String? = null,
  )

  /**
   * Health Connect splits records into interval and instantaneous shapes, but
   * the marker interfaces for those are `internal`, so each concrete type
   * states its own time range here.
   */
  private fun encode(record: Record, id: String): Map<String, Any?>? {
    val reading: Reading = when (record) {
      is StepsRecord ->
        Reading(record.startTime, record.endTime, record.count.toDouble())
      is FloorsClimbedRecord ->
        Reading(record.startTime, record.endTime, record.floors)
      is DistanceRecord ->
        Reading(record.startTime, record.endTime, record.distance.inMeters)
      is ActiveCaloriesBurnedRecord ->
        Reading(record.startTime, record.endTime, record.energy.inKilocalories)
      is HydrationRecord ->
        Reading(record.startTime, record.endTime, record.volume.inLiters)
      is HeartRateRecord ->
        // One record holds many beats; the mean across it is the closest
        // honest single value.
        Reading(
          record.startTime, record.endTime,
          if (record.samples.isEmpty()) 0.0
          else record.samples.map { it.beatsPerMinute }.average(),
        )
      is SleepSessionRecord ->
        Reading(record.startTime, record.endTime, stage = "asleep")
      is ExerciseSessionRecord ->
        Reading(
          record.startTime, record.endTime,
          activity = record.exerciseType.toString(),
        )

      is RestingHeartRateRecord ->
        Reading(record.time, record.time, record.beatsPerMinute.toDouble())
      is RespiratoryRateRecord ->
        Reading(record.time, record.time, record.rate)
      // Health Connect reports percentages as 0-100 while the Dart side is a
      // fraction, so the conversion happens once, here.
      is OxygenSaturationRecord ->
        Reading(record.time, record.time, record.percentage.value / 100.0)
      is BodyFatRecord ->
        Reading(record.time, record.time, record.percentage.value / 100.0)
      is BodyTemperatureRecord ->
        Reading(record.time, record.time, record.temperature.inCelsius)
      is BloodGlucoseRecord ->
        Reading(record.time, record.time, record.level.inMillimolesPerLiter)
      is WeightRecord ->
        Reading(record.time, record.time, record.weight.inKilograms)
      is LeanBodyMassRecord ->
        Reading(record.time, record.time, record.mass.inKilograms)
      is HeightRecord ->
        Reading(record.time, record.time, record.height.inMeters)
      is BloodPressureRecord ->
        Reading(
          record.time, record.time,
          if (id == "bloodPressureSystolic") {
            record.systolic.inMillimetersOfMercury
          } else {
            record.diastolic.inMillimetersOfMercury
          },
        )
      else -> return null
    }

    return hashMapOf(
      "start" to reading.start.toEpochMilli(),
      "end" to reading.end.toEpochMilli(),
      "id" to record.metadata.id,
      "value" to reading.value,
      "stage" to reading.stage,
      "activity" to reading.activity,
      "source" to hashMapOf(
        "name" to record.metadata.dataOrigin.packageName,
        "bundleId" to record.metadata.dataOrigin.packageName,
        "device" to record.metadata.device?.model,
      ),
    )
  }

  // ------------------------------------------------------------- statistics

  /**
   * Buckets on the platform side by reading records and reducing them here.
   *
   * Health Connect's own aggregate API needs a metric constant per record
   * type, which is a larger mapping than this version carries. Reducing in
   * Kotlin still keeps every sample off the method channel, which is the
   * expensive part; swapping in the native aggregates later is an
   * optimisation, not a behaviour change.
   */
  private fun statistics(call: MethodCall, result: MethodChannel.Result) {
    val id = call.argument<String>("type") ?: return result.error(
      "unknownType", "A type is required.", null
    )
    val klass = recordClass(id) ?: return result.error(
      "unsupportedOnAndroid", "Health Connect does not model $id.", null
    )
    val from = Instant.ofEpochMilli(call.argument<Number>("from")!!.toLong())
    val to = Instant.ofEpochMilli(call.argument<Number>("to")!!.toLong())
    val bucket = call.argument<String>("bucket") ?: "daily"
    val aggregate = call.argument<String>("aggregate") ?: "sum"

    guard(result) {
      val response = client!!.readRecords(
        ReadRecordsRequest(
          recordType = klass,
          timeRangeFilter = TimeRangeFilter.between(from, to),
        )
      )
      val zone = ZoneId.systemDefault()
      val points = response.records.mapNotNull { record ->
        val map = encode(record, id) ?: return@mapNotNull null
        val value = map["value"] as? Double ?: return@mapNotNull null
        (map["start"] as Long) to value
      }

      val out = ArrayList<Map<String, Any?>>()
      var cursor = floor(ZonedDateTime.ofInstant(from, zone), bucket)
      while (cursor.toInstant() < to) {
        val next = advance(cursor, bucket)
        val startMs = cursor.toInstant().toEpochMilli()
        val endMs = next.toInstant().toEpochMilli()
        val inBucket = points.filter { it.first in startMs until endMs }.map { it.second }
        out.add(
          hashMapOf(
            "start" to startMs,
            "end" to endMs,
            "value" to if (inBucket.isEmpty()) null else reduce(inBucket, aggregate),
          )
        )
        cursor = next
      }
      withContext(Dispatchers.Main) { result.success(out) }
    }
  }

  private fun reduce(values: List<Double>, how: String): Double = when (how) {
    "average" -> values.average()
    "minimum" -> values.min()
    "maximum" -> values.max()
    "latest" -> values.last()
    else -> values.sum()
  }

  private fun floor(t: ZonedDateTime, bucket: String): ZonedDateTime = when (bucket) {
    "hourly" -> t.truncatedTo(java.time.temporal.ChronoUnit.HOURS)
    "weekly" -> t.toLocalDate().atStartOfDay(t.zone)
      .minusDays((t.dayOfWeek.value - 1).toLong())
    "monthly" -> t.toLocalDate().withDayOfMonth(1).atStartOfDay(t.zone)
    else -> t.toLocalDate().atStartOfDay(t.zone)
  }

  private fun advance(t: ZonedDateTime, bucket: String): ZonedDateTime = when (bucket) {
    "hourly" -> t.plusHours(1)
    "weekly" -> t.plusWeeks(1)
    "monthly" -> t.plusMonths(1)
    else -> t.plusDays(1)
  }

  private companion object {
    const val PERMISSION_REQUEST_CODE = 0x5641
  }
}
