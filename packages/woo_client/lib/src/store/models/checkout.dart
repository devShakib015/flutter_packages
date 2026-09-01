import '../../json.dart';
import 'address.dart';

/// What happened when the store tried to take payment.
enum StorePaymentStatus {
  /// Paid.
  success,

  /// The gateway declined it.
  failure,

  /// Started, but not finished — usually means [StorePaymentResult.redirectUrl]
  /// is set and the shopper has to go somewhere.
  pending,

  /// The gateway itself broke.
  error,

  /// The store sent a status this package does not know.
  unknown;

  /// Reads WooCommerce's own spelling.
  static StorePaymentStatus parse(String? wire) => switch (wire) {
    'success' => success,
    'failure' => failure,
    'pending' => pending,
    'error' => error,
    _ => unknown,
  };
}

/// The outcome of a payment attempt.
class StorePaymentResult {
  /// Creates a result.
  const StorePaymentResult({
    required this.status,
    this.redirectUrl = '',
    this.details = const <String, String>{},
    this.message = '',
  });

  /// Reads the Store API's representation.
  factory StorePaymentResult.fromJson(Map<String, Object?> json) =>
      StorePaymentResult(
        status: StorePaymentStatus.parse(readString(json['payment_status'])),
        redirectUrl: readString(json['redirect_url']),
        // Sent as a list of {key, value} pairs, which is awkward to read.
        details: <String, String>{
          for (final Object? d in readList(json['payment_details']))
            if (d is Map<String, Object?>)
              '${d['key'] ?? ''}': '${d['value'] ?? ''}',
        },
        message: readString(json['message']),
      );

  /// Whether the payment went through.
  final StorePaymentStatus status;

  /// Where to send the shopper next, for gateways that take over.
  ///
  /// Empty when the payment finished on the spot. When it is set, open it —
  /// the order is not paid until the shopper comes back.
  final String redirectUrl;

  /// Whatever the gateway attached, flattened from its key/value pairs.
  final Map<String, String> details;

  /// A message from the gateway, usually only on failure.
  final String message;

  /// Whether the shopper has to be sent somewhere to finish paying.
  bool get needsRedirect => redirectUrl.isNotEmpty;

  /// Whether the order is paid and done.
  bool get isPaid => status == StorePaymentStatus.success;
}

/// A checkout: the draft order made from a cart, and the result of paying.
class StoreCheckout {
  /// Creates a checkout.
  const StoreCheckout({
    required this.orderId,
    required this.status,
    required this.orderKey,
    required this.billingAddress,
    required this.shippingAddress,
    required this.paymentResult,
    required this.raw,
    this.customerId = 0,
    this.customerNote = '',
    this.paymentMethod = '',
    this.additionalFields = const <String, Object?>{},
  });

  /// Reads the Store API's representation.
  factory StoreCheckout.fromJson(Map<String, Object?> json) => StoreCheckout(
    orderId: readInt(json['order_id'], orElse: 0),
    status: readString(json['status']),
    orderKey: readString(json['order_key']),
    customerId: readInt(json['customer_id'], orElse: 0),
    customerNote: readString(json['customer_note']),
    paymentMethod: readString(json['payment_method']),
    billingAddress: StoreAddress.fromJson(readMap(json['billing_address'])),
    shippingAddress: StoreAddress.fromJson(readMap(json['shipping_address'])),
    paymentResult: StorePaymentResult.fromJson(readMap(json['payment_result'])),
    additionalFields: readMap(json['additional_fields']),
    raw: json,
  );

  /// The order this checkout is for. Exists from the moment you ask for a
  /// checkout, as a `checkout-draft`.
  final int orderId;

  /// The order's status. `checkout-draft` until payment is attempted.
  final String status;

  /// The key that, with [orderId], identifies the order publicly. Needed to
  /// look the order up afterwards without logging in.
  final String orderKey;

  /// The logged-in customer, or 0 for a guest.
  final int customerId;

  /// A note the shopper left.
  final String customerNote;

  /// The chosen payment method id.
  final String paymentMethod;

  /// Billing address on the order.
  final StoreAddress billingAddress;

  /// Shipping address on the order.
  final StoreAddress shippingAddress;

  /// How payment went. Empty until you submit.
  final StorePaymentResult paymentResult;

  /// Extra checkout fields registered by plugins.
  final Map<String, Object?> additionalFields;

  /// The whole response as the store sent it.
  final Map<String, Object?> raw;

  /// Whether the order was paid.
  bool get isPaid => paymentResult.isPaid;

  /// The URL where a guest can view this order, given the store's base URL.
  ///
  /// WooCommerce's order-received page needs both the id and the key.
  Uri receivedUrl(String baseUrl) => Uri.parse(
    '${baseUrl.replaceAll(RegExp(r'/+$'), '')}'
    '/checkout/order-received/$orderId/?key=$orderKey',
  );

  @override
  String toString() => 'StoreCheckout(order $orderId, $status)';
}
