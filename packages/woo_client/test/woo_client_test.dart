import 'package:test/test.dart';
import 'package:woo_client/woo_client.dart';

import 'support.dart';

void main() {
  WooCommerce clientFor(FakeStore store, {WooCredentials? credentials}) =>
      WooCommerce(
        baseUrl: 'https://shop.example.com',
        credentials:
            credentials ??
            const WooCredentials.key(
              consumerKey: 'ck_test',
              consumerSecret: 'cs_test',
            ),
        httpClient: store.client,
      );

  group('the URL it builds', () {
    test('adds the REST path and the credentials', () async {
      final FakeStore store = FakeStore((_) => Reply(<Object?>[productJson()]));
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      await woo.products.list();

      expect(store.lastUri.path, '/wp-json/wc/v3/products');
      expect(store.lastQuery['consumer_key'], 'ck_test');
      expect(store.lastQuery['consumer_secret'], 'cs_test');
    });

    test('tolerates a trailing slash on the base url', () async {
      final FakeStore store = FakeStore((_) => Reply(<Object?>[]));
      final WooCommerce woo = WooCommerce(
        baseUrl: 'https://shop.example.com/',
        httpClient: store.client,
      );
      addTearDown(woo.close);
      await woo.products.list();
      expect(store.lastUri.path, '/wp-json/wc/v3/products');
    });

    test('works with WordPress in a subdirectory', () async {
      final FakeStore store = FakeStore((_) => Reply(<Object?>[]));
      final WooCommerce woo = WooCommerce(
        baseUrl: 'https://example.com/shop',
        httpClient: store.client,
      );
      addTearDown(woo.close);
      await woo.products.list();
      expect(store.lastUri.path, '/shop/wp-json/wc/v3/products');
    });

    test('a bearer token goes in the header, never the query', () async {
      final FakeStore store = FakeStore((_) => Reply(<Object?>[]));
      final WooCommerce woo = clientFor(
        store,
        credentials: const WooCredentials.bearer('jwt-token'),
      );
      addTearDown(woo.close);
      await woo.products.list();

      expect(store.calls.last.headers['Authorization'], 'Bearer jwt-token');
      expect(store.lastQuery.containsKey('consumer_secret'), isFalse);
    });

    test('refuses to send a consumer secret over plain http', () {
      expect(
        () => WooCommerce(
          baseUrl: 'http://shop.example.com',
          credentials: const WooCredentials.key(
            consumerKey: 'ck',
            consumerSecret: 'cs',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('allows plain http when there is no secret to leak', () {
      final WooCommerce woo = WooCommerce(baseUrl: 'http://localhost:8080');
      addTearDown(woo.close);
      expect(woo, isA<WooCommerce>());
    });

    test('lists become comma-separated, dates become ISO 8601', () async {
      final FakeStore store = FakeStore((_) => Reply(<Object?>[]));
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      await woo.products.list(
        categories: <int>[21, 44],
        after: DateTime.utc(2026, 8, 1, 9, 30),
        onSale: true,
      );

      expect(store.lastQuery['category'], '21,44');
      expect(store.lastQuery['after'], startsWith('2026-08-01T09:30'));
      expect(store.lastQuery['on_sale'], 'true');
    });

    test('null filters are left out entirely', () async {
      final FakeStore store = FakeStore((_) => Reply(<Object?>[]));
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);
      await woo.products.list(search: null, sku: null);
      expect(store.lastQuery.containsKey('search'), isFalse);
      expect(store.lastQuery.containsKey('sku'), isFalse);
    });
  });

  group('pagination', () {
    test('reads the totals the store puts in headers', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(
          <Object?>[productJson()],
          headers: <String, String>{'x-wp-total': '57', 'x-wp-totalpages': '6'},
        ),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      final WooPage<WooProduct> page = await woo.products.list(perPage: 10);
      expect(page.totalItems, 57);
      expect(page.totalPages, 6);
      expect(page.hasMore, isTrue);
      expect(page.nextPage, 2);
    });

    test('knows when it is on the last page', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(
          <Object?>[productJson()],
          headers: <String, String>{'x-wp-total': '3', 'x-wp-totalpages': '1'},
        ),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);
      final WooPage<WooProduct> page = await woo.products.list();
      expect(page.hasMore, isFalse);
      expect(page.nextPage, isNull);
    });

    test('falls back to a full page when the store sends no totals', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<Object?>[productJson(), productJson(id: 800)]),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);
      // Some hardened stores strip the X-WP headers; guessing from a full
      // page is better than reporting "no more" and silently truncating.
      final WooPage<WooProduct> page = await woo.products.list(perPage: 2);
      expect(page.totalItems, isNull);
      expect(page.hasMore, isTrue);
    });

    test('all() walks every page and then stops', () async {
      int call = 0;
      final FakeStore store = FakeStore((_) {
        call++;
        return Reply(
          <Object?>[productJson(id: 800 + call), productJson(id: 900 + call)],
          headers: <String, String>{'x-wp-total': '6', 'x-wp-totalpages': '3'},
        );
      });
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      final List<WooProduct> all = await woo.products.all(perPage: 2).toList();
      expect(all, hasLength(6));
      expect(store.calls, hasLength(3));
      expect(store.calls.last.url.queryParameters['page'], '3');
    });
  });

  group('errors say which kind of no', () {
    Future<void> expectFor(int status, Object matcher, {Object? body}) async {
      final FakeStore store = FakeStore(
        (_) => Reply(
          body ??
              <String, Object?>{
                'code': 'woocommerce_rest_cannot_view',
                'message': 'Sorry, you cannot list resources.',
                'data': <String, Object?>{'status': status},
              },
          status: status,
        ),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);
      await expectLater(woo.products.list(), throwsA(matcher));
    }

    test(
      '401 is an auth problem',
      () => expectFor(401, isA<WooAuthException>()),
    );
    test(
      '403 is an auth problem',
      () => expectFor(403, isA<WooAuthException>()),
    );
    test('404 is not found', () => expectFor(404, isA<WooNotFoundException>()));
    test(
      '400 is a bad request',
      () => expectFor(400, isA<WooInvalidRequestException>()),
    );
    test(
      '500 is the store breaking',
      () => expectFor(500, isA<WooServerException>()),
    );

    test('carries the code and message the store gave', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<String, Object?>{
          'code': 'woocommerce_rest_invalid_id',
          'message': 'Invalid ID.',
          'data': <String, Object?>{'status': 404},
        }, status: 404),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      try {
        await woo.products.get(1);
        fail('should have thrown');
      } on WooNotFoundException catch (e) {
        expect(e.code, 'woocommerce_rest_invalid_id');
        expect(e.message, 'Invalid ID.');
        expect(e.statusCode, 404);
        expect(e.toString(), contains('woocommerce_rest_invalid_id'));
      }
    });

    test('an HTML page instead of JSON is its own kind of wrong', () async {
      // A plugin printing a notice, or a login wall on the REST route. The
      // status can even be 200, which makes a JSON decode error confusing.
      final FakeStore store = FakeStore(
        (_) => Reply('<!DOCTYPE html><html><body>Login</body></html>'),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      await expectLater(
        woo.products.list(),
        throwsA(
          isA<WooBadResponseException>().having(
            (WooBadResponseException e) => e.body,
            'body',
            contains('DOCTYPE'),
          ),
        ),
      );
    });

    test('validation details survive', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<String, Object?>{
          'code': 'rest_missing_callback_param',
          'message': 'Missing parameter(s): name',
          'data': <String, Object?>{
            'status': 400,
            'params': <Object?>['name'],
          },
        }, status: 400),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      try {
        await woo.products.create(const <String, Object?>{});
        fail('should have thrown');
      } on WooInvalidRequestException catch (e) {
        expect(e.details?['params'], <Object?>['name']);
      }
    });

    test('a closed client refuses rather than misbehaving', () async {
      final FakeStore store = FakeStore((_) => Reply(<Object?>[]));
      final WooCommerce woo = clientFor(store);
      woo.close();
      await expectLater(woo.products.list(), throwsStateError);
    });
  });
}
