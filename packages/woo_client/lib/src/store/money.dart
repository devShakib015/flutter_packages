import '../json.dart';

import 'dart:math' as math;

/// How a store writes its prices.
///
/// The Store API sends this alongside every amount, because a store decides
/// its own symbol, separators, and whether the symbol goes before or after.
class StoreCurrency {
  /// Creates a currency description.
  const StoreCurrency({
    this.code = '',
    this.symbol = '',
    this.minorUnit = 2,
    this.decimalSeparator = '.',
    this.thousandSeparator = ',',
    this.prefix = '',
    this.suffix = '',
  });

  /// Reads the seven `currency_*` fields the Store API repeats everywhere.
  factory StoreCurrency.fromJson(Map<String, Object?> json) => StoreCurrency(
    code: readString(json['currency_code']),
    symbol: readString(json['currency_symbol']),
    minorUnit: readInt(json['currency_minor_unit'], orElse: 2),
    decimalSeparator: readStringOr(json['currency_decimal_separator'], '.'),
    // An empty thousand separator is a real choice — some stores group
    // nothing — so only an absent key falls back, unlike the decimal
    // separator, where an empty string would render 8256 as "8256".
    thousandSeparator: json.containsKey('currency_thousand_separator')
        ? readString(json['currency_thousand_separator'])
        : ',',
    prefix: readString(json['currency_prefix']),
    suffix: readString(json['currency_suffix']),
  );

  /// ISO 4217 code, such as `USD`.
  final String code;

  /// The store's symbol, such as `$`. Already HTML-decoded by WooCommerce for
  /// most currencies, but `&pound;` and friends do occur.
  final String symbol;

  /// How many digits are after the decimal point. Two for most currencies,
  /// zero for yen, three for dinar.
  final int minorUnit;

  /// What separates the whole part from the fraction.
  final String decimalSeparator;

  /// What groups the thousands. Empty in stores that group nothing.
  final String thousandSeparator;

  /// Written before the number, usually the symbol.
  final String prefix;

  /// Written after the number.
  final String suffix;

  /// Turns a count of minor units into the string this store would print.
  ///
  /// ```dart
  /// currency.format(8256); // '$82.56'
  /// ```
  String format(int minorUnits) {
    final bool negative = minorUnits < 0;
    final String digits = minorUnits.abs().toString().padLeft(
      minorUnit + 1,
      '0',
    );
    final int split = digits.length - minorUnit;
    final String whole = _group(digits.substring(0, split));
    final String fraction = digits.substring(split);
    final String number = minorUnit == 0
        ? whole
        : '$whole$decimalSeparator$fraction';
    return '${negative ? '-' : ''}$prefix$number$suffix';
  }

  String _group(String whole) {
    if (thousandSeparator.isEmpty || whole.length <= 3) return whole;
    final StringBuffer out = StringBuffer();
    final int lead = whole.length % 3 == 0 ? 3 : whole.length % 3;
    out.write(whole.substring(0, lead));
    for (int i = lead; i < whole.length; i += 3) {
      out
        ..write(thousandSeparator)
        ..write(whole.substring(i, i + 3));
    }
    return out.toString();
  }

  @override
  String toString() => code.isEmpty ? 'StoreCurrency()' : code;
}

/// An amount of money from the Store API.
///
/// The Store API sends amounts as integer strings in the currency's smallest
/// unit — `"1800"` is eighteen dollars, not one thousand eight hundred — and
/// sends the formatting rules alongside. Printing this gives you what the
/// store itself would print.
///
/// ```dart
/// print(cart.totals.totalPrice);        // $82.56
/// cart.totals.totalPrice.minorUnits;    // 8256
/// cart.totals.totalPrice.amount;        // 82.56
/// ```
class StoreMoney implements Comparable<StoreMoney> {
  /// Creates an amount from a count of minor units.
  const StoreMoney(this.minorUnits, this.currency);

  /// Reads one field of an object that also carries the `currency_*` fields.
  factory StoreMoney.read(
    Map<String, Object?> json,
    String field, [
    StoreCurrency? currency,
  ]) => StoreMoney(
    int.tryParse('${json[field] ?? ''}') ?? 0,
    currency ?? StoreCurrency.fromJson(json),
  );

  /// The amount, counted in the currency's smallest unit.
  final int minorUnits;

  /// How to write it.
  final StoreCurrency currency;

  /// The amount as a decimal number.
  ///
  /// Convenient for comparisons and charts. Do not add money up this way —
  /// sum [minorUnits] instead, which is exact.
  double get amount => minorUnits / math.pow(10, currency.minorUnit);

  /// Whether this is exactly nothing.
  bool get isZero => minorUnits == 0;

  /// This amount plus [other], which must be the same currency.
  StoreMoney operator +(StoreMoney other) =>
      StoreMoney(minorUnits + other.minorUnits, currency);

  /// This amount minus [other], which must be the same currency.
  StoreMoney operator -(StoreMoney other) =>
      StoreMoney(minorUnits - other.minorUnits, currency);

  /// This amount repeated [times] over.
  StoreMoney operator *(int times) => StoreMoney(minorUnits * times, currency);

  /// Whether this is less than [other].
  bool operator <(StoreMoney other) => minorUnits < other.minorUnits;

  /// Whether this is less than or equal to [other].
  bool operator <=(StoreMoney other) => minorUnits <= other.minorUnits;

  /// Whether this is more than [other].
  bool operator >(StoreMoney other) => minorUnits > other.minorUnits;

  /// Whether this is more than or equal to [other].
  bool operator >=(StoreMoney other) => minorUnits >= other.minorUnits;

  @override
  int compareTo(StoreMoney other) => minorUnits.compareTo(other.minorUnits);

  @override
  bool operator ==(Object other) =>
      other is StoreMoney &&
      other.minorUnits == minorUnits &&
      other.currency.code == currency.code;

  @override
  int get hashCode => Object.hash(minorUnits, currency.code);

  /// The amount as the store would print it, such as `$82.56`.
  @override
  String toString() => currency.format(minorUnits);
}
