import '../json.dart';
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
  ///
  /// Throws for [unknown]. A plugin status this package does not model has no
  /// safe wire form, and guessing one is worse than refusing: sending
  /// `pending` for a status you did not recognise moves a paid order back to
  /// unpaid. Use `WooOrders.setStatusRaw` to send a status verbatim, and
  /// `WooOrder.statusName` to read the one the store actually sent.
  String get wireName => switch (this) {
    pending => 'pending',
    processing => 'processing',
    onHold => 'on-hold',
    completed => 'completed',
    cancelled => 'cancelled',
    refunded => 'refunded',
    failed => 'failed',
    checkoutDraft => 'checkout-draft',
    unknown => throw StateError(
      'WooOrderStatus.unknown has no wire form. The store sent a status this '
      'package does not model — read it with WooOrder.statusName and send it '
      'back with WooOrders.setStatusRaw.',
    ),
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
    firstName: readString(json['first_name']),
    lastName: readString(json['last_name']),
    company: readString(json['company']),
    address1: readString(json['address_1']),
    address2: readString(json['address_2']),
    city: readString(json['city']),
    state: readString(json['state']),
    postcode: readString(json['postcode']),
    country: readString(json['country']),
    email: readString(json['email']),
    phone: readString(json['phone']),
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
    id: readInt(json['id'], orElse: 0),
    name: readString(json['name']),
    productId: readInt(json['product_id'], orElse: 0),
    variationId: readInt(json['variation_id'], orElse: 0),
    quantity: readInt(json['quantity'], orElse: 0),
    subtotal: WooPrice(readString(json['subtotal'])),
    total: WooPrice(readString(json['total'])),
    sku: readString(json['sku']),
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
      for (final Object? v in (readList(json['line_items'])))
        if (v is Map<String, Object?>) WooLineItem.fromJson(v),
    ];
    return WooOrder(
      id: readInt(json['id'], orElse: 0),
      number: readString(json['number']),
      status: WooOrderStatus.parse(json['status']),
      currency: readString(json['currency']),
      total: WooPrice(readString(json['total'])),
      // WooCommerce does not send a subtotal on the order, only per line.
      subtotal: WooPrice(
        lines.isEmpty
            ? ''
            : lines
                  .map((WooLineItem l) => l.subtotal.amountOrZero)
                  .reduce((double a, double b) => a + b)
                  .toStringAsFixed(2),
      ),
      totalTax: WooPrice(readString(json['total_tax'])),
      shippingTotal: WooPrice(readString(json['shipping_total'])),
      discountTotal: WooPrice(readString(json['discount_total'])),
      customerId: readInt(json['customer_id'], orElse: 0),
      billing: WooAddress.fromJson(readMap(json['billing'])),
      shipping: WooAddress.fromJson(readMap(json['shipping'])),
      lineItems: lines,
      paymentMethod: readString(json['payment_method']),
      paymentMethodTitle: readString(json['payment_method_title']),
      customerNote: readString(json['customer_note']),
      dateCreated: DateTime.tryParse(readString(json['date_created'])),
      datePaid: DateTime.tryParse(readString(json['date_paid'])),
      raw: json,
    );
  }

  /// The order id.
  final int id;

  /// The order number the customer sees, which can differ from [id].
  final String number;

  /// Where it is in its life.
  final WooOrderStatus status;

  /// The status exactly as the store spelled it.
  ///
  /// [status] is `unknown` for anything a plugin added — subscriptions,
  /// bookings, a shop's own workflow state. This is the original string, so a
  /// status this package does not model is still readable and still
  /// re-sendable through `WooOrders.setStatusRaw`.
  String get statusName => readString(raw['status']);

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
