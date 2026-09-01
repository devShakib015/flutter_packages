import 'package:http/http.dart' as http;

import '../page.dart';
import '../transport.dart';
import 'resources/cart.dart';
import 'resources/checkout.dart';
import 'resources/store_products.dart';
import 'session.dart';

/// A client for the WooCommerce **Store API** — the public one.
///
/// This is the API to use for anything a shopper touches: browsing, the cart,
/// and checkout. It needs **no API keys at all**, which is what makes it the
/// right choice for a shipped app. The admin API's consumer keys can read
/// every customer's address and change every price, and anything you ship to
/// a device can be read off that device.
///
/// ```dart
/// final store = WooStore(baseUrl: 'https://your-store.com');
///
/// final products = await store.products.list(search: 'beanie');
/// await store.cart.addItem(id: products.first.id, quantity: 1);
///
/// final cart = await store.cart.get();
/// print(cart.totals.totalPrice);  // $18.00
/// ```
///
/// Carts are identified by a `Cart-Token` the store issues on the first
/// request; this client captures it and sends it back automatically. Give it
/// a [CartTokenStore] to keep a shopper's basket across app launches.
///
/// Available on WooCommerce 8.0+ (the Store API shipped with WooCommerce
/// Blocks and was merged into core). Requires no plugin on a current store.
class WooStore {
  /// Connects to the store at [baseUrl].
  ///
  /// [baseUrl] is the site root — `https://your-store.com`, with or without a
  /// trailing slash. WordPress in a subdirectory works too.
  ///
  /// Pass [tokens] to keep the cart across restarts, [httpClient] to control
  /// or fake the transport, and [retry] to have reads retried on a flaky
  /// connection.
  WooStore({
    required String baseUrl,
    CartTokenStore? tokens,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 30),
    WooRetry retry = const WooRetry.none(),
    this.apiPath = '/wp-json/wc/store/v1',
  }) : session = CartSession(tokens: tokens),
       _transport = WooTransport(
         baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''),
         timeout: timeout,
         retry: retry,
         httpClient: httpClient,
       );

  final WooTransport _transport;

  /// Where the Store API lives under the site root.
  final String apiPath;

  /// The cart token bookkeeping. Use it to persist, adopt, or clear a cart.
  final CartSession session;

  StoreCartResource? _cart;
  StoreCheckoutResource? _checkout;
  StoreProducts? _products;

  /// The shopper's cart.
  StoreCartResource get cart => _cart ??= StoreCartResource(this);

  /// Turning the cart into a paid order.
  StoreCheckoutResource get checkout =>
      _checkout ??= StoreCheckoutResource(this);

  /// Public product browsing — no keys, no admin fields.
  StoreProducts get products => _products ??= StoreProducts(this);

  /// Sends a GET and decodes an object.
  ///
  /// Use this for Store API routes this package does not wrap. Tokens and
  /// error handling work the same.
  Future<Map<String, Object?>> getOne(
    String path, {
    Map<String, Object?>? query,
  }) async => _transport.asMap(await _call('GET', path, query: query));

  /// Sends a GET and decodes a list.
  Future<List<Map<String, Object?>>> getList(
    String path, {
    Map<String, Object?>? query,
  }) async => _transport.asList(await _call('GET', path, query: query));

  /// Sends a GET and decodes a list, with the store's paging headers.
  ///
  /// Returns the totals rather than stashing them on the client, so two list
  /// calls in flight at once cannot read each other's page counts.
  Future<WooPage<Map<String, Object?>>> getPage(
    String path, {
    Map<String, Object?>? query,
    int page = 1,
    int perPage = 10,
  }) async {
    final http.Response response = await _call(
      'GET',
      path,
      query: <String, Object?>{...?query, 'page': page, 'per_page': perPage},
    );
    return WooPage<Map<String, Object?>>(
      items: _transport.asList(response),
      page: page,
      perPage: perPage,
      totalItems: int.tryParse(response.headers['x-wp-total'] ?? ''),
      totalPages: int.tryParse(response.headers['x-wp-totalpages'] ?? ''),
    );
  }

  /// Sends a POST and decodes an object.
  Future<Map<String, Object?>> post(
    String path, {
    Map<String, Object?>? body,
    Map<String, Object?>? query,
  }) async =>
      _transport.asMap(await _call('POST', path, body: body, query: query));

  /// Sends a PUT and decodes an object.
  Future<Map<String, Object?>> put(
    String path, {
    Map<String, Object?>? body,
    Map<String, Object?>? query,
  }) async =>
      _transport.asMap(await _call('PUT', path, body: body, query: query));

  Future<http.Response> _call(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? body,
  }) async {
    final http.Response response = await _transport.send(
      method,
      _transport.uri('$apiPath$path', query),
      headers: await session.headers(),
      body: body,
    );
    await session.absorb(response.headers);
    return response;
  }

  /// Runs several Store API calls in one round trip.
  ///
  /// The Store API's own batch endpoint. Adding five things to a cart this way
  /// is one request and one recalculation instead of five of each — which on a
  /// slow connection is the difference between a snappy cart and a spinner.
  ///
  /// ```dart
  /// await store.batch([
  ///   StoreBatchRequest.addItem(id: 26, quantity: 1),
  ///   StoreBatchRequest.addItem(id: 27, quantity: 2),
  /// ]);
  /// ```
  ///
  /// Each response is returned in order. A failure in one does not fail the
  /// others, so check each one's `status`.
  Future<List<Map<String, Object?>>> batch(
    List<StoreBatchRequest> requests,
  ) async {
    final Map<String, Object?> body = _transport.asMap(
      await _call(
        'POST',
        '/batch',
        body: <String, Object?>{
          'requests': <Object?>[
            for (final StoreBatchRequest r in requests) r.toJson(apiPath),
          ],
        },
      ),
    );
    return <Map<String, Object?>>[
      for (final Object? r in body['responses'] as List<Object?>? ?? const [])
        if (r is Map<String, Object?>) r,
    ];
  }

  /// Releases the underlying HTTP client, if this created it.
  void close() => _transport.close();
}

