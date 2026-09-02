// Every API call the README makes, compiled and run.
//
// A snippet checker only catches syntax. This catches a signature that has
// drifted — a renamed parameter, a changed type, a method that moved — which
// is the failure mode that actually reaches readers.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:woo_client/woo_client.dart';

import 'store_support.dart';

void main() {
  group('the Store API half', () {
    late FakeStoreApi api;
    late WooStore store;

    setUp(() {
      api = FakeStoreApi((http.Request r) {
        final String p = r.url.path;
        if (p.endsWith('/checkout') || p.contains('/checkout/')) {
          return checkoutJson(paymentStatus: 'success');
        }
        if (p.contains('/cart')) return cartJson();
        if (p.endsWith('/batch')) {
          return <String, Object?>{'responses': <Object?>[]};
        }
        if (p.endsWith('/collection-data')) return <String, Object?>{};
        if (RegExp(r'/products/\d+$').hasMatch(p)) return storeProductJson();
        if (p.contains('/products')) return <Object?>[storeProductJson()];
        return <String, Object?>{};
      });
      store = WooStore(
        baseUrl: 'https://your-store.com',
        httpClient: api.client,
      );
      addTearDown(store.close);
    });

    test('opening and the cart badge', () async {
      await store.cart.addItem(id: 799, quantity: 2);
      final StoreCart cart = await store.cart.get();
      expect('${cart.totals.totalPrice}', r'$82.56');
    });

    test('browsing', () async {
      final WooPage<StoreProduct> page = await store.products.list(
        search: 'beanie',
        category: 21,
        orderBy: StoreProductOrderBy.popularity,
      );
      expect(page.totalItems, isNull);
      expect(page.hasMore, isA<bool>());

      await store.products.get(799);
      await store.products.bySlug('beanie-with-logo');
      await store.products.categories();
    });

    test('money', () async {
      final StoreCart cart = await store.cart.get();
      expect('${cart.totals.totalPrice}', isNotEmpty);
      expect(cart.totals.totalPrice.minorUnits, 8256);
      expect(cart.totals.totalPrice.amount, 82.56);

      final StoreCartItem item = cart.items.first;
      final StoreMoney subtotal = item.price * item.quantity;
      expect(subtotal, isA<StoreMoney>());
    });

    test('the cart', () async {
      final StoreCart cart = await store.cart.get();
      final StoreCartItem item = cart.items.first;

      await store.cart.addItem(id: 799, quantity: 2);
      final StoreProduct p = (await store.products.list()).items.first;
      await store.cart.addItem(
        id: 815,
        variation: p.cartAttributes(<String, String>{'Colour': 'blue'}),
      );
      await store.cart.updateItem(key: item.key, quantity: 3);
      await store.cart.removeItem(item.key);
      await store.cart.applyCoupon('SAVE10');
      await store.cart.addItems(<int, int>{799: 1, 812: 2, 815: 1});

      expect(item.limits.clamp(3), 4);
      expect(item.limits.clamp(99), 12);
    });

    test('shipping', () async {
      final StoreCart cart = await store.cart.updateCustomer(
        shippingAddress: const StoreAddress(postcode: 'N1 7GU', country: 'GB'),
      );
      for (final StoreShippingPackage package in cart.shippingPackages) {
        for (final StoreShippingRate rate in package.rates) {
          expect('${rate.name} — ${rate.price}', isNotEmpty);
        }
      }
      await store.cart.selectShippingRate(packageId: 0, rateId: 'flat_rate:10');
    });

    test('checkout', () async {
      final StoreCart cart = await store.cart.get();
      const StoreAddress address = StoreAddress(country: 'GB');

      final StoreCheckout result = await store.checkout.submitAndClear(
        billingAddress: address,
        paymentMethod: 'stripe',
        expectedTotal: cart.totals.totalPrice,
      );

      if (result.paymentResult.needsRedirect) {
        expect(Uri.parse(result.paymentResult.redirectUrl), isA<Uri>());
      } else if (result.isPaid) {
        expect(result.orderId, isA<int>());
      }
    });

    test('the total-mismatch recovery', () async {
      final FakeStoreApi bumped = FakeStoreApi(
        (_) => wooError(
          409,
          'woocommerce_rest_checkout_total_mismatch',
          'moved',
          data: <String, Object?>{'cart': cartJson(totalPrice: '9000')},
        ),
      );
      final WooStore s = WooStore(
        baseUrl: 'https://your-store.com',
        httpClient: bumped.client,
      );
      addTearDown(s.close);

      try {
        await s.checkout.submit(
          billingAddress: const StoreAddress(country: 'GB'),
          paymentMethod: 'cod',
          expectedTotal: const StoreMoney(8256, StoreCurrency()),
        );
        fail('should have thrown');
      } on WooTotalMismatchException catch (e) {
        final StoreCart? fresh = StoreCheckoutResource.cartFrom(e);
        expect(fresh!.totals.totalPrice, isA<StoreMoney>());
      }
    });

    test('the raw escape hatch', () async {
      await store.getOne('/products/collection-data');
      final StoreCart cart = await store.cart.get();
      expect(cart.raw['extensions'], isNotNull);
    });
  });

  test("the README's CartTokenStore implementation compiles", () async {
    final FakeCartTokens tokens = FakeCartTokens();
    final FakeStoreApi api = FakeStoreApi((_) => cartJson());
    final WooStore store = WooStore(
      baseUrl: 'https://your-store.com',
      tokens: tokens,
      httpClient: api.client,
    );
    addTearDown(store.close);

    await store.cart.get();
    expect(await tokens.read(), 'cart-token-1');
  });

  group('the admin API half', () {
    late WooCommerce woo;
    late List<http.Request> calls;

    setUp(() {
      calls = <http.Request>[];
      woo = WooCommerce(
        baseUrl: 'https://your-store.com',
        credentials: const WooCredentials.key(
          consumerKey: 'ck',
          consumerSecret: 'cs',
        ),
        retry: const WooRetry.reads(),
        httpClient: MockClient((http.Request r) async {
          calls.add(r);
          final String path = r.url.path;
          final bool singular =
              RegExp(r'/\d+$').hasMatch(path) ||
              path.endsWith('/system_status') ||
              RegExp(r'/settings/[a-z_]+/[a-z_]+$').hasMatch(path);
          final bool wantsList = r.method == 'GET' && !singular;
          final Map<String, Object?> one = <String, Object?>{
            'id': 799,
            'name': 'Thing',
            'price': '1.00',
            'rate': '20',
            'value': 'GBP',
            'environment': <String, Object?>{'version': '9.0'},
            'line_items': <Object?>[],
            'billing': <String, Object?>{},
            'shipping': <String, Object?>{},
            'create': <Object?>[],
            'update': <Object?>[],
            'delete': <Object?>[],
          };
          return http.Response(
            jsonEncode(wantsList ? <Object?>[one] : one),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(woo.close);
    });

    test('reading', () async {
      await woo.products.list(search: 'leather', onSale: true);
      await woo.orders.get(5120);
    });

    test('every admin collection named in the README exists', () async {
      await woo.admin.productCategories.list();
      await woo.admin.productTags.list();
      await woo.admin.productAttributes.list();
      await woo.admin.reviews.list();
      await woo.admin.shippingClasses.list();
      await woo.admin.taxRates.list();
      await woo.admin.webhooks.list();
      await woo.admin.shippingZones.list();
      await woo.admin.reports.topSellers();
      await woo.admin.settings.groups();
      await woo.admin.data.countries();
      await woo.admin.systemStatus();
      await woo.admin.attributeTerms(3).list();
      await woo.admin.orderNotes(5120).list();
      await woo.admin.refunds(5120).list();
      await woo.admin.paymentGateways();
      await woo.admin.taxClasses();
      expect(calls, isNotEmpty);
    });

    test('batch', () async {
      final WooBatchResult<WooProduct> result = await woo.products.batch(
        update: <Map<String, Object?>>[
          <String, Object?>{'id': 799, 'regular_price': '119.00'},
          <String, Object?>{'id': 812, 'stock_quantity': 0},
        ],
        delete: <int>[800],
      );
      expect(result.updated, isA<List<WooProduct>>());
    });

    test('writing orders', () async {
      final WooOrder order = await woo.orders.create(
        lineItems: <WooLineItem>[
          WooLineItem.order(productId: 799, quantity: 2),
          WooLineItem.order(productId: 812, quantity: 1, variationId: 815),
        ],
        billing: const WooAddress(
          firstName: 'Ada',
          country: 'GB',
          email: 'ada@example.com',
        ),
        paymentMethod: 'stripe',
        setPaid: false,
      );
      await woo.orders.setStatus(order.id, WooOrderStatus.completed);
    });

    test('the three credential shapes', () {
      expect(
        const WooCredentials.key(consumerKey: 'ck', consumerSecret: 'cs'),
        isA<WooCredentials>(),
      );
      expect(
        const WooCredentials.applicationPassword(username: 'u', password: 'p'),
        isA<WooCredentials>(),
      );
      expect(const WooCredentials.bearer('t'), isA<WooCredentials>());
      expect(const WooRetry.none(), isA<WooRetry>());
      expect(const WooRetry.reads(), isA<WooRetry>());
      expect(const WooRetry.everything(), isA<WooRetry>());
    });

    test('the raw escape hatch', () async {
      await woo.getPage('/customers/33/downloads');
      await woo.getPage(
        '/reports/sales',
        query: <String, Object?>{'period': 'month'},
      );
    });
  });

  test('the webhook handler compiles', () {
    final String body = jsonEncode(<String, Object?>{'id': 5120});
    final WooWebhookDelivery delivery = WooWebhookDelivery.fromRequest(
      body: body,
      headers: <String, String>{
        'X-WC-Webhook-Topic': 'order.created',
        'X-WC-Webhook-Signature': WooWebhookDelivery.signatureFor(body, 's'),
      },
    );

    expect(delivery.isSignedWith('s'), isTrue);
    final Object? handled = switch (delivery.topic) {
      'order.created' => WooOrder.fromJson(delivery.json),
      'product.updated' => delivery.resourceId,
      _ => null,
    };
    expect(handled, isA<WooOrder>());
  });

  test('the error handling compiles and is exhaustive', () {
    Object? handle(WooException e) => switch (e) {
      WooNotFoundException() => null,
      final WooRateLimitException e => e.retryAfter,
      final WooAuthException e => 'Key rejected: ${e.message}',
      final WooInvalidRequestException e =>
        'Store said no: ${e.code} ${e.details}',
      WooServerException() => 'retry',
      final WooNetworkException e => 'Never reached: ${e.cause}',
      final WooBadResponseException e => 'Not JSON: ${e.body}',
      final WooTotalMismatchException e => 'Total moved: ${e.cart}',
    };
    // No default: adding an exception type is a compile error here, which is
    // the README's claim about the sealed hierarchy.
    expect(handle(const WooNotFoundException('x')), isNull);
  });

  test('the version the client advertises matches the pubspec', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    final String version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    expect(WooCommerce.userAgent, 'woo_client/$version (Dart)');
  });
}

/// The README's CartTokenStore example, with the SharedPreferences swapped for
/// a map so it can run here.
class FakeCartTokens implements CartTokenStore {
  final Map<String, String> _prefs = <String, String>{};

  @override
  Future<String?> read() async => _prefs['woo_cart_token'];

  @override
  Future<void> write(String? token) async => token == null
      ? _prefs.remove('woo_cart_token')
      : _prefs['woo_cart_token'] = token;
}
