import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:woo_commerce/woo_commerce.dart';

import 'support.dart';

void main() {
  WooCommerce clientFor(FakeStore store) => WooCommerce(
    baseUrl: 'https://shop.example.com',
    credentials: const WooCredentials.key(
      consumerKey: 'ck_test',
      consumerSecret: 'cs_test',
    ),
    httpClient: store.client,
  );

  group('products', () {
    test('bySku asks for one and unwraps it', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<Object?>[productJson(sku: 'SATCHEL-01')]),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      final WooProduct? p = await woo.products.bySku('SATCHEL-01');
      expect(p?.sku, 'SATCHEL-01');
      expect(store.lastQuery['sku'], 'SATCHEL-01');
      expect(store.lastQuery['per_page'], '1');
    });

    test('bySku returns null rather than throwing on no match', () async {
      final FakeStore store = FakeStore((_) => Reply(<Object?>[]));
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);
      expect(await woo.products.bySku('NOPE'), isNull);
    });

    test('variations hit the nested route', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<Object?>[productJson(id: 801, type: 'variation')]),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      final WooPage<WooProduct> v = await woo.products.variations(799);
      expect(store.lastUri.path, endsWith('/products/799/variations'));
      expect(v.items.single.id, 801);
    });

    test('delete is a trash by default and permanent on request', () async {
      final FakeStore store = FakeStore((_) => Reply(productJson()));
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      await woo.products.delete(799);
      expect(store.calls.last.method, 'DELETE');
      expect(store.lastQuery['force'], 'false');

      await woo.products.delete(799, force: true);
      expect(store.lastQuery['force'], 'true');
    });
  });

  group('orders', () {
    test('create sends line items and lets the store price them', () async {
      final FakeStore store = FakeStore((_) => Reply(orderJson()));
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      await woo.orders.create(
        lineItems: <WooLineItem>[
          WooLineItem.order(productId: 799, quantity: 2),
        ],
        billing: const WooAddress(
          firstName: 'Ada',
          email: 'ada@example.com',
          country: 'GB',
        ),
        paymentMethod: 'bacs',
        setPaid: false,
      );

      final Map<String, Object?> body = store.lastBody;
      expect(store.calls.last.method, 'POST');
      expect(body['payment_method'], 'bacs');
      expect(body['set_paid'], false);
      final List<Object?> lines = body['line_items']! as List<Object?>;
      expect(lines.single, <String, Object?>{'product_id': 799, 'quantity': 2});
      expect(
        (body['billing']! as Map<String, Object?>)['email'],
        'ada@example.com',
      );
      // Shipping was not given, so nothing is sent for it.
      expect(body.containsKey('shipping'), isFalse);
    });

    test('extra fields ride along for plugins', () async {
      final FakeStore store = FakeStore((_) => Reply(orderJson()));
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      await woo.orders.create(
        lineItems: <WooLineItem>[
          WooLineItem.order(productId: 799, quantity: 1),
        ],
        extra: const <String, Object?>{
          'meta_data': <Object?>[
            <String, Object?>{'key': '_gift_note', 'value': 'Happy birthday'},
          ],
        },
      );
      expect(store.lastBody.containsKey('meta_data'), isTrue);
    });

    test('setStatus sends the wire name, not the enum name', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(orderJson(status: 'on-hold')),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      final WooOrder o = await woo.orders.setStatus(
        5120,
        WooOrderStatus.onHold,
      );
      expect(store.calls.last.method, 'PUT');
      expect(store.lastBody['status'], 'on-hold');
      expect(o.status, WooOrderStatus.onHold);
    });

    test('a status filter is sent as wire names', () async {
      final FakeStore store = FakeStore((_) => Reply(<Object?>[]));
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      await woo.orders.list(
        statuses: <WooOrderStatus>[
          WooOrderStatus.processing,
          WooOrderStatus.onHold,
        ],
      );
      expect(store.lastQuery['status'], 'processing,on-hold');
    });
  });

  group('customers', () {
    test('byEmail sends the address unchanged', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<Object?>[
          <String, Object?>{'id': 33, 'email': 'ada@example.com'},
        ]),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      final WooCustomer? c = await woo.customers.byEmail('Ada@Example.com');
      expect(c?.id, 33);
      // Case folding is the store database's business; a binary collation
      // would not match a lowercased address registered in mixed case.
      expect(store.lastQuery['email'], 'Ada@Example.com');
    });

    test('delete must say where the orders go', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<String, Object?>{'id': 33, 'email': 'a@b.c'}),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      await woo.customers.delete(33, reassignTo: 1);
      // WooCommerce refuses a customer delete without force=true.
      expect(store.lastQuery['force'], 'true');
      expect(store.lastQuery['reassign'], '1');
    });
  });

  group('coupons', () {
    test('byCode lowercases, because WooCommerce does', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<Object?>[
          <String, Object?>{'id': 12, 'code': 'save10', 'amount': '10.00'},
        ]),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      final WooCoupon? c = await woo.coupons.byCode('SAVE10');
      expect(c?.code, 'save10');
      expect(store.lastQuery['code'], 'save10');
    });
  });

  group('the request itself', () {
    test('sends and reads UTF-8, not Latin-1', () async {
      // http defaults to Latin-1 when the store omits a charset, which turns
      // every accented product name into mojibake.
      final FakeStore store = FakeStore(
        (_) => Reply.rawBytes(
          utf8.encode(jsonEncode(productJson(name: 'Café Crème – 250g'))),
          contentType: 'application/json',
        ),
      );
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      final WooProduct p = await woo.products.get(799);
      expect(p.name, 'Café Crème – 250g');
    });

    test('a POST body is JSON with a JSON content type', () async {
      final FakeStore store = FakeStore((_) => Reply(productJson()));
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);

      await woo.products.create(const <String, Object?>{'name': 'Tote'});
      expect(
        store.calls.last.headers['Content-Type'],
        contains('application/json'),
      );
      expect(store.lastBody['name'], 'Tote');
    });

    test('identifies itself so store logs are readable', () async {
      final FakeStore store = FakeStore((_) => Reply(<Object?>[]));
      final WooCommerce woo = clientFor(store);
      addTearDown(woo.close);
      await woo.products.list();
      expect(store.calls.last.headers['User-Agent'], WooCommerce.userAgent);
    });

    test('the advertised version matches the pubspec', () {
      // A hardcoded version drifts silently; this is the only thing stopping
      // the client from telling every store the wrong one.
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      final String version = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1)!;
      expect(WooCommerce.userAgent, 'woo_commerce/$version (Dart)');
    });
  });
}
