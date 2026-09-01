import 'money.dart';

/// Where an order is in its life.
enum WooOrderStatus {
  /// Awaiting payment.
  pending,

  /// Paid, awaiting fulfilment.
  processing,

  /// Paid, waiting on stock or the customer.
  onHold,

  /// Fulfilled.
  completed,

  /// Cancelled before fulfilment.
  cancelled,

  /// Money returned.
  refunded,

  /// Payment failed.
  failed,

  /// Created but never submitted.
  checkoutDraft,

  /// A status this client does not know — often added by a plugin. The
  /// original string is in [WooOrder.raw] under `status`.
  unknown;

  /// Reads WooCommerce's value.
  static WooOrderStatus parse(Object? value) => switch (value) {
    'pending' => pending,
    'processing' => processing,
    'on-hold' => onHold,
    'completed' => completed,
    'cancelled' => cancelled,
    'refunded' => refunded,
    'failed' => failed,
    'checkout-draft' => checkoutDraft,
    _ => unknown,
  };

  /// The string WooCommerce expects back.
  String get wireName => switch (this) {
    pending => 'pending',
    processing => 'processing',
    onHold => 'on-hold',
    completed => 'completed',
    cancelled => 'cancelled',
    refunded => 'refunded',
    failed => 'failed',
    checkoutDraft => 'checkout-draft',
    unknown => 'pending',
  };
}

/// A postal address on an order.
class WooAddress {
  /// Creates an address.
  const WooAddress({
    this.firstName = '',
    this.lastName = '',
    this.company = '',
    this.address1 = '',
    this.address2 = '',
    this.city = '',
    this.state = '',
    this.postcode = '',
    this.country = '',
    this.email = '',
    this.phone = '',
  });

  /// Reads WooCommerce's representation.
  factory WooAddress.fromJson(Map<String, Object?> json) => WooAddress(
    firstName: json['first_name'] as String? ?? '',
    lastName: json['last_name'] as String? ?? '',
    company: json['company'] as String? ?? '',
    address1: json['address_1'] as String? ?? '',
    address2: json['address_2'] as String? ?? '',
    city: json['city'] as String? ?? '',
    state: json['state'] as String? ?? '',
    postcode: json['postcode'] as String? ?? '',
    country: json['country'] as String? ?? '',
    email: json['email'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
  );

  /// Given name.
  final String firstName;

  /// Family name.
  final String lastName;

  /// Company, when given.
  final String company;

  /// First address line.
  final String address1;

  /// Second address line.
  final String address2;

  /// City or town.
  final String city;

  /// State, county or region.
  final String state;

  /// Postal or ZIP code.
  final String postcode;

  /// Two-letter country code.
  final String country;

  /// Email. WooCommerce only carries this on the billing address.
  final String email;

  /// Phone number.
  final String phone;

  /// The wire form, for creating or updating an order.
  Map<String, Object?> toJson() => <String, Object?>{
    'first_name': firstName,
    'last_name': lastName,
    'company': company,
    'address_1': address1,
    'address_2': address2,
    'city': city,
    'state': state,
    'postcode': postcode,
    'country': country,
    if (email.isNotEmpty) 'email': email,
    if (phone.isNotEmpty) 'phone': phone,
  };

  /// Both names, trimmed.
  String get fullName => '$firstName $lastName'.trim();

  @override
  String toString() => 'WooAddress($fullName, $city, $country)';
}

/// One line on an order.
class WooLineItem {
  /// Creates a line item.
  const WooLineItem({
    required this.id,
    required this.name,
    required this.productId,
    required this.variationId,
    required this.quantity,
    required this.subtotal,
    required this.total,
    required this.sku,
    required this.raw,
  });

  /// Reads WooCommerce's representation.
  factory WooLineItem.fromJson(Map<String, Object?> json) => WooLineItem(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    productId: (json['product_id'] as num?)?.toInt() ?? 0,
    variationId: (json['variation_id'] as num?)?.toInt() ?? 0,
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    subtotal: WooPrice(json['subtotal'] as String? ?? ''),
    total: WooPrice(json['total'] as String? ?? ''),
    sku: json['sku'] as String? ?? '',
    raw: json,
  );

  /// Creates a line for an order being placed.
  ///
  /// Only the product and quantity are needed — WooCommerce prices the line
  /// itself, which is the point: a client that sent its own prices would let
  /// a tampered app decide what things cost.
  factory WooLineItem.order({
    required int productId,
    required int quantity,
    int? variationId,
  }) => WooLineItem(
    id: 0,
    name: '',
    productId: productId,
    variationId: variationId ?? 0,
    quantity: quantity,
    subtotal: WooPrice.none,
    total: WooPrice.none,
    sku: '',
    raw: const <String, Object?>{},
  );

  /// The line id, zero for a line not yet saved.
  final int id;

  /// The product name as it was when ordered.
  final String name;

  /// Which product.
  final int productId;

