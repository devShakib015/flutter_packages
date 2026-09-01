import '../../json.dart';
import '../money.dart';
import 'address.dart';

/// A picture the store attached to a product.
class StoreImage {
  /// Creates an image.
  const StoreImage({
    this.id = 0,
    this.src = '',
    this.thumbnail = '',
    this.srcset = '',
    this.sizes = '',
    this.name = '',
    this.alt = '',
  });

  /// Reads the Store API's representation.
  factory StoreImage.fromJson(Map<String, Object?> json) => StoreImage(
    id: readInt(json['id'], orElse: 0),
    src: readString(json['src']),
    thumbnail: readString(json['thumbnail']),
    srcset: readString(json['srcset']),
    sizes: readString(json['sizes']),
    name: readString(json['name']),
    alt: readString(json['alt']),
  );

  /// Attachment id.
  final int id;

  /// Full-size URL.
  final String src;

  /// A square crop, usually 450px, which is what a cart row wants.
  final String thumbnail;

  /// The full `srcset`, if you are rendering to HTML.
  final String srcset;

  /// The `sizes` attribute that goes with [srcset].
  final String sizes;

  /// File name.
  final String name;

  /// Alt text. Often empty, which is the store's fault, not yours.
  final String alt;
}

/// How many of an item a shopper is allowed to have.
class StoreQuantityLimits {
  /// Creates the limits.
  const StoreQuantityLimits({
    this.minimum = 1,
    this.maximum = 9999,
    this.multipleOf = 1,
    this.editable = true,
  });

  /// Reads the Store API's representation.
  factory StoreQuantityLimits.fromJson(Map<String, Object?> json) =>
      StoreQuantityLimits(
        minimum: readInt(json['minimum'], orElse: 1),
        maximum: readInt(json['maximum'], orElse: 9999),
        multipleOf: readInt(json['multiple_of'], orElse: 1),
        editable: readBool(json['editable'], orElse: true),
      );

  /// Fewest allowed.
  final int minimum;

  /// Most allowed — stock, or a per-order cap.
  final int maximum;

  /// Quantities must be a multiple of this. Six-packs, and the like.
  final int multipleOf;

  /// Whether a quantity stepper should be enabled at all.
  final bool editable;

  /// The nearest allowed quantity to [wanted].
  ///
  /// Use this to drive a stepper rather than clamping by hand — it respects
  /// [multipleOf], which is the part people forget.
  int clamp(int wanted) {
    final int stepped = multipleOf <= 1
        ? wanted
        : (wanted / multipleOf).round() * multipleOf;
    return stepped.clamp(minimum, maximum);
  }
}

/// One line of a cart.
class StoreCartItem {
  /// Creates an item.
  const StoreCartItem({
    required this.key,
    required this.id,
    required this.quantity,
    required this.name,
    required this.price,
    required this.regularPrice,
    required this.salePrice,
    required this.lineSubtotal,
    required this.lineTotal,
    required this.raw,
    this.sku = '',
    this.permalink = '',
    this.shortDescription = '',
    this.images = const <StoreImage>[],
    this.limits = const StoreQuantityLimits(),
    this.variation = const <String, String>{},
    this.lowStockRemaining,
    this.backordersAllowed = false,
    this.soldIndividually = false,
  });

