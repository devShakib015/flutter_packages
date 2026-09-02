// Each of these pins a defect found by the 2026-09-02 audit. The comment on
// each says what shipped, so a regression reads as a regression.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:woo_client/woo_client.dart';

import 'store_support.dart';
import 'support.dart';

void main() {
  group('credentials never reach an exception message', () {
    test('a network failure redacts the key and secret', () async {
      // Shipped in 0.2.x: 'Could not reach https://…?consumer_secret=cs_live…'
      // Anyone logging the exception shipped their store credentials to their
      // crash reporter.
      final WooCommerce woo = WooCommerce(
        baseUrl: 'https://shop.test',
        credentials: const WooCredentials.key(
          consumerKey: 'ck_live_SECRETKEY',
          consumerSecret: 'cs_live_SECRETVALUE',
        ),
        httpClient: MockClient((_) async => throw const _Offline()),
      );
      addTearDown(woo.close);

      try {
        await woo.products.list();
        fail('should have thrown');
      } on WooNetworkException catch (e) {
        expect(e.message, contains('REDACTED'));
        expect(e.message, isNot(contains('cs_live_SECRETVALUE')));
        expect(e.message, isNot(contains('ck_live_SECRETKEY')));
        expect(e.toString(), isNot(contains('SECRET')));
      }
    });

    test('a bearer token is not in the query, so nothing to redact', () async {
      final WooCommerce woo = WooCommerce(
        baseUrl: 'https://shop.test',
        credentials: const WooCredentials.bearer('jwt'),
        httpClient: MockClient((_) async => throw const _Offline()),
      );
      addTearDown(woo.close);
      await expectLater(
        woo.products.list(),
        throwsA(
          isA<WooNetworkException>().having(
            (WooNetworkException e) => e.message,
            'message',
            isNot(contains('jwt')),
          ),
        ),
      );
    });
  });

  group('an unmodelled order status is never guessed', () {
    test('wireName refuses rather than inventing pending', () {
      // Shipped in 0.2.x: unknown.wireName was 'pending'. Reading an order
      // with a plugin status and re-saving it moved a paid order to unpaid.
      expect(() => WooOrderStatus.unknown.wireName, throwsStateError);
    });

    test('the original spelling is still readable', () {
      final WooOrder o = WooOrder.fromJson(
        orderJson(status: 'awaiting-pickup'),
      );
      expect(o.status, WooOrderStatus.unknown);
      expect(o.statusName, 'awaiting-pickup');
    });

    test('setStatusRaw sends a plugin status verbatim', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(orderJson(status: 'awaiting-pickup')),
      );
      final WooCommerce woo = _admin(store);
      addTearDown(woo.close);

      await woo.orders.setStatusRaw(5120, 'awaiting-pickup');
      expect(store.lastBody['status'], 'awaiting-pickup');
    });

    test(
      'unknown is dropped from a status filter, not sent as pending',
      () async {
        final FakeStore store = FakeStore((_) => Reply(<Object?>[]));
        final WooCommerce woo = _admin(store);
        addTearDown(woo.close);

        await woo.orders.list(
          statuses: <WooOrderStatus>[
            WooOrderStatus.processing,
            WooOrderStatus.unknown,
          ],
        );
        expect(store.lastQuery['status'], 'processing');
      },
    );
  });

  group('variation keys match what the Store API actually sends', () {
    // WooCommerce builds a variation's attribute name with wc_attribute_label,
    // so it is the display label ("Colour"), while addItem requires the pa_
    // taxonomy. variationFor documented the taxonomy and so never matched a
    // global attribute — and the old fixture used pa_colour for both, so the
    // test agreed with the bug.
    StoreProduct product() => StoreProduct.fromJson(<String, Object?>{
      ...storeProductJson(type: 'variable'),
      'attributes': <Object?>[
        <String, Object?>{
          'id': 3,
          'name': 'Colour',
          'taxonomy': 'pa_colour',
          'has_variations': true,
          'terms': <Object?>[
            <String, Object?>{'id': 9, 'name': 'Blue', 'slug': 'blue'},
            <String, Object?>{'id': 10, 'name': 'Red', 'slug': 'red'},
          ],
        },
      ],
      'variations': <Object?>[
        <String, Object?>{
          'id': 35,
          'attributes': <Object?>[
            <String, Object?>{'name': 'Colour', 'value': 'blue'},
          ],
        },
        <String, Object?>{
          'id': 36,
          'attributes': <Object?>[
            <String, Object?>{'name': 'Colour', 'value': 'red'},
          ],
        },
      ],
    });

    test('resolves by the label the API uses', () {
      expect(product().variationFor(<String, String>{'Colour': 'red'})?.id, 36);
    });

    test('resolves by the taxonomy too, since addItem speaks that', () {
      expect(
        product().variationFor(<String, String>{'pa_colour': 'blue'})?.id,
        35,
      );
    });

    test('an unsold combination is still null', () {
      expect(
        product().variationFor(<String, String>{'Colour': 'green'}),
        isNull,
      );
      expect(product().variationFor(const <String, String>{}), isNull);
    });

    test('cartAttributes rewrites a label into the taxonomy addItem wants', () {
      expect(
        product().cartAttributes(<String, String>{'Colour': 'blue'}),
        <String, String>{'pa_colour': 'blue'},
      );
      // Already a taxonomy, and product-specific names, both pass through.
      expect(
        product().cartAttributes(<String, String>{'pa_colour': 'blue'}),
        <String, String>{'pa_colour': 'blue'},
      );
      expect(
        product().cartAttributes(<String, String>{'Logo': 'Yes'}),
        <String, String>{'Logo': 'Yes'},
      );
    });
  });

  test('two concurrent first calls make one cart, not two', () async {
    // Shipped in 0.2.x: both went out with no Cart-Token, the store made a
    // cart for each, and whichever token was absorbed last won — the other
    // shopper's items were simply gone.
    int tokenless = 0;
    int issued = 0;
    final WooStore store = WooStore(
      baseUrl: 'https://shop.test',
      httpClient: MockClient((http.Request r) async {
        if (!r.headers.containsKey('Cart-Token')) tokenless++;
        issued++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response(
          jsonEncode(cartJson()),
          200,
          headers: <String, String>{
            'content-type': 'application/json',
            'Cart-Token': 'token-$issued',
          },
        );
      }),
    );
    addTearDown(store.close);

    await Future.wait(<Future<Object?>>[
      store.cart.get(),
      store.cart.addItem(id: 38),
      store.cart.addItem(id: 39),
    ]);

    expect(tokenless, 1, reason: 'only the first request may go out unclaimed');
    expect(await store.session.cartToken, isNotNull);
  });

  test('a failed first request does not wedge every later one', () async {
    int calls = 0;
    final WooStore store = WooStore(
      baseUrl: 'https://shop.test',
      httpClient: MockClient((http.Request r) async {
        calls++;
        if (calls == 1) return wooError(500, 'boom', 'Store exploded');
        return http.Response(
          jsonEncode(cartJson()),
          200,
          headers: <String, String>{
            'content-type': 'application/json',
            'Cart-Token': 't',
          },
        );
      }),
    );
    addTearDown(store.close);

    await expectLater(store.cart.get(), throwsA(isA<WooServerException>()));
    // Before the fix this hung forever on a Completer nobody completed.
    final StoreCart cart = await store.cart.get().timeout(
      const Duration(seconds: 5),
    );
    expect(cart.isNotEmpty, isTrue);
  });

  group('a partly failed batch is not silent', () {
    test('addItems throws naming what the store refused', () async {
      // Shipped in 0.2.x: the batch response was discarded, so adding five
      // items where one was out of stock returned a cart with four and no
      // indication anything went wrong.
      final FakeStoreApi api = FakeStoreApi((http.Request r) {
        if (!r.url.path.endsWith('/batch')) return cartJson();
        return <String, Object?>{
          'responses': <Object?>[
            <String, Object?>{'status': 201, 'body': <String, Object?>{}},
            <String, Object?>{
              'status': 409,
              'body': <String, Object?>{
                'code': 'woocommerce_rest_product_out_of_stock',
                'message': 'Beanie with Logo is out of stock.',
              },
            },
          ],
        };
      });
      final WooStore store = WooStore(
        baseUrl: 'https://shop.test',
        httpClient: api.client,
      );
      addTearDown(store.close);

      await expectLater(
        store.cart.addItems(<int, int>{38: 1, 39: 1}),
        throwsA(
          isA<WooInvalidRequestException>()
              .having(
                (WooInvalidRequestException e) => e.message,
                'message',
                contains('out of stock'),
              )
              .having(
                (WooInvalidRequestException e) => e.message,
                'message',
                contains('1 of 2'),
              ),
        ),
      );
    });

    test('an all-good batch still just returns the cart', () async {
      final FakeStoreApi api = FakeStoreApi((http.Request r) {
        if (!r.url.path.endsWith('/batch')) return cartJson();
        return <String, Object?>{
          'responses': <Object?>[
            <String, Object?>{'status': 201, 'body': <String, Object?>{}},
          ],
        };
      });
      final WooStore store = WooStore(
        baseUrl: 'https://shop.test',
        httpClient: api.client,
      );
      addTearDown(store.close);
      expect((await store.cart.addItems(<int, int>{38: 1})).isNotEmpty, isTrue);
    });
  });
}

WooCommerce _admin(FakeStore store) => WooCommerce(
  baseUrl: 'https://shop.test',
  credentials: const WooCredentials.key(
    consumerKey: 'ck',
    consumerSecret: 'cs',
  ),
  httpClient: store.client,
);

class _Offline implements Exception {
  const _Offline();
  @override
  String toString() => 'SocketException: Network is unreachable';
}
