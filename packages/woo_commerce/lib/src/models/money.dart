/// A price, kept as the store sent it.
///
/// WooCommerce returns prices as strings — `"12.99"`, sometimes `""` — because
/// its own storage is decimal and JSON numbers are not. Parsing them to
/// `double` on the way in loses that fidelity and invites rounding errors in
/// totals, so this keeps the original text and offers the conversion where a
/// caller asks for it.
class WooPrice implements Comparable<WooPrice> {
  /// Creates a price from the store's representation.
  const WooPrice(this.raw);

  /// No price set. WooCommerce sends an empty string for this, not zero.
  static const WooPrice none = WooPrice('');

  /// Exactly what the store sent.
  final String raw;

  /// Whether the store gave a price at all.
  ///
  /// An unpriced variation and a free one are different things, and both
  /// would read as `0.0` if this were parsed eagerly.
  bool get isSet => raw.trim().isNotEmpty;

  /// The price as a number, or null when unset or unparseable.
  double? get amount => isSet ? double.tryParse(raw.trim()) : null;

  /// The price as a number, treating unset as zero.
  double get amountOrZero => amount ?? 0;

  @override
  int compareTo(WooPrice other) => amountOrZero.compareTo(other.amountOrZero);

  @override
  bool operator ==(Object other) => other is WooPrice && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => isSet ? raw : '(no price)';
}