  /// Reads the Store API's representation.
  factory StoreCartItem.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> prices = readMap(json['prices']);
    final Map<String, Object?> totals = readMap(json['totals']);
    final StoreCurrency currency = StoreCurrency.fromJson(prices);
    return StoreCartItem(
      key: readString(json['key']),
      id: readInt(json['id'], orElse: 0),
      quantity: readInt(json['quantity'], orElse: 0),
      name: readString(json['name']),
      sku: readString(json['sku']),
      permalink: readString(json['permalink']),
      shortDescription: readString(json['short_description']),
      price: StoreMoney.read(prices, 'price', currency),
      regularPrice: StoreMoney.read(prices, 'regular_price', currency),
      salePrice: StoreMoney.read(prices, 'sale_price', currency),
      lineSubtotal: StoreMoney.read(totals, 'line_subtotal'),
      lineTotal: StoreMoney.read(totals, 'line_total'),
      images: <StoreImage>[
        for (final Map<String, Object?> i in readObjects(json['images']))
          StoreImage.fromJson(i),
      ],
      limits: StoreQuantityLimits.fromJson(readMap(json['quantity_limits'])),
      variation: <String, String>{
        for (final Object? v in readList(json['variation']))
          if (v is Map<String, Object?>)
            '${v['attribute'] ?? ''}': '${v['value'] ?? ''}',
      },
      lowStockRemaining: readIntOrNull(json['low_stock_remaining']),
      backordersAllowed: readBool(json['backorders_allowed']),
      soldIndividually: readBool(json['sold_individually']),
      raw: json,
    );
  }

  /// The cart's own identifier for this line. Every change to an item — a
  /// quantity, a removal — is addressed by this, not by the product id, since
  /// one product can be in a cart twice with different options.
  final String key;

  /// Product or variation id.
  final int id;

  /// How many.
  final int quantity;

  /// Product name.
  final String name;

  /// Stock keeping unit.
  final String sku;

  /// Link to the product page on the store.
  final String permalink;

  /// Short description, as HTML.
  final String shortDescription;

  /// What one costs now.
  final StoreMoney price;

  /// What one costs when it is not on sale.
  final StoreMoney regularPrice;

  /// What one costs on sale. Equal to [regularPrice] when there is no sale.
  final StoreMoney salePrice;

  /// The line before discounts.
  final StoreMoney lineSubtotal;

  /// The line after discounts.
  final StoreMoney lineTotal;

  /// Product images.
  final List<StoreImage> images;

  /// What quantities are allowed.
  final StoreQuantityLimits limits;

  /// Chosen variation attributes, keyed by attribute name.
  final Map<String, String> variation;

  /// How many are left, when the store is showing a low-stock warning.
  final int? lowStockRemaining;

  /// Whether the store will accept an order it cannot fill yet.
  final bool backordersAllowed;

  /// Whether only one may be bought at a time.
  final bool soldIndividually;

  /// The whole item as the store sent it.
  final Map<String, Object?> raw;

  /// Whether this line is discounted.
  bool get onSale => salePrice < regularPrice;

  /// The first image, or null when the product has none.
  StoreImage? get image => images.isEmpty ? null : images.first;
}

/// A coupon that is currently applied to a cart.
class StoreCartCoupon {
  /// Creates a coupon.
  const StoreCartCoupon({
    required this.code,
    required this.discountType,
    required this.totalDiscount,
    required this.totalDiscountTax,
  });

  /// Reads the Store API's representation.
  factory StoreCartCoupon.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> totals = readMap(json['totals']);
    return StoreCartCoupon(
      code: readString(json['code']),
      discountType: readString(json['discount_type']),
      totalDiscount: StoreMoney.read(totals, 'total_discount'),
      totalDiscountTax: StoreMoney.read(totals, 'total_discount_tax'),
    );
  }

  /// The code, always lowercase — WooCommerce lowercases coupon codes.
  final String code;

  /// `percent`, `fixed_cart`, or `fixed_product`.
  final String discountType;

  /// What this coupon took off.
  final StoreMoney totalDiscount;

  /// Tax on the discount.
  final StoreMoney totalDiscountTax;
}

/// One way of shipping one package.
class StoreShippingRate {
  /// Creates a rate.
  const StoreShippingRate({
    required this.rateId,
    required this.name,
    required this.price,
    required this.taxes,
    required this.selected,
    this.description = '',
    this.deliveryTime = '',
    this.methodId = '',
    this.instanceId = 0,
  });

  /// Reads the Store API's representation.
  factory StoreShippingRate.fromJson(Map<String, Object?> json) =>
      StoreShippingRate(
        rateId: readString(json['rate_id']),
        name: readString(json['name']),
        description: readString(json['description']),
        deliveryTime: readString(json['delivery_time']),
        price: StoreMoney.read(json, 'price'),
        taxes: StoreMoney.read(json, 'taxes'),
        methodId: readString(json['method_id']),
        instanceId: readInt(json['instance_id'], orElse: 0),
        selected: readBool(json['selected']),
      );

  /// The id to pass back when choosing this rate, such as `flat_rate:10`.
  final String rateId;

