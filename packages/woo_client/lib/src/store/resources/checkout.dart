import '../../exceptions.dart';
import '../models/address.dart';
import '../models/cart.dart';
import '../models/checkout.dart';
import '../money.dart';
import '../store.dart';

/// Turning a cart into a paid order.
class StoreCheckoutResource {
  /// Wraps [_store]'s checkout routes.
  StoreCheckoutResource(this._store);

  final WooStore _store;

  /// The draft order made from the current cart.
  ///
  /// Calling this creates a `checkout-draft` order on the store, so it is not
  /// free — call it when the shopper reaches the checkout screen, not on every
  /// cart change.
  Future<StoreCheckout> get() async =>
      StoreCheckout.fromJson(await _store.getOne('/checkout'));

  /// Saves checkout fields without paying.
  ///
  /// Use this to persist the payment method or an order note as the shopper
  /// fills the form, so nothing is lost if they back out and return.
  Future<StoreCheckout> update({
    String? paymentMethod,
    String? orderNotes,
    Map<String, Object?>? additionalFields,
    bool recalculateTotals = true,
  }) async => StoreCheckout.fromJson(
    await _store.put(
      '/checkout',
      query: <String, Object?>{
        if (recalculateTotals) '__experimental_calc_totals': true,
      },
      body: <String, Object?>{
        'payment_method': ?paymentMethod,
        'order_notes': ?orderNotes,
        'additional_fields': ?additionalFields,
      },
    ),
  );

  /// Places the order and attempts payment.
  ///
  /// Check [StorePaymentResult.needsRedirect] on the way out: gateways such as
  /// PayPal finish off-site, and the order is not paid until the shopper comes
  /// back. Only [StorePaymentResult.isPaid] means done.
  ///
  /// ```dart
  /// final result = await store.checkout.submit(
  ///   billingAddress: address,
  ///   shippingAddress: address,
  ///   paymentMethod: 'cod',
  ///   expectedTotal: cart.totals.totalPrice,
  /// );
  ///
  /// if (result.paymentResult.needsRedirect) {
  ///   await launchUrl(Uri.parse(result.paymentResult.redirectUrl));
  /// }
  /// ```
  ///
  /// Pass [expectedTotal] — the total you actually showed the shopper — and
  /// the store refuses the order with [WooTotalMismatchException] if it no
  /// longer agrees, instead of charging a different amount than the one on
  /// screen. Nothing is charged when that happens, and the exception carries
  /// the refreshed cart.
  ///
  /// Set [createAccount] to register the shopper while ordering; the store
  /// must have guest account creation enabled for it to be honoured.
  Future<StoreCheckout> submit({
    required StoreAddress billingAddress,
    required String paymentMethod,
    StoreAddress? shippingAddress,
    String? customerNote,
    Map<String, Object?>? paymentData,
    StoreMoney? expectedTotal,
    bool createAccount = false,
    String? customerPassword,
    Map<String, Object?>? additionalFields,
    Map<String, Object?> extensions = const <String, Object?>{},
  }) async => StoreCheckout.fromJson(
    await _store.post(
      '/checkout',
      body: <String, Object?>{
        'billing_address': billingAddress.toJson(),
        'shipping_address': (shippingAddress ?? billingAddress).toJson(),
        'payment_method': paymentMethod,
        'customer_note': ?customerNote,
        // The wire form is a list of {key, value}, not an object.
        if (paymentData != null)
          'payment_data': <Object?>[
            for (final MapEntry<String, Object?> e in paymentData.entries)
              <String, Object?>{'key': e.key, 'value': e.value},
          ],
        if (expectedTotal != null)
          'expected_total': '${expectedTotal.minorUnits}',
        if (createAccount) 'create_account': true,
        'customer_password': ?customerPassword,
        'additional_fields': ?additionalFields,
        if (extensions.isNotEmpty) 'extensions': extensions,
      },
    ),
  );

  /// Retries payment on an order that was created but not paid.
  ///
  /// The Store API keeps a draft order after a declined card, so a shopper can
  /// try a different method without rebuilding the cart.
  Future<StoreCheckout> pay(
    int orderId, {
    required String paymentMethod,
    Map<String, Object?>? paymentData,
  }) async => StoreCheckout.fromJson(
    await _store.post(
      '/checkout/$orderId',
      body: <String, Object?>{
        'payment_method': paymentMethod,
        if (paymentData != null)
          'payment_data': <Object?>[
            for (final MapEntry<String, Object?> e in paymentData.entries)
              <String, Object?>{'key': e.key, 'value': e.value},
          ],
      },
    ),
  );

  /// Places the order, then forgets the cart on success.
  ///
  /// The convenience most apps want: after a paid order the old cart token
  /// points at a consumed cart, and reusing it is a confusing bug. This calls
  /// [submit] and clears the session only when the payment actually went
  /// through — a declined card leaves the basket intact.
  Future<StoreCheckout> submitAndClear({
    required StoreAddress billingAddress,
    required String paymentMethod,
    StoreAddress? shippingAddress,
    String? customerNote,
    Map<String, Object?>? paymentData,
    StoreMoney? expectedTotal,
  }) async {
    final StoreCheckout result = await submit(
      billingAddress: billingAddress,
      paymentMethod: paymentMethod,
      shippingAddress: shippingAddress,
      customerNote: customerNote,
      paymentData: paymentData,
      expectedTotal: expectedTotal,
    );
    if (result.isPaid) await _store.session.clear();
    return result;
  }

  /// The cart the store returned alongside a total mismatch, already parsed.
  ///
  /// ```dart
  /// try {
  ///   await store.checkout.submit(..., expectedTotal: shown);
  /// } on WooTotalMismatchException catch (e) {
  ///   final fresh = StoreCheckoutResource.cartFrom(e);
  ///   showDialog(newTotal: fresh?.totals.totalPrice);
  /// }
  /// ```
  static StoreCart? cartFrom(WooTotalMismatchException e) =>
      e.cart == null ? null : StoreCart.fromJson(e.cart!);
}
