import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:woo_client/woo_client.dart';

import 'store_support.dart';
import 'support.dart';

void main() {
  WooCommerce adminFor(FakeStore store) => WooCommerce(
    baseUrl: 'https://shop.test',
    credentials: const WooCredentials.key(
      consumerKey: 'ck',
      consumerSecret: 'cs',
    ),
    httpClient: store.client,
  );

  group('the resources 0.1.0 was missing', () {
    test('categories parse and page', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(
          <Object?>[
            <String, Object?>{
              'id': 21,
              'name': 'Bags',
              'slug': 'bags',
              'parent': 0,
              'count': 12,
              'image': <String, Object?>{'src': 'https://shop.test/bags.jpg'},
            },
          ],
          headers: <String, String>{'x-wp-total': '9', 'x-wp-totalpages': '1'},
        ),
      );
      final WooCommerce woo = adminFor(store);
      addTearDown(woo.close);

      final WooPage<WooCategory> page = await woo.admin.productCategories
          .list();
      expect(store.lastUri.path, endsWith('/products/categories'));
      final WooCategory c = page.items.single;
      expect(c.name, 'Bags');
      expect(c.isTopLevel, isTrue);
      expect(c.count, 12);
      expect(c.imageSrc, endsWith('bags.jpg'));
      expect(page.totalItems, 9);
    });

    test('attribute terms hang off their attribute', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<Object?>[
          <String, Object?>{'id': 9, 'name': 'Blue', 'slug': 'blue'},
        ]),
      );
      final WooCommerce woo = adminFor(store);
      addTearDown(woo.close);

      final WooPage<WooAttributeTerm> terms = await woo.admin
          .attributeTerms(3)
          .list();
      expect(store.lastUri.path, endsWith('/products/attributes/3/terms'));
      expect(terms.items.single.name, 'Blue');
    });

    test('an attribute knows its pa_ taxonomy', () {
      expect(
        WooAttribute.fromJson(const <String, Object?>{
          'id': 3,
          'name': 'Colour',
          'slug': 'colour',
        }).taxonomy,
        'pa_colour',
      );
      // Already prefixed, so do not prefix it twice.
      expect(
        WooAttribute.fromJson(const <String, Object?>{'slug': 'pa_colour'})
            .taxonomy,
        'pa_colour',
      );
    });

    test('order notes and refunds hang off their order', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<Object?>[
          <String, Object?>{
            'id': 1,
            'note': 'Picked',
            'customer_note': false,
            'author': 'system',
          },
        ]),
      );
      final WooCommerce woo = adminFor(store);
      addTearDown(woo.close);

      final WooPage<WooOrderNote> notes = await woo.admin
          .orderNotes(5120)
          .list();
      expect(store.lastUri.path, endsWith('/orders/5120/notes'));
      expect(notes.items.single.isPrivate, isTrue);

      await woo.admin.refunds(5120).list();
      expect(store.lastUri.path, endsWith('/orders/5120/refunds'));
    });

    test('a review knows whether the reviewer actually bought it', () {
      final WooReview r = WooReview.fromJson(const <String, Object?>{
        'id': 4,
        'product_id': 799,
        'rating': 5,
        'review': '<p>Lovely.</p>',
        'status': 'approved',
        'reviewer': 'Ada',
        'verified': true,
        'reviewer_avatar_urls': <String, Object?>{'96': 'https://g.test/a.png'},
      });
      expect(r.verified, isTrue);
      expect(r.isApproved, isTrue);
      expect(r.reviewerAvatar, 'https://g.test/a.png');
    });

    test('a tax rate reads as a number, not a string', () {
      final WooTaxRate t = WooTaxRate.fromJson(const <String, Object?>{
        'id': 1,
        'rate': '20.0000',
        'name': 'VAT',
        'country': 'GB',
        'compound': false,
        'shipping': true,
      });
      expect(t.rate, 20.0);
      expect(t.toString(), 'VAT 20.0%');
    });

    test('payment gateways come back typed', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<Object?>[
          <String, Object?>{
            'id': 'cod',
            'title': 'Cash on delivery',
            'enabled': true,
            'order': 1,
          },
        ]),
      );
      final WooCommerce woo = adminFor(store);
      addTearDown(woo.close);

      final List<WooPaymentGateway> gateways = await woo.admin
          .paymentGateways();
      expect(gateways.single.id, 'cod');
      expect(gateways.single.enabled, isTrue);
    });

    test('settings has a shortcut for the currency', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<String, Object?>{
          'id': 'woocommerce_currency',
          'value': 'GBP',
        }),
      );
      final WooCommerce woo = adminFor(store);
      addTearDown(woo.close);

      expect(await woo.admin.settings.currency(), 'GBP');
      expect(
        store.lastUri.path,
        endsWith('/settings/general/woocommerce_currency'),
      );
    });

    test('shipping zone locations are replaced with a bare array', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<Object?>[
          <String, Object?>{'code': 'GB', 'type': 'country'},
        ]),
      );
      final WooCommerce woo = adminFor(store);
      addTearDown(woo.close);

      await woo.admin.shippingZones.setLocations(2, <Map<String, Object?>>[
        <String, Object?>{'code': 'GB', 'type': 'country'},
      ]);
      expect(store.calls.last.method, 'PUT');
      // A bare list, not {"locations": [...]} — this route is the odd one.
      expect(jsonDecode(store.calls.last.body), isA<List<Object?>>());
    });

    test('reports pass their period through', () async {
      final FakeStore store = FakeStore((_) => Reply(<Object?>[]));
      final WooCommerce woo = adminFor(store);
      addTearDown(woo.close);

      await woo.admin.reports.topSellers(period: 'month');
      expect(store.lastQuery['period'], 'month');

      await woo.admin.reports.sales(dateMin: DateTime.utc(2026, 8, 1));
      expect(store.lastQuery['date_min'], '2026-08-01');
    });
  });

  group('batch', () {
    test('splits the response the way it split the request', () async {
      final FakeStore store = FakeStore(
        (_) => Reply(<String, Object?>{
          'create': <Object?>[productJson(id: 900)],
          'update': <Object?>[productJson(id: 799)],
          'delete': <Object?>[productJson(id: 800)],
        }),
      );
      final WooCommerce woo = adminFor(store);
      addTearDown(woo.close);

      final WooBatchResult<WooProduct> result = await woo.products.batch(
        create: <Map<String, Object?>>[
          <String, Object?>{'name': 'Tote'},
        ],
        update: <Map<String, Object?>>[
          <String, Object?>{'id': 799, 'regular_price': '119.00'},
        ],
        delete: <int>[800],
      );

      expect(store.lastUri.path, endsWith('/products/batch'));
      expect(result.created.single.id, 900);
      expect(result.updated.single.id, 799);
      expect(result.deleted.single.id, 800);
      expect(result.total, 3);
    });

    test('refuses more than WooCommerce accepts, rather than losing rows', () {
      // WooCommerce silently truncates past 100, which looks like data loss.
      final FakeStore store = FakeStore((_) => Reply(<String, Object?>{}));
      final WooCommerce woo = adminFor(store);
      addTearDown(woo.close);

      expect(
        () => woo.products.batch(
          update: List<Map<String, Object?>>.generate(
            101,
            (int i) => <String, Object?>{'id': i},
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('omits the keys it was given nothing for', () async {
      final FakeStore store = FakeStore((_) => Reply(<String, Object?>{}));
      final WooCommerce woo = adminFor(store);
      addTearDown(woo.close);

      await woo.admin.productTags.batch(
        create: <Map<String, Object?>>[
          <String, Object?>{'name': 'Leather'},
        ],
      );
      expect(store.lastBody.keys, <String>['create']);
    });
  });

  group('public products', () {
    test('parse with formatted prices and their attributes', () async {
      final FakeStoreApi api = FakeStoreApi(
        (_) => <Object?>[storeProductJson()],
      );
      final WooStore store = WooStore(
        baseUrl: 'https://shop.test',
        httpClient: api.client,
      );
      addTearDown(store.close);

      final WooPage<StoreProduct> page = await store.products.list(
        search: 'pennant',
        orderBy: StoreProductOrderBy.popularity,
      );
      final StoreProduct p = page.items.single;
      expect(p.price.toString(), '£11.05');
      expect(p.averageRating, 4.5);
      expect(p.categories.single.name, 'Flags');
      expect(p.attributes.single.wireName, 'pa_colour');
      expect(p.attributes.single.terms.map((StoreTerm t) => t.name), <String>[
        'Blue',
        'Red',
      ]);
      expect(api.lastUri.queryParameters['orderby'], 'popularity');
      expect(api.lastUri.queryParameters['search'], 'pennant');
    });

    test(
      'a variable product resolves a chosen combination to a variation',
      () async {
        final StoreProduct p = StoreProduct.fromJson(
          storeProductJson(type: 'variable'),
        );
        expect(p.needsOptions, isTrue);
        expect(p.variationFor(<String, String>{'pa_colour': 'red'})?.id, 36);
        expect(p.variationFor(<String, String>{'pa_colour': 'green'}), isNull);
      },
    );

    test('a price range is exposed rather than flattened to one number', () {
      final StoreProduct p = StoreProduct.fromJson(
        storeProductJson(
          type: 'variable',
          priceRange: <String, Object?>{
            'min_amount': '1105',
            'max_amount': '2210',
          },
        ),
      );
      expect(p.priceRange?.isFlat, isFalse);
      expect(p.priceRange.toString(), '£11.05 – £22.10');
    });

    test('paging headers survive two calls in flight at once', () async {
      // These used to live on the client, so two concurrent list calls read
      // each other's totals. The slow first page makes that visible.
      final WooStore store = WooStore(
        baseUrl: 'https://shop.test',
        httpClient: EchoPageAsTotalClient(),
      );
      addTearDown(store.close);

      final List<WooPage<StoreProduct>> pages = await Future.wait(
        <Future<WooPage<StoreProduct>>>[
          store.products.list(page: 1),
          store.products.list(page: 2),
        ],
      );
      expect(pages[0].totalItems, 1);
      expect(pages[1].totalItems, 2);
    });

    test('bySlug is a deep-link lookup', () async {
      final FakeStoreApi api = FakeStoreApi(
        (_) => <Object?>[storeProductJson()],
      );
      final WooStore store = WooStore(
        baseUrl: 'https://shop.test',
        httpClient: api.client,
      );
      addTearDown(store.close);

      final StoreProduct? p = await store.products.bySlug('wordpress-pennant');
      expect(p?.id, 34);
      expect(api.lastUri.queryParameters['slug'], 'wordpress-pennant');
    });
  });
}

/// Echoes the requested page number back as `x-wp-total`, slowly for page 1,
/// so a response read against the wrong request is visible.
class EchoPageAsTotalClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final String page = request.url.queryParameters['page'] ?? '1';
    if (page == '1') {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('[]')),
      200,
      headers: <String, String>{
        'content-type': 'application/json',
        'x-wp-total': page,
      },
    );
  }
}
