import 'package:flutter/foundation.dart';

/// A mass, stored canonically so the unit is never in doubt.
///
/// Health data crosses unit systems constantly — HealthKit stores kilograms,
/// users read pounds, and a bare `double` loses which is which. Every quantity
/// in this package is a typed value with named accessors, so the classic
/// "is this kilograms or pounds?" bug cannot be written.
@immutable
class Mass implements Comparable<Mass> {
  /// Creates a mass from kilograms.
  const Mass.kilograms(this.kilograms);

  /// Creates a mass from grams.
  const Mass.grams(double grams) : kilograms = grams / 1000;

  /// Creates a mass from pounds.
  const Mass.pounds(double pounds) : kilograms = pounds * 0.45359237;

  /// Creates a mass from stone.
  const Mass.stone(double stone) : kilograms = stone * 6.35029318;

  /// The canonical value.
  final double kilograms;

  /// In grams.
  double get grams => kilograms * 1000;

  /// In pounds.
  double get pounds => kilograms / 0.45359237;

  /// In stone.
  double get stone => kilograms / 6.35029318;

  @override
  int compareTo(Mass other) => kilograms.compareTo(other.kilograms);

  @override
  bool operator ==(Object other) =>
      other is Mass && other.kilograms == kilograms;

  @override
  int get hashCode => kilograms.hashCode;

  @override
  String toString() => '${kilograms.toStringAsFixed(2)} kg';
}

/// A distance, stored canonically in metres.
@immutable
class Length implements Comparable<Length> {
  /// Creates a length from metres.
  const Length.metres(this.metres);

  /// Creates a length from centimetres.
  const Length.centimetres(double cm) : metres = cm / 100;

  /// Creates a length from kilometres.
  const Length.kilometres(double km) : metres = km * 1000;

  /// Creates a length from miles.
  const Length.miles(double miles) : metres = miles * 1609.344;

  /// Creates a length from feet.
  const Length.feet(double feet) : metres = feet * 0.3048;

  /// The canonical value.
  final double metres;

  /// In centimetres.
  double get centimetres => metres * 100;

  /// In kilometres.
  double get kilometres => metres / 1000;

  /// In miles.
  double get miles => metres / 1609.344;

  /// In feet.
  double get feet => metres / 0.3048;

  @override
  int compareTo(Length other) => metres.compareTo(other.metres);

  @override
  bool operator ==(Object other) => other is Length && other.metres == metres;

  @override
  int get hashCode => metres.hashCode;

  @override
  String toString() => '${metres.toStringAsFixed(1)} m';
}

/// An amount of energy, stored canonically in kilocalories.
///
/// Kilocalories rather than joules because that is what both platforms and
/// every fitness UI actually use.
@immutable
class Energy implements Comparable<Energy> {
  /// Creates an energy from kilocalories.
  const Energy.kilocalories(this.kilocalories);

  /// Creates an energy from joules.
  const Energy.joules(double joules) : kilocalories = joules / 4184;

  /// Creates an energy from kilojoules.
  const Energy.kilojoules(double kj) : kilocalories = kj / 4.184;

  /// The canonical value.
  final double kilocalories;

  /// In joules.
  double get joules => kilocalories * 4184;

  /// In kilojoules.
  double get kilojoules => kilocalories * 4.184;

  @override
  int compareTo(Energy other) => kilocalories.compareTo(other.kilocalories);

  @override
  bool operator ==(Object other) =>
      other is Energy && other.kilocalories == kilocalories;

  @override
  int get hashCode => kilocalories.hashCode;

  @override
  String toString() => '${kilocalories.toStringAsFixed(0)} kcal';
}

/// A volume, stored canonically in litres.
@immutable
class Volume implements Comparable<Volume> {
  /// Creates a volume from litres.
  const Volume.litres(this.litres);

  /// Creates a volume from millilitres.
  const Volume.millilitres(double ml) : litres = ml / 1000;

  /// Creates a volume from US fluid ounces.
  const Volume.fluidOuncesUS(double oz) : litres = oz * 0.0295735295625;

  /// The canonical value.
  final double litres;

  /// In millilitres.
  double get millilitres => litres * 1000;

  /// In US fluid ounces.
  double get fluidOuncesUS => litres / 0.0295735295625;

  @override
  int compareTo(Volume other) => litres.compareTo(other.litres);

  @override
  bool operator ==(Object other) => other is Volume && other.litres == litres;

  @override
  int get hashCode => litres.hashCode;

  @override
  String toString() => '${millilitres.toStringAsFixed(0)} ml';
}

/// A temperature, stored canonically in degrees Celsius.
@immutable
class Temperature implements Comparable<Temperature> {
  /// Creates a temperature from degrees Celsius.
  const Temperature.celsius(this.celsius);

  /// Creates a temperature from degrees Fahrenheit.
  const Temperature.fahrenheit(double f) : celsius = (f - 32) * 5 / 9;

  /// The canonical value.
  final double celsius;

  /// In degrees Fahrenheit.
  double get fahrenheit => celsius * 9 / 5 + 32;

  @override
  int compareTo(Temperature other) => celsius.compareTo(other.celsius);

  @override
  bool operator ==(Object other) =>
      other is Temperature && other.celsius == celsius;

  @override
  int get hashCode => celsius.hashCode;

  @override
  String toString() => '${celsius.toStringAsFixed(1)} °C';
}

/// A pressure, stored canonically in millimetres of mercury.
///
/// mmHg because blood pressure is the only pressure health data records.
@immutable
class Pressure implements Comparable<Pressure> {
  /// Creates a pressure from millimetres of mercury.
  const Pressure.millimetresOfMercury(this.millimetresOfMercury);

  /// Creates a pressure from kilopascals.
  const Pressure.kilopascals(double kpa) : millimetresOfMercury = kpa * 7.50062;

  /// The canonical value.
  final double millimetresOfMercury;

  /// In kilopascals.
  double get kilopascals => millimetresOfMercury / 7.50062;

  @override
  int compareTo(Pressure other) =>
      millimetresOfMercury.compareTo(other.millimetresOfMercury);

  @override
  bool operator ==(Object other) =>
      other is Pressure && other.millimetresOfMercury == millimetresOfMercury;

  @override
  int get hashCode => millimetresOfMercury.hashCode;

  @override
  String toString() => '${millimetresOfMercury.toStringAsFixed(0)} mmHg';
}

/// A blood glucose concentration, stored canonically in mmol/L.
@immutable
class Concentration implements Comparable<Concentration> {
  /// Creates a concentration from millimoles per litre.
  const Concentration.millimolesPerLitre(this.millimolesPerLitre);

  /// Creates a concentration from milligrams per decilitre.
  ///
  /// The conversion factor is glucose-specific, which is why this type is
  /// named for the measurement rather than being a general concentration.
  const Concentration.milligramsPerDecilitre(double mgdl)
    : millimolesPerLitre = mgdl / 18.0182;

  /// The canonical value.
  final double millimolesPerLitre;

  /// In milligrams per decilitre.
  double get milligramsPerDecilitre => millimolesPerLitre * 18.0182;

  @override
  int compareTo(Concentration other) =>
      millimolesPerLitre.compareTo(other.millimolesPerLitre);

  @override
  bool operator ==(Object other) =>
      other is Concentration && other.millimolesPerLitre == millimolesPerLitre;

  @override
  int get hashCode => millimolesPerLitre.hashCode;

  @override
  String toString() => '${millimolesPerLitre.toStringAsFixed(1)} mmol/L';
}
