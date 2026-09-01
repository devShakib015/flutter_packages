import '../json.dart';
import 'money.dart';

/// How a coupon reduces the total.
enum WooDiscountType {
  /// A percentage off the cart.
  percent,

  /// A fixed amount off the cart.
  fixedCart,

  /// A fixed amount off each qualifying product.
  fixedProduct,

  /// Something this client does not recognise.
  unknown;

  /// Reads WooCommerce's value.
  static WooDiscountType parse(Object? value) => switch (value) {
    'percent' => percent,
    'fixed_cart' => fixedCart,
    'fixed_product' => fixedProduct,
    _ => unknown,
  };
}

/// A discount code.
class WooCoupon {
  /// Creates a coupon.
  const WooCoupon({
    required this.id,
    required this.code,
    required this.amount,
    required this.discountType,
    required this.description,
    required this.dateExpires,
    required this.usageCount,
    required this.usageLimit,
    required this.minimumAmount,
    required this.maximumAmount,
    required this.freeShipping,
    required this.productIds,
    required this.raw,
  });

  /// Reads WooCommerce's representation.
  factory WooCoupon.fromJson(Map<String, Object?> json) => WooCoupon(
    id: readInt(json['id'], orElse: 0),
    code: readString(json['code']),
    amount: WooPrice(readString(json['amount'])),
    discountType: WooDiscountType.parse(json['discount_type']),
    description: readString(json['description']),
    dateExpires: DateTime.tryParse(readString(json['date_expires'])),
    usageCount: readInt(json['usage_count'], orElse: 0),
    usageLimit: readIntOrNull(json['usage_limit']),
    minimumAmount: WooPrice(readString(json['minimum_amount'])),
    maximumAmount: WooPrice(readString(json['maximum_amount'])),
    freeShipping: readBool(json['free_shipping']),
    productIds: <int>[
      for (final Object? v in (readList(json['product_ids'])))
        if (v is num) v.toInt(),
    ],
    raw: json,
  );

  /// The coupon id.
  final int id;

  /// The code a customer types.
  final String code;

  /// How much it takes off, meaning depending on [discountType].
  final WooPrice amount;

  /// Percentage, fixed cart, or fixed product.
  final WooDiscountType discountType;

  /// What it is for.
  final String description;

  /// When it stops working, null if never.
  final DateTime? dateExpires;

  /// How many times it has been used.
  final int usageCount;

  /// How many times it may be used, null when unlimited.
  final int? usageLimit;

  /// Smallest order it applies to.
  final WooPrice minimumAmount;

  /// Largest order it applies to.
  final WooPrice maximumAmount;

  /// Whether it also removes shipping.
  final bool freeShipping;

  /// Products it is restricted to, empty when it applies to everything.
  final List<int> productIds;

  /// Everything WooCommerce sent, untouched.
  final Map<String, Object?> raw;

  /// Whether it has passed its expiry date.
  ///
  /// Says nothing about usage limits — see [isUsedUp].
  bool get isExpired =>
      dateExpires != null && dateExpires!.isBefore(DateTime.now());

  /// Whether it has hit its usage limit.
  bool get isUsedUp => usageLimit != null && usageCount >= usageLimit!;

  /// Whether it would be accepted right now, as far as this data shows.
  ///
  /// The store is the authority — per-customer limits and product rules are
  /// not all visible here.
  bool get looksUsable => !isExpired && !isUsedUp;

  @override
  String toString() => 'WooCoupon($code, ${discountType.name} $amount)';
}
