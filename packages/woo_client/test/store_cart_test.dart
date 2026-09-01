import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:woo_client/woo_client.dart';

import 'store_support.dart';

void main() {
  WooStore storeFor(FakeStoreApi api, {CartTokenStore? tokens}) => WooStore(
    baseUrl: 'https://shop.test',
    httpClient: api.client,
    tokens: tokens,
  );

  group('no keys are involved', () {
    test('a plain http store is allowed, because nothing is secret', () {
      // The whole point of the Store API: there is no credential to leak, so
      // a local dev store over http is fine.
      final WooStore store = WooStore(baseUrl: 'http://localhost:8080');
      addTearDown(store.close);
      expect(store, isA<WooStore>());
    });

    test('the route is the public one', () async {
      final FakeStoreApi api = FakeStoreApi((_) => cartJson());
      final WooStore store = storeFor(api);
      addTearDown(store.close);
      await store.cart.get();
      expect(api.lastUri.path, '/wp-json/wc/store/v1/cart');
      expect(api.lastUri.queryParameters.containsKey('consumer_key'), isFalse);
    });
  });

  group('the cart token', () {
    test('is taken from the first response and sent on the next', () async {
      final FakeStoreApi api = FakeStoreApi((_) => cartJson());
      final WooStore store = storeFor(api);
      addTearDown(store.close);

      await store.cart.get();
      expect(
        api.calls.first.headers.containsKey('Cart-Token'),
        isFalse,
        reason: 'there is no cart yet on the first call',
      );

      await store.cart.get();
      expect(api.lastSentToken, 'cart-token-1');
      expect(await store.session.cartToken, 'cart-token-1');
    });

    test('a rotated token replaces the old one', () async {
      // Stores rotate cart tokens. Keeping the first one forever silently
      // detaches the app from the cart the store thinks it is talking about.
      int n = 0;
      final WooStore store = WooStore(
        baseUrl: 'https://shop.test',
        httpClient: MockClient((http.Request request) async {
          n++;
          return http.Response(
            jsonEncode(cartJson()),
            200,
            headers: <String, String>{
              'content-type': 'application/json',
              'Cart-Token': 'token-$n',
            },
          );
        }),
      );
      addTearDown(store.close);

      await store.cart.get();
      expect(await store.session.cartToken, 'token-1');
      await store.cart.get();
      expect(await store.session.cartToken, 'token-2');
    });

    test(
      'survives into a store built later, given a persistent tokens store',
      () async {
        final InMemoryCartTokenStore tokens = InMemoryCartTokenStore();
        final FakeStoreApi api = FakeStoreApi((_) => cartJson());

        final WooStore first = storeFor(api, tokens: tokens);
        await first.cart.get();
        first.close();

        // A real app would back this with shared_preferences; the contract is
        // the same — the basket outlives the process.
        final WooStore second = storeFor(api, tokens: tokens);
        addTearDown(second.close);
        await second.cart.get();
        expect(api.lastSentToken, 'cart-token-1');
      },
    );

    test('clearing forgets the cart', () async {
      final FakeStoreApi api = FakeStoreApi((_) => cartJson());
      final WooStore store = storeFor(api);
      addTearDown(store.close);

      await store.cart.get();
      await store.session.clear();
      expect(await store.session.cartToken, isNull);

      await store.cart.get();
      expect(api.calls.last.headers.containsKey('Cart-Token'), isFalse);
    });

    test('a token from elsewhere can be adopted', () async {
      final FakeStoreApi api = FakeStoreApi(
        (_) => cartJson(),
        issueToken: null,
      );
      final WooStore store = storeFor(api);
      addTearDown(store.close);

      // Handing a cart from a web view to the app, for instance.
      await store.session.adopt('from-the-web-view');
      await store.cart.get();
      expect(api.lastSentToken, 'from-the-web-view');
    });

    test('a Nonce the store sends is echoed back', () async {
      final FakeStoreApi api = FakeStoreApi(
        (_) => cartJson(),
        issueToken: null,
      );
      final WooStore store = WooStore(
        baseUrl: 'https://shop.test',
        httpClient: api.client,
      );
      addTearDown(store.close);
      await store.cart.get();
      // Our fake sends no Nonce, so none is echoed — the absence is the point:
      // a token-based client never invents one.
      expect(api.calls.last.headers.containsKey('Nonce'), isFalse);
      expect(store.session.nonce, isNull);
    });
  });

  group('reading a cart', () {
    late StoreCart cart;

    setUp(() async {
      final FakeStoreApi api = FakeStoreApi((_) => cartJson());
      final WooStore store = WooStore(
        baseUrl: 'https://shop.test',
        httpClient: api.client,
      );
      addTearDown(store.close);
      cart = await store.cart.get();
    });

    test('prices come out as the store would print them', () {
      expect(cart.totals.totalPrice.toString(), r'$82.56');
      expect(cart.totals.totalDiscount.toString(), r'$10.95');
      expect(cart.items.single.price.toString(), r'$18.00');
    });

    test('reads the line', () {
      final StoreCartItem item = cart.items.single;
      expect(item.key, 'a5771bce93e200c36f7cd9dfd0e5deaa');
      expect(item.id, 38);
      expect(item.name, 'Beanie with Logo');
      expect(item.sku, 'Woo-beanie-logo');
      expect(item.onSale, isTrue);
      expect(item.variation, <String, String>{'pa_colour': 'blue'});
      expect(item.image?.thumbnail, endsWith('450x450.jpg'));
    });

    test('quantity limits know about multiples', () {
      final StoreQuantityLimits limits = cart.items.single.limits;
      // Sold in twos, twelve at most. A naive clamp would offer 13, or 3.
      expect(limits.clamp(3), 4);
      expect(limits.clamp(99), 12);
      expect(limits.clamp(0), 1);
    });

    test('shipping packages carry their rates and which is chosen', () {
      final StoreShippingPackage pkg = cart.shippingPackages.single;
      expect(pkg.rates, hasLength(2));
      expect(pkg.selected?.rateId, 'flat_rate:10');
      expect(pkg.selected?.price.toString(), r'$13.00');
      expect(pkg.rates.last.isFree, isTrue);
    });

    test('addresses parse', () {
      expect(cart.billingAddress.fullName, 'John Doe');
      expect(cart.billingAddress.email, 'john@example.com');
      expect(cart.shippingAddress.email, isEmpty);
      expect(cart.shippingAddress.isEmpty, isFalse);
    });

    test('the badge number and the payment methods are there', () {
      expect(cart.itemsCount, 1);
      expect(cart.paymentMethods, <String>['cod', 'bacs']);
      expect(cart.needsShipping, isTrue);
      expect(cart.isNotEmpty, isTrue);
    });

    test('a line is findable by product id', () {
      expect(cart.itemFor(38)?.name, 'Beanie with Logo');
      expect(cart.itemFor(999), isNull);
    });
  });

  test('cart errors arrive inside a successful response', () async {
    // An item going out of stock while the shopper browsed does not fail the
    // request — it annotates the cart. Treating that as an error loses it.
    final FakeStoreApi api = FakeStoreApi(
      (_) => cartJson(
        errors: <Object?>[
          <String, Object?>{
            'code': 'woocommerce_rest_product_partially_out_of_stock',
            'message': 'Beanie with Logo has only 2 left.',
          },
        ],
      ),
    );
    final WooStore store = WooStore(
      baseUrl: 'https://shop.test',
      httpClient: api.client,
    );
    addTearDown(store.close);

    final StoreCart cart = await store.cart.get();
    expect(cart.hasErrors, isTrue);
    expect(cart.errors.single.message, contains('only 2 left'));
  });

  group('changing a cart', () {
    late FakeStoreApi api;
    late WooStore store;

    setUp(() {
      api = FakeStoreApi((_) => cartJson());
      store = WooStore(baseUrl: 'https://shop.test', httpClient: api.client);
      addTearDown(store.close);
    });

    test('addItem sends id and quantity', () async {
      await store.cart.addItem(id: 38, quantity: 2);
      expect(api.lastUri.path, endsWith('/cart/add-item'));
      expect(api.calls.last.method, 'POST');
      expect(api.lastBody, <String, Object?>{'id': 38, 'quantity': 2});
    });

    test('a variation is sent as attribute/value pairs, not a map', () async {
      await store.cart.addItem(
        id: 815,
        variation: <String, String>{'pa_colour': 'blue', 'Size': 'Large'},
      );
      expect(api.lastBody['variation'], <Object?>[
        <String, Object?>{'attribute': 'pa_colour', 'value': 'blue'},
        <String, Object?>{'attribute': 'Size', 'value': 'Large'},
      ]);
    });

    test('updateItem and removeItem address the line key', () async {
      await store.cart.updateItem(key: 'abc', quantity: 4);
      expect(api.lastBody, <String, Object?>{'key': 'abc', 'quantity': 4});

      await store.cart.removeItem('abc');
      expect(api.lastUri.path, endsWith('/cart/remove-item'));
      expect(api.lastBody, <String, Object?>{'key': 'abc'});
    });

    test(
      'coupon codes are lowercased, because WooCommerce stores them so',
      () async {
        await store.cart.applyCoupon('SAVE10');
        expect(api.lastBody, <String, Object?>{'code': 'save10'});
        await store.cart.removeCoupon('SAVE10');
        expect(api.lastBody, <String, Object?>{'code': 'save10'});
      },
    );

    test(
      'updateCustomer sends the whole address, empty fields included',
      () async {
        // Omitting an empty field would make it impossible to clear a line the
        // shopper deleted.
        await store.cart.updateCustomer(
          shippingAddress: const StoreAddress(
            postcode: 'N1 7GU',
            country: 'GB',
          ),
        );
        final Map<String, Object?> sent =
            api.lastBody['shipping_address']! as Map<String, Object?>;
        expect(sent['postcode'], 'N1 7GU');
        expect(sent['country'], 'GB');
        expect(sent['address_2'], '');
        expect(sent.containsKey('email'), isFalse);
      },
    );

    test('selectShippingRate names the package and the rate', () async {
      await store.cart.selectShippingRate(
        packageId: 0,
        rateId: 'free_shipping:11',
      );
      expect(api.lastBody, <String, Object?>{
        'package_id': 0,
        'rate_id': 'free_shipping:11',
      });
    });
  });

  group('batching', () {
    test('adding several items is one request, not several', () async {
      final FakeStoreApi api = FakeStoreApi((http.Request request) {
        if (request.url.path.endsWith('/batch')) {
          return <String, Object?>{'responses': <Object?>[]};
        }
        return cartJson();
      });
      final WooStore store = WooStore(
        baseUrl: 'https://shop.test',
        httpClient: api.client,
      );
      addTearDown(store.close);

      await store.cart.addItems(<int, int>{38: 1, 39: 2});

      final http.Request batch = api.calls.firstWhere(
        (http.Request r) => r.url.path.endsWith('/batch'),
      );
      final List<Object?> requests =
          (jsonDecode(batch.body) as Map<String, Object?>)['requests']!
              as List<Object?>;
      expect(requests, hasLength(2));
      expect(
        (requests.first! as Map<String, Object?>)['path'],
        '/wp-json/wc/store/v1/cart/add-item',
      );
      // One batch plus one refresh, not two adds plus a refresh.
      expect(
        api.calls.where((http.Request r) => r.url.path.endsWith('add-item')),
        isEmpty,
      );
    });

    test('clearing an empty cart does not call batch at all', () async {
      final FakeStoreApi api = FakeStoreApi(
        (_) => <String, Object?>{...cartJson(), 'items': <Object?>[]},
      );
      final WooStore store = WooStore(
        baseUrl: 'https://shop.test',
        httpClient: api.client,
      );
      addTearDown(store.close);

      await store.cart.clear();
      expect(
        api.calls.where((http.Request r) => r.url.path.endsWith('/batch')),
        isEmpty,
      );
    });
  });
}