/// One call inside a [WooStore.batch].
class StoreBatchRequest {
  /// Creates a request for any Store API path.
  const StoreBatchRequest({
    required this.path,
    this.method = 'POST',
    this.body,
  });

  /// Adds an item to the cart.
  factory StoreBatchRequest.addItem({
    required int id,
    int quantity = 1,
    Map<String, String>? variation,
  }) => StoreBatchRequest(
    path: '/cart/add-item',
    body: <String, Object?>{
      'id': id,
      'quantity': quantity,
      if (variation != null && variation.isNotEmpty)
        'variation': <Object?>[
          for (final MapEntry<String, String> e in variation.entries)
            <String, Object?>{'attribute': e.key, 'value': e.value},
        ],
    },
  );

  /// Removes an item from the cart.
  factory StoreBatchRequest.removeItem(String key) => StoreBatchRequest(
    path: '/cart/remove-item',
    body: <String, Object?>{'key': key},
  );

  /// Changes an item's quantity.
  factory StoreBatchRequest.updateItem({
    required String key,
    required int quantity,
  }) => StoreBatchRequest(
    path: '/cart/update-item',
    body: <String, Object?>{'key': key, 'quantity': quantity},
  );

  /// The path under the Store API root, such as `/cart/add-item`.
  final String path;

  /// HTTP method.
  final String method;

  /// JSON body, if any.
  final Map<String, Object?>? body;

  /// The wire form, with [apiPath] prefixed onto [path].
  Map<String, Object?> toJson(String apiPath) => <String, Object?>{
    'path': '$apiPath$path',
    'method': method,
    'cache': 'no-store',
    if (body != null) 'body': body,
  };
}