  /// What to show the shopper, such as `Flat rate`.
  final String name;

  /// Longer text from the shipping method.
  final String description;

  /// An estimate, when the method provides one.
  final String deliveryTime;

  /// What it costs.
  final StoreMoney price;

  /// Tax on the shipping.
  final StoreMoney taxes;

  /// Which shipping method produced this, such as `flat_rate`.
  final String methodId;

  /// The configured instance of that method.
  final int instanceId;

  /// Whether this is the rate currently chosen.
  final bool selected;

  /// Whether the shopper pays nothing for this.
  bool get isFree => price.isZero;
}

/// A group of cart items that ship together, with the rates available to it.
class StoreShippingPackage {
  /// Creates a package.
  const StoreShippingPackage({
    required this.packageId,
    required this.name,
    required this.rates,
    this.destination,
    this.itemNames = const <String>[],
  });

  /// Reads the Store API's representation.
  factory StoreShippingPackage.fromJson(Map<String, Object?> json) =>
      StoreShippingPackage(
        packageId: readInt(json['package_id'], orElse: 0),
        name: readString(json['name']),
        destination: switch (json['destination']) {
          final Map<String, Object?> d => StoreAddress.fromJson(d),
          _ => null,
        },
        itemNames: <String>[
          for (final Map<String, Object?> i in readObjects(json['items']))
            readString(i['name']),
        ],
        rates: <StoreShippingRate>[
          for (final Map<String, Object?> r in readObjects(
            json['shipping_rates'],
          ))
            StoreShippingRate.fromJson(r),
        ],
      );

  /// The id to pass when choosing a rate for this package.
  final int packageId;

  /// A label, such as `Shipment 1`.
  final String name;

  /// Where it is going.
  final StoreAddress? destination;

  /// Names of the items in this package.
  final List<String> itemNames;

  /// The rates on offer.
  final List<StoreShippingRate> rates;

  /// The rate currently chosen, or null when none is.
  StoreShippingRate? get selected =>
      rates.where((StoreShippingRate r) => r.selected).firstOrNull;
}

/// What a cart adds up to.
class StoreCartTotals {
  /// Creates the totals.
  const StoreCartTotals({
    required this.currency,
    required this.totalItems,
    required this.totalItemsTax,
    required this.totalFees,
    required this.totalDiscount,
    required this.totalShipping,
    required this.totalShippingTax,
    required this.totalTax,
    required this.totalPrice,
  });

  /// Reads the Store API's representation.
  factory StoreCartTotals.fromJson(Map<String, Object?> json) {
    final StoreCurrency c = StoreCurrency.fromJson(json);
    return StoreCartTotals(
      currency: c,
      totalItems: StoreMoney.read(json, 'total_items', c),
      totalItemsTax: StoreMoney.read(json, 'total_items_tax', c),
      totalFees: StoreMoney.read(json, 'total_fees', c),
      totalDiscount: StoreMoney.read(json, 'total_discount', c),
      totalShipping: StoreMoney.read(json, 'total_shipping', c),
      totalShippingTax: StoreMoney.read(json, 'total_shipping_tax', c),
      totalTax: StoreMoney.read(json, 'total_tax', c),
      totalPrice: StoreMoney.read(json, 'total_price', c),
    );
  }

  /// How this store writes money.
  final StoreCurrency currency;

  /// The items, before tax.
  final StoreMoney totalItems;

  /// Tax on the items.
  final StoreMoney totalItemsTax;

  /// Fees.
  final StoreMoney totalFees;

  /// What coupons took off.
  final StoreMoney totalDiscount;

  /// Shipping, before tax.
  final StoreMoney totalShipping;

  /// Tax on the shipping.
  final StoreMoney totalShippingTax;

  /// All tax.
  final StoreMoney totalTax;

  /// What the shopper pays. This is the one to show.
  final StoreMoney totalPrice;
}

/// A problem the store reported about the cart itself.
///
/// These arrive inside a successful response, not as an error: an item that
/// went out of stock while the shopper browsed does not fail the request, it
/// annotates the cart.
class StoreCartError {
  /// Creates an error.
  const StoreCartError({required this.code, required this.message});