  /// Which variation, zero when not a variable product.
  final int variationId;

  /// How many.
  final int quantity;

  /// Line total before discounts.
  final WooPrice subtotal;

  /// Line total after discounts.
  final WooPrice total;

  /// The SKU as it was when ordered.
  final String sku;

  /// Everything WooCommerce sent for this line.
  final Map<String, Object?> raw;

  /// The wire form for creating an order.
  Map<String, Object?> toJson() => <String, Object?>{
    'product_id': productId,
    if (variationId != 0) 'variation_id': variationId,
    'quantity': quantity,
  };

  @override
  String toString() => 'WooLineItem($quantity x $productId)';
}

/// An order in the store.
class WooOrder {
  /// Creates an order.
  const WooOrder({
    required this.id,
    required this.number,
    required this.status,
    required this.currency,
    required this.total,
    required this.subtotal,
    required this.totalTax,
    required this.shippingTotal,
    required this.discountTotal,
    required this.customerId,
    required this.billing,
    required this.shipping,
    required this.lineItems,
    required this.paymentMethod,
    required this.paymentMethodTitle,
    required this.customerNote,
    required this.dateCreated,
    required this.datePaid,
    required this.raw,
  });

  /// Reads WooCommerce's representation.
  factory WooOrder.fromJson(Map<String, Object?> json) {
    final List<WooLineItem> lines = <WooLineItem>[
      for (final Object? v
          in (json['line_items'] as List<Object?>? ?? const <Object?>[]))
        if (v is Map<String, Object?>) WooLineItem.fromJson(v),
    ];
    return WooOrder(
      id: (json['id'] as num?)?.toInt() ?? 0,
      number: json['number'] as String? ?? '',
      status: WooOrderStatus.parse(json['status']),
      currency: json['currency'] as String? ?? '',
      total: WooPrice(json['total'] as String? ?? ''),
      // WooCommerce does not send a subtotal on the order, only per line.
      subtotal: WooPrice(
        lines.isEmpty
            ? ''
            : lines
                  .map((WooLineItem l) => l.subtotal.amountOrZero)
                  .reduce((double a, double b) => a + b)
                  .toStringAsFixed(2),
      ),
      totalTax: WooPrice(json['total_tax'] as String? ?? ''),
      shippingTotal: WooPrice(json['shipping_total'] as String? ?? ''),
      discountTotal: WooPrice(json['discount_total'] as String? ?? ''),
      customerId: (json['customer_id'] as num?)?.toInt() ?? 0,
      billing: WooAddress.fromJson(
        json['billing'] as Map<String, Object?>? ?? const <String, Object?>{},
      ),
      shipping: WooAddress.fromJson(
        json['shipping'] as Map<String, Object?>? ?? const <String, Object?>{},
      ),
      lineItems: lines,
      paymentMethod: json['payment_method'] as String? ?? '',
      paymentMethodTitle: json['payment_method_title'] as String? ?? '',
      customerNote: json['customer_note'] as String? ?? '',
      dateCreated: DateTime.tryParse(json['date_created'] as String? ?? ''),
      datePaid: DateTime.tryParse(json['date_paid'] as String? ?? ''),
      raw: json,
    );
  }

  /// The order id.
  final int id;

  /// The order number the customer sees, which can differ from [id].
  final String number;

  /// Where it is in its life.
  final WooOrderStatus status;

  /// Currency code, such as `GBP`.
  final String currency;

  /// What the customer pays in total.
  final WooPrice total;

  /// The sum of the line subtotals, computed here — WooCommerce sends this
  /// per line rather than on the order.
  final WooPrice subtotal;

  /// Tax included in [total].
  final WooPrice totalTax;

  /// Shipping included in [total].
  final WooPrice shippingTotal;

  /// Discount applied.
  final WooPrice discountTotal;

  /// The customer's id, zero for a guest.
  final int customerId;

  /// Where the invoice goes.
  final WooAddress billing;

  /// Where the goods go.
  final WooAddress shipping;

  /// What was ordered.
  final List<WooLineItem> lineItems;

  /// Gateway id, such as `stripe`.
  final String paymentMethod;

  /// Gateway name as shown to the customer.
  final String paymentMethodTitle;

  /// Anything the customer wrote at checkout.
  final String customerNote;

  /// When it was placed.
  final DateTime? dateCreated;

  /// When it was paid, null if it has not been.
  final DateTime? datePaid;

  /// Everything WooCommerce sent, untouched.
  final Map<String, Object?> raw;

  /// Whether the money has arrived.
  bool get isPaid => datePaid != null;

  /// Whether it was placed without an account.
  bool get isGuest => customerId == 0;

  /// How many items in total, counting quantities.
  int get itemCount =>
      lineItems.fold(0, (int sum, WooLineItem l) => sum + l.quantity);

  @override
  String toString() => 'WooOrder(#$number, ${status.name}, $total $currency)';
}
