// Every API call the README makes, compiled.
//
// A snippet checker only catches syntax. This catches a signature that has
// drifted — a renamed parameter, a changed type, a method that moved — which
// is the failure mode that actually reaches readers.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:woo_client/woo_client.dart';

void main() {
  test('the README compiles and runs', () async {
    const String ck = 'ck_x';
    const String cs = 'cs_x';

    // -- Opening ------------------------------------------------------------
    final WooCommerce woo = WooCommerce(
      baseUrl: 'https://your-store.com',
      credentials: const WooCredentials.key(
        consumerKey: ck,
        consumerSecret: cs,
      ),
      httpClient: _store,
    );
    addTearDown(woo.close);

    final WooPage<WooProduct> first = await woo.products.list(
      search: 'satchel',
      onSale: true,
    );
    for (final WooProduct product in first.items) {
      expect('${product.name} — ${product.price}', isNotEmpty);
    }

    // -- Reading ------------------------------------------------------------
    final WooPage<WooProduct> page = await woo.products.list(
      search: 'leather',
      categories: <int>[21],
      onSale: true,
      minPrice: '50',
      orderBy: WooProductOrderBy.popularity,
      perPage: 20,
    );

    expect(page.totalItems, 57);
    expect(page.totalPages, 3);
    expect(page.hasMore, isTrue);
    expect(page.nextPage, 2);

    await woo.products.get(799);
    final WooProduct? bySku = await woo.products.bySku('SATCHEL-01');
    expect(bySku, isNotNull);
    await woo.products.variations(799);

    final WooProduct product = page.items.first;
    expect(product.onSale, isA<bool>());
    expect(product.regularPrice, isA<WooPrice>());
    expect(product.salePrice, isA<WooPrice>());
    expect(product.stockQuantity, isA<int?>());
    expect(product.categories, isA<List<WooTerm>>());
    expect(product.images, isA<List<WooImage>>());
    expect(product.dateCreated, isA<DateTime?>());
    expect(product.raw['meta_data'], anything);
    expect(product.raw['_yoast_wpseo_title'], anything);

    await for (final WooProduct _ in woo.products.all(perPage: 100)) {
      break;
    }

    // -- Writing ------------------------------------------------------------
    final WooOrder order = await woo.orders.create(
      lineItems: <WooLineItem>[
        WooLineItem.order(productId: 799, quantity: 2),
        WooLineItem.order(productId: 812, quantity: 1, variationId: 815),
      ],
      billing: const WooAddress(
        firstName: 'Ada',
        lastName: 'Lovelace',
        address1: '12 Analytical Way',
        city: 'London',
        postcode: 'N1 7GU',
        country: 'GB',
        email: 'ada@example.com',
      ),
      paymentMethod: 'stripe',
      setPaid: false,
    );
    await woo.orders.setStatus(order.id, WooOrderStatus.completed);

    await woo.orders.create(
      lineItems: <WooLineItem>[WooLineItem.order(productId: 799, quantity: 1)],
      extra: const <String, Object?>{
        'meta_data': <Object?>[
          <String, Object?>{'key': '_gift_note', 'value': 'Happy birthday'},
        ],
      },
    );

    // -- Escape hatch -------------------------------------------------------
    await woo.getOne('/reports/sales');
    await woo.getPage('/orders/5120/refunds');

    // -- Bearer -------------------------------------------------------------
    WooCommerce(
      baseUrl: 'https://your-store.com',
      credentials: const WooCredentials.bearer('token'),
      httpClient: _store,
    ).close();
  });

  test('the README error handling compiles and catches what it claims', () {
    Object? handle(WooException e) => switch (e) {
      WooNotFoundException() => null,
      final WooAuthException e => 'Key rejected: ${e.message}',
      final WooInvalidRequestException e =>
        'Store said no: ${e.code} '
            '${e.details}',
      WooServerException() => 'retry',
      final WooNetworkException e => 'Never reached the store: ${e.cause}',
      final WooBadResponseException e => 'Not JSON: ${e.body}',
    };

    // The switch above is exhaustive with no default, which is the README's
    // claim about the sealed hierarchy. If a subclass is added it stops
    // compiling here.
    expect(
      handle(const WooNotFoundException('Invalid ID.', statusCode: 404)),
      isNull,
    );
  });

  test('the README testing snippet compiles', () async {
    final WooCommerce woo = WooCommerce(
      baseUrl: 'https://example.com',
      httpClient: MockClient(
        (http.Request request) async => http.Response(
          jsonEncode(<Object?>[
            <String, Object?>{'id': 1, 'name': 'Satchel', 'price': '129.00'},
          ]),
          200,
          headers: <String, String>{
            'content-type': 'application/json',
            'x-wp-total': '1',
          },
        ),
      ),
    );
    addTearDown(woo.close);

    final WooPage<WooProduct> page = await woo.products.list();
    expect(page.items.single.name, 'Satchel');
    expect(page.totalItems, 1);
  });
}

/// Answers anything with a plausible shape, so the README's calls can run.
http.Client get _store => MockClient((http.Request request) async {
  // /reports/sales is an object; /products and /orders/5120/refunds are lists.
  final bool isList =
      request.method == 'GET' &&
      RegExp(r'/(products|orders|customers|coupons|variations|refunds)$')
          .hasMatch(request.url.path);
  final Map<String, Object?> one = <String, Object?>{
    'id': 799,
    'name': 'Leather Satchel',
    'sku': 'SATCHEL-01',
    'price': '99.00',
    'regular_price': '129.00',
    'sale_price': '99.00',
    'on_sale': true,
    'stock_quantity': 4,
    'line_items': <Object?>[],
    'billing': <String, Object?>{},
    'shipping': <String, Object?>{},
  };
  return http.Response(
    jsonEncode(isList ? <Object?>[one] : one),
    200,
    headers: <String, String>{
      'content-type': 'application/json',
      'x-wp-total': '57',
      'x-wp-totalpages': '3',
    },
  );
});
