import 'package:http/http.dart' as http;

import 'credentials.dart';
import 'exceptions.dart';
import 'page.dart';
import 'resources/coupons.dart';
import 'resources/customers.dart';
import 'resources/orders.dart';
import 'resources/products.dart';
import 'resources/store_admin.dart';
import 'transport.dart';

/// A connection to one WooCommerce store.
///
/// ```dart
/// final woo = WooCommerce(
///   baseUrl: 'https://shop.example.com',
///   credentials: const WooCredentials.key(
///     consumerKey: 'ck_…',
///     consumerSecret: 'cs_…',
///   ),
/// );
///
/// final page = await woo.products.list(perPage: 20);
/// ```
///
/// Close it when you are done, or pass your own [http.Client] and manage that
/// instead — a client left open keeps its connections alive.
class WooCommerce {
  /// The `User-Agent` this client sends, so a store owner reading their
  /// access log can tell which app is calling.
  ///
  /// A test keeps this in step with the package version. Browsers forbid
  /// setting this header and drop it, so on the web the browser's own
  /// `User-Agent` is sent instead.
  static const String userAgent = wooUserAgent;

  /// Connects to the store at [baseUrl].
  ///
  /// [baseUrl] is the site root, with or without a trailing slash — the
  /// `/wp-json/wc/v3` part is added for you. Pass [apiPath] only if your store
  /// has moved the REST route.
  WooCommerce({
    required String baseUrl,
    this.credentials = const WooCredentials.none(),
    this.apiPath = '/wp-json/wc/v3',
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
    WooRetry retry = const WooRetry.none(),
  }) : _transport = WooTransport(
         baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''),
         timeout: timeout,
         retry: retry,
         httpClient: httpClient,
       ) {
    final bool secret =
        credentials is KeyCredentials || credentials is BasicCredentials;
    if (secret && !Uri.parse(baseUrl).isScheme('https')) {
      // Both of these put a reusable store credential on the wire. WordPress
      // and WooCommerce refuse them over plain HTTP anyway, and sending the
      // secret unencrypted to discover that is worse than refusing here.
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'This credential requires https. WooCommerce rejects consumer keys '
            'and WordPress rejects application passwords over http, and '
            'sending the secret unencrypted to find that out is not worth '
            'doing. Use https, or WooCredentials.bearer against your own '
            'backend.',
      );
    }
  }

  /// Products, variations, and the queries over them.
  late final WooProducts products = WooProducts(this);

  /// Orders: listing, placing, and moving through statuses.
  late final WooOrders orders = WooOrders(this);

  /// Customer accounts.
  late final WooCustomers customers = WooCustomers(this);

  /// Discount codes.
  late final WooCoupons coupons = WooCoupons(this);

  /// Everything else the admin API exposes: categories, tags, attributes,
  /// reviews, shipping, tax, reports, settings, webhooks, system status.
  ///
  /// ```dart
  /// final cats = await woo.admin.productCategories.list();
  /// final vat = await woo.admin.taxRates.list();
  /// final gateways = await woo.admin.paymentGateways();
  /// ```
  late final WooAdminResources admin = WooAdminResources(this);

  /// How this client proves who it is.
  final WooCredentials credentials;

  /// Where the REST route lives, relative to the site root.
  final String apiPath;

  /// How long to wait for the store before giving up.
  final Duration timeout;

  final WooTransport _transport;

  /// Releases the underlying connection, if this client made it.
  ///
  /// Does nothing to an [http.Client] you supplied — that one is yours.
  void close() => _transport.close();

  // ------------------------------------------------------------- requests

  /// Sends a GET and decodes a single object.
  Future<Map<String, Object?>> getOne(
    String path, {
    Map<String, Object?>? query,
  }) async => _asMap(await _send('GET', path, query: query));

  /// Sends a GET and decodes a list, with the store's paging headers.
  Future<WooPage<Map<String, Object?>>> getPage(
    String path, {
    Map<String, Object?>? query,
    int page = 1,
    int perPage = 10,
  }) async {
    final http.Response response = await _send(
      'GET',
      path,
      query: <String, Object?>{...?query, 'page': page, 'per_page': perPage},
    );
    final Object? decoded = _transport.decode(response);
    if (decoded is! List) {
      throw WooBadResponseException(
        'Expected a list from $path but the store sent '
        '${decoded.runtimeType}.',
        statusCode: response.statusCode,
        body: WooTransport.snippet(response.body),
      );
    }
    return WooPage<Map<String, Object?>>(
      items: decoded.whereType<Map<String, Object?>>().toList(growable: false),
      page: page,
      perPage: perPage,
      totalItems: int.tryParse(response.headers['x-wp-total'] ?? ''),
      totalPages: int.tryParse(response.headers['x-wp-totalpages'] ?? ''),
    );
  }

  /// Sends a POST and decodes a single object.
  Future<Map<String, Object?>> post(
    String path,
    Map<String, Object?> body, {
    Map<String, Object?>? query,
  }) async => _asMap(await _send('POST', path, query: query, body: body));

  /// Sends a PUT and decodes a single object.
  Future<Map<String, Object?>> put(
    String path,
    Map<String, Object?> body, {
    Map<String, Object?>? query,
  }) async => _asMap(await _send('PUT', path, query: query, body: body));

  /// Sends a DELETE and decodes a single object.
  ///
  /// WooCommerce keeps most things in the trash unless [force] is set, and
  /// returns the deleted object either way.
  Future<Map<String, Object?>> delete(
    String path, {
    bool force = false,
    Map<String, Object?>? query,
  }) async => _asMap(
    await _send(
      'DELETE',
      path,
      query: <String, Object?>{...?query, 'force': force},
    ),
  );

  /// Sends a PUT whose body is a JSON array, and decodes an array back.
  ///
  /// A handful of WooCommerce routes take a bare list rather than an object —
  /// replacing a shipping zone's locations is the one most people meet.
  Future<List<Map<String, Object?>>> putList(
    String path,
    List<Object?> body,
  ) async => _transport.asList(await _send('PUT', path, body: body));

  // ------------------------------------------------------------- internals

  Uri _uri(String path, Map<String, Object?>? query) {
    final String clean = path.startsWith('/') ? path : '/$path';
    final Map<String, Object?> params = <String, Object?>{
      ...?query,
      if (credentials case final KeyCredentials k) ...<String, Object?>{
        'consumer_key': k.consumerKey,
        'consumer_secret': k.consumerSecret,
      },
    };
    return _transport.uri('$apiPath$clean', params);
  }

  Map<String, String> get _headers => <String, String>{
    if (credentials case final BearerCredentials b)
      'Authorization': 'Bearer ${b.token}',
    if (credentials case final BasicCredentials b)
      'Authorization': 'Basic ${b.encoded}',
  };

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
  }) =>
      _transport.send(method, _uri(path, query), headers: _headers, body: body);

  Map<String, Object?> _asMap(http.Response response) =>
      _transport.asMap(response);
}