  /// Reads the Store API's representation.
  factory StoreCartError.fromJson(Map<String, Object?> json) => StoreCartError(
    code: readString(json['code']),
    message: readString(json['message']),
  );

  /// WooCommerce's code, such as `woocommerce_rest_product_out_of_stock`.
  final String code;

  /// Text meant for the shopper.
  final String message;

  @override
  String toString() => '$code: $message';
}

/// A shopper's cart.
class StoreCart {
  /// Creates a cart.
  const StoreCart({
    required this.items,
    required this.coupons,
    required this.totals,
    required this.billingAddress,
    required this.shippingAddress,
    required this.shippingPackages,
    required this.itemsCount,
    required this.itemsWeight,
    required this.needsPayment,
    required this.needsShipping,
    required this.hasCalculatedShipping,
    required this.errors,
    required this.raw,
    this.paymentMethods = const <String>[],
  });

  /// Reads the Store API's representation.
  factory StoreCart.fromJson(Map<String, Object?> json) => StoreCart(
    items: <StoreCartItem>[
      for (final Map<String, Object?> i in readObjects(json['items']))
        StoreCartItem.fromJson(i),
    ],
    coupons: <StoreCartCoupon>[
      for (final Map<String, Object?> c in readObjects(json['coupons']))
        StoreCartCoupon.fromJson(c),
    ],
    totals: StoreCartTotals.fromJson(readMap(json['totals'])),
    billingAddress: StoreAddress.fromJson(readMap(json['billing_address'])),
    shippingAddress: StoreAddress.fromJson(readMap(json['shipping_address'])),
    shippingPackages: <StoreShippingPackage>[
      for (final Map<String, Object?> p in readObjects(json['shipping_rates']))
        StoreShippingPackage.fromJson(p),
    ],
    itemsCount: readInt(json['items_count'], orElse: 0),
    itemsWeight: readDouble(json['items_weight']),
    needsPayment: readBool(json['needs_payment']),
    needsShipping: readBool(json['needs_shipping']),
    hasCalculatedShipping: readBool(json['has_calculated_shipping']),
    paymentMethods: <String>[
      for (final Object? m in readList(json['payment_methods'])) '$m',
    ],
    errors: <StoreCartError>[
      for (final Map<String, Object?> e in readObjects(json['errors']))
        StoreCartError.fromJson(e),
    ],
    raw: json,
  );

  /// The lines in the cart.
  final List<StoreCartItem> items;

  /// Coupons currently applied.
  final List<StoreCartCoupon> coupons;

  /// What it all adds up to.
  final StoreCartTotals totals;

  /// Billing address so far.
  final StoreAddress billingAddress;

  /// Shipping address so far.
  final StoreAddress shippingAddress;

  /// Shipment groups and the rates available to each.
  final List<StoreShippingPackage> shippingPackages;

  /// Total quantity across all lines — the number for a cart badge.
  final int itemsCount;

  /// Combined weight, in the store's weight unit.
  final double itemsWeight;

  /// Whether this cart costs anything.
  final bool needsPayment;

  /// Whether anything in it has to be shipped.
  final bool needsShipping;

  /// Whether the store has enough address to have quoted shipping.
  final bool hasCalculatedShipping;

  /// Ids of the payment methods available, such as `cod` or `stripe`.
  final List<String> paymentMethods;

  /// Problems with the cart's contents, which do not fail the request.
  final List<StoreCartError> errors;

  /// The whole cart as the store sent it.
  final Map<String, Object?> raw;

  /// Whether there is nothing in it.
  bool get isEmpty => items.isEmpty;

  /// Whether there is something in it.
  bool get isNotEmpty => items.isNotEmpty;

  /// The line for [productId], or null when it is not in the cart.
  ///
  /// Returns the first match; a product added twice with different variation
  /// options occupies two lines, which is why lines are addressed by
  /// [StoreCartItem.key] everywhere else.
  StoreCartItem? itemFor(int productId) =>
      items.where((StoreCartItem i) => i.id == productId).firstOrNull;

  /// Whether the store reported any problem with the contents.
  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() => 'StoreCart($itemsCount items, ${totals.totalPrice})';
}
