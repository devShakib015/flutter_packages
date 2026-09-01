import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:woo_client/woo_client.dart';

import 'store_support.dart';

void main() {
  const StoreAddress ada = StoreAddress(
    firstName: 'Ada',
    lastName: 'Lovelace',
    address1: '12 Analytical Way',
    city: 'London',
    postcode: 'N1 7GU',
    country: 'GB',
    email: 'ada@example.com',
  );

  ({FakeStoreApi api, WooStore store}) make(
    Object? Function(http.Request) reply,
  ) {
    final FakeStoreApi api = FakeStoreApi(reply);
    final WooStore store = WooStore(
      baseUrl: 'https://shop.test',
      httpClient: api.client,
    );
    addTearDown(store.close);
    return (api: api, store: store);
  }

  test('the draft order is readable before paying', () async {
    final ({FakeStoreApi api, WooStore store}) t = make((_) => checkoutJson());
    final StoreCheckout draft = await t.store.checkout.get();
    expect(draft.orderId, 146);
    expect(draft.status, 'checkout-draft');
    expect(draft.isPaid, isFalse);
    expect(draft.billingAddress.fullName, 'Ada Lovelace');
  });

  test('submit sends both addresses and the payment method', () async {
    final ({FakeStoreApi api, WooStore store}) t = make(
      (_) => checkoutJson(status: 'processing', paymentStatus: 'success'),
    );

    final StoreCheckout result = await t.store.checkout.submit(
      billingAddress: ada,
      paymentMethod: 'cod',
    );

    expect(t.api.calls.last.method, 'POST');
    expect(t.api.lastUri.path, endsWith('/checkout'));
    expect(t.api.lastBody['payment_method'], 'cod');
    // Shipping defaults to billing rather than being left blank, which is
    // what a store needs to quote and what a shopper means.
    expect(
      (t.api.lastBody['shipping_address']! as Map<String, Object?>)['postcode'],
      'N1 7GU',
    );
    expect(result.isPaid, isTrue);
  });

  test('payment data goes as key/value pairs, not an object', () async {
    final ({FakeStoreApi api, WooStore store}) t = make((_) => checkoutJson());
    await t.store.checkout.submit(
      billingAddress: ada,
      paymentMethod: 'stripe',
      paymentData: const <String, Object?>{'stripe_source': 'src_123'},
    );
    expect(t.api.lastBody['payment_data'], <Object?>[
      <String, Object?>{'key': 'stripe_source', 'value': 'src_123'},
    ]);
  });

  test('expectedTotal is sent in minor units', () async {
    final ({FakeStoreApi api, WooStore store}) t = make((_) => checkoutJson());
    const StoreMoney total = StoreMoney(8256, StoreCurrency(code: 'USD'));

    await t.store.checkout.submit(
      billingAddress: ada,
      paymentMethod: 'cod',
      expectedTotal: total,
    );
    // "8256", not "82.56" — sending the decimal would never match.
    expect(t.api.lastBody['expected_total'], '8256');
  });

  test(
    'a moved total is its own exception, and carries the new cart',
    () async {
      final ({FakeStoreApi api, WooStore store}) t = make(
        (_) => wooError(
          409,
          'woocommerce_rest_checkout_total_mismatch',
          'The cart has been updated since you last viewed it.',
          data: <String, Object?>{'cart': cartJson(totalPrice: '9000')},
        ),
      );

      try {
        await t.store.checkout.submit(
          billingAddress: ada,
          paymentMethod: 'cod',
          expectedTotal: const StoreMoney(8256, StoreCurrency()),
        );
        fail('should have thrown');
      } on WooTotalMismatchException catch (e) {
        // Nothing was charged, and the shopper can be shown the real number
        // without a second round trip.
        final StoreCart? fresh = StoreCheckoutResource.cartFrom(e);
        expect(fresh?.totals.totalPrice.toString(), r'$90.00');
      }
    },
  );

  test(
    'an off-site gateway says so instead of pretending it is done',
    () async {
      final ({FakeStoreApi api, WooStore store}) t = make(
        (_) => checkoutJson(
          paymentStatus: 'pending',
          redirectUrl: 'https://paypal.test/pay/abc',
        ),
      );

      final StoreCheckout result = await t.store.checkout.submit(
        billingAddress: ada,
        paymentMethod: 'paypal',
      );

      expect(result.paymentResult.status, StorePaymentStatus.pending);
      expect(result.paymentResult.needsRedirect, isTrue);
      expect(result.isPaid, isFalse, reason: 'not paid until they come back');
    },
  );

  test('a declined card is a failure, not an exception', () async {
    // The request succeeded; the payment did not. Throwing here would lose
    // the order id the shopper needs to retry against.
    final ({FakeStoreApi api, WooStore store}) t = make(
      (_) => checkoutJson(paymentStatus: 'failure'),
    );
    final StoreCheckout result = await t.store.checkout.submit(
      billingAddress: ada,
      paymentMethod: 'stripe',
    );
    expect(result.paymentResult.status, StorePaymentStatus.failure);
    expect(result.orderId, 146);
  });

  test('submitAndClear forgets the cart only when paid', () async {
    String status = 'failure';
    final FakeStoreApi api = FakeStoreApi(
      (http.Request r) => r.url.path.endsWith('/checkout')
          ? checkoutJson(paymentStatus: status)
          : cartJson(),
    );
    final WooStore store = WooStore(
      baseUrl: 'https://shop.test',
      httpClient: api.client,
    );
    addTearDown(store.close);

    await store.cart.get();
    expect(await store.session.cartToken, isNotNull);

    await store.checkout.submitAndClear(
      billingAddress: ada,
      paymentMethod: 'stripe',
    );
    expect(
      await store.session.cartToken,
      isNotNull,
      reason: 'a declined card must leave the basket alone',
    );

    status = 'success';
    await store.checkout.submitAndClear(
      billingAddress: ada,
      paymentMethod: 'stripe',
    );
    expect(await store.session.cartToken, isNull);
  });

  test('an unpaid order can be paid again at its own route', () async {
    final ({FakeStoreApi api, WooStore store}) t = make(
      (_) => checkoutJson(paymentStatus: 'success'),
    );
    await t.store.checkout.pay(146, paymentMethod: 'bacs');
    expect(t.api.lastUri.path, endsWith('/checkout/146'));
    expect(t.api.lastBody['payment_method'], 'bacs');
  });

  test('update persists a field without paying', () async {
    final ({FakeStoreApi api, WooStore store}) t = make((_) => checkoutJson());
    await t.store.checkout.update(
      paymentMethod: 'cod',
      orderNotes: 'Ring bell',
    );
    expect(t.api.calls.last.method, 'PUT');
    expect(t.api.lastUri.queryParameters['__experimental_calc_totals'], 'true');
    expect(t.api.lastBody['order_notes'], 'Ring bell');
  });

  test('the order-received link is buildable for a guest', () {
    final StoreCheckout c = StoreCheckout.fromJson(checkoutJson());
    final Uri url = c.receivedUrl('https://shop.test/');
    expect(url.path, '/checkout/order-received/146/');
    expect(url.queryParameters['key'], 'wc_order_VPffqyvgWVqWL');
  });

  test('an unknown payment status degrades instead of throwing', () {
    final StoreCheckout c = StoreCheckout.fromJson(
      checkoutJson(paymentStatus: 'awaiting_3ds'),
    );
    expect(c.paymentResult.status, StorePaymentStatus.unknown);
    expect(c.raw['payment_result'], isNotNull);
  });
}
