import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One scripted response from the fake store.
class Reply {
  /// A reply whose [body] is JSON-encoded (or sent verbatim if a `String`).
  Reply(
    Object? body, {
    this.status = 200,
    this.headers = const <String, String>{},
  }) : bytes = utf8.encode(body is String ? body : jsonEncode(body)),
       contentType = body is String
           ? 'text/html; charset=utf-8'
           : 'application/json; charset=utf-8';

  /// A reply whose bytes are given verbatim, for testing decoding.
  Reply.rawBytes(this.bytes, {required this.contentType})
    : status = 200,
      headers = const <String, String>{};

  /// The exact bytes the store sends.
  final List<int> bytes;

  /// The `content-type` header, which decides how [bytes] are decoded.
  final String contentType;

  /// HTTP status code.
  final int status;

  /// Extra response headers, such as the `x-wp-total` pagination pair.
  final Map<String, String> headers;
}

/// A store that answers from a script, and records what it was asked.
///
/// Real WooCommerce responses are large and their shape is what this client
/// has to survive, so the fixtures below are the genuine field sets rather
/// than the two keys a test happens to read.
class FakeStore {
  /// Answers every request with what [_reply] returns for it.
  FakeStore(this._reply);

  final Reply Function(http.Request request) _reply;

  /// Every request the client has made, in order.
  final List<http.Request> calls = <http.Request>[];

  /// The last URI requested.
  Uri get lastUri => calls.last.url;

  /// Query parameters of the last request.
  Map<String, String> get lastQuery => lastUri.queryParameters;

  /// Decoded body of the last request.
  Map<String, Object?> get lastBody =>
      jsonDecode(calls.last.body) as Map<String, Object?>;

  /// The client to hand to `WooCommerce(httpClient: ...)`.
  http.Client get client => MockClient((http.Request request) async {
    calls.add(request);
    final Reply reply = _reply(request);
    return http.Response.bytes(
      reply.bytes,
      reply.status,
      headers: <String, String>{
        'content-type': reply.contentType,
        ...reply.headers,
      },
    );
  });
}

/// A product as WooCommerce actually sends one, trimmed of the longest tails.
Map<String, Object?> productJson({
  int id = 799,
  String name = 'Leather Satchel',
  String sku = 'SATCHEL-01',
  String type = 'simple',
  String price = '129.00',
  String? salePrice,
  String stockStatus = 'instock',
  int? stockQuantity = 4,
}) => <String, Object?>{
  'id': id,
  'name': name,
  'slug': 'leather-satchel',
  'permalink': 'https://shop.example.com/product/leather-satchel',
  'date_created': '2026-03-04T10:15:22',
  'date_modified': '2026-08-19T08:02:11',
  'type': type,
  'status': 'publish',
  'featured': false,
  'description': '<p>Full-grain leather.</p>',
  'short_description': '<p>Full-grain.</p>',
  'sku': sku,
  'price': salePrice ?? price,
  'regular_price': price,
  'sale_price': salePrice ?? '',
  'on_sale': salePrice != null,
  'purchasable': true,
  'manage_stock': stockQuantity != null,
  'stock_quantity': stockQuantity,
  'stock_status': stockStatus,
  'average_rating': '4.67',
  'rating_count': 12,
  'categories': <Object?>[
    <String, Object?>{'id': 21, 'name': 'Bags', 'slug': 'bags'},
  ],
  'tags': <Object?>[
    <String, Object?>{'id': 44, 'name': 'Leather', 'slug': 'leather'},
  ],
  'images': <Object?>[
    <String, Object?>{
      'id': 900,
      'src': 'https://shop.example.com/wp-content/uploads/satchel.jpg',
      'alt': '',
    },
  ],
  'variations': type == 'variable' ? <Object?>[801, 802] : <Object?>[],
  'meta_data': <Object?>[],
};

/// An order as WooCommerce actually sends one.
Map<String, Object?> orderJson({
  int id = 5120,
  String status = 'processing',
  String total = '148.00',
  int customerId = 33,
  String? datePaid = '2026-08-20T11:04:00',
}) => <String, Object?>{
  'id': id,
  'number': '$id',
  'status': status,
  'currency': 'GBP',
  'date_created': '2026-08-20T11:03:12',
  'date_paid': datePaid,
  'total': total,
  'total_tax': '24.67',
  'shipping_total': '19.00',
  'discount_total': '0.00',
  'customer_id': customerId,
  'payment_method': 'stripe',
  'payment_method_title': 'Card',
  'customer_note': 'Leave with a neighbour',
  'billing': <String, Object?>{
    'first_name': 'Ada',
    'last_name': 'Lovelace',
    'address_1': '12 Analytical Way',
    'city': 'London',
    'postcode': 'N1 7GU',
    'country': 'GB',
    'email': 'ada@example.com',
    'phone': '+44 20 7946 0000',
  },
  'shipping': <String, Object?>{
    'first_name': 'Ada',
    'last_name': 'Lovelace',
    'address_1': '12 Analytical Way',
    'city': 'London',
    'postcode': 'N1 7GU',
    'country': 'GB',
  },
  'line_items': <Object?>[
    <String, Object?>{
      'id': 1,
      'name': 'Leather Satchel',
      'product_id': 799,
      'variation_id': 0,
      'quantity': 1,
      'subtotal': '129.00',
      'total': '129.00',
      'sku': 'SATCHEL-01',
    },
  ],
};
