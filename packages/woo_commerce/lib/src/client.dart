import 'dart:convert';

import 'package:http/http.dart' as http;

import 'credentials.dart';
import 'exceptions.dart';
import 'page.dart';
import 'resources/coupons.dart';
import 'resources/customers.dart';
import 'resources/orders.dart';
import 'resources/products.dart';

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
  static const String userAgent = 'woo_commerce/0.1.0 (Dart)';

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
  }) : _base = Uri.parse(
         baseUrl.endsWith('/')
             ? baseUrl.substring(0, baseUrl.length - 1)
             : baseUrl,
       ),
       _http = httpClient ?? http.Client(),
       _ownsClient = httpClient == null {
    if (credentials is KeyCredentials && !_base.isScheme('https')) {
      // WooCommerce refuses key auth over plain HTTP, and sending a secret in
      // the clear to find that out is worse than refusing here.
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Key authentication requires https. WooCommerce rejects consumer keys '
            'over http, and sending the secret unencrypted to discover that is '
            'not worth doing. Use https, or WooCredentials.bearer against your '
            'own backend.',
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

  /// How this client proves who it is.
  final WooCredentials credentials;

  /// Where the REST route lives, relative to the site root.
  final String apiPath;

  /// How long to wait for the store before giving up.
  final Duration timeout;

  final Uri _base;
  final http.Client _http;
  final bool _ownsClient;
  bool _closed = false;

  /// Releases the underlying connection, if this client made it.
  ///
  /// Does nothing to an [http.Client] you supplied — that one is yours.
  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _http.close();
  }

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
    final Object? decoded = _decode(response);
    if (decoded is! List) {
      throw WooBadResponseException(
        'Expected a list from $path but the store sent '
        '${decoded.runtimeType}.',
        statusCode: response.statusCode,
        body: _snippet(response.body),
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

  // ------------------------------------------------------------- internals

  Uri _uri(String path, Map<String, Object?>? query) {
    final String clean = path.startsWith('/') ? path : '/$path';
    final Map<String, String> params = <String, String>{
      for (final MapEntry<String, Object?> e
          in (query ?? const <String, Object?>{}).entries)
        if (e.value != null) e.key: _encode(e.value!),
    };
    if (credentials case final KeyCredentials k) {
      params['consumer_key'] = k.consumerKey;
      params['consumer_secret'] = k.consumerSecret;
    }
    return _base.replace(
      path: '${_base.path}$apiPath$clean',
      queryParameters: params.isEmpty ? null : params,
    );
  }

  /// WooCommerce takes repeated values as `key[]=a&key[]=b`, but its filters
  /// also accept comma-separated lists, which survive a `Map<String, String>`.
  static String _encode(Object value) => switch (value) {
    final List<Object?> list => list.map((Object? e) => '$e').join(','),
    final DateTime date => date.toUtc().toIso8601String(),
    final bool flag => flag ? 'true' : 'false',
    _ => '$value',
  };

  Map<String, String> get _headers => <String, String>{
    'Accept': 'application/json',
    // Store owners read their access logs, and security plugins block clients
    // they cannot name. Browsers forbid setting this and will drop it.
    'User-Agent': userAgent,
    'Content-Type': 'application/json; charset=utf-8',
    if (credentials case final BearerCredentials b)
      'Authorization': 'Bearer ${b.token}',
  };

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? body,
  }) async {
    if (_closed) {
      throw StateError('This WooCommerce client has been closed.');
    }
    final Uri uri = _uri(path, query);
    final http.Request request = http.Request(method, uri)
      ..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      );
    } on WooException {
      rethrow;
    } catch (e) {
      // No answer at all: DNS, TLS, timeout, offline. Worth its own type
      // because retrying is usually reasonable and rarely is for a 4xx.
      throw WooNetworkException('Could not reach $uri: $e', cause: e);
    }
    if (response.statusCode >= 400) throw _errorFor(response);
    return response;
  }

  Object? _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw WooBadResponseException(
        'The store did not send JSON. A plugin printing a notice before the '
        'body, or an HTML page where the REST route should be, both look like '
        'this.',
        statusCode: response.statusCode,
        body: _snippet(response.body),
      );
    }
  }

  Map<String, Object?> _asMap(http.Response response) {
    final Object? decoded = _decode(response);
    if (decoded is Map<String, Object?>) return decoded;
    throw WooBadResponseException(
      'Expected an object but the store sent ${decoded.runtimeType}.',
      statusCode: response.statusCode,
      body: _snippet(response.body),
    );
  }

  /// Turns WooCommerce's error body into something catchable by kind.
  WooException _errorFor(http.Response response) {
    final int status = response.statusCode;
    String message = 'The store returned HTTP $status.';
    String? code;
    Map<String, Object?>? data;
    try {
      final Object? decoded = jsonDecode(response.body);
      if (decoded is Map<String, Object?>) {
        message = decoded['message'] as String? ?? message;
        code = decoded['code'] as String?;
        data = decoded['data'] as Map<String, Object?>?;
      }
    } catch (_) {
      // A non-JSON error body is common when something ahead of WordPress
      // answered — a firewall, a maintenance page. Keep the status.
    }
    return switch (status) {
      401 || 403 => WooAuthException(message, code: code, statusCode: status),
      404 => WooNotFoundException(message, code: code, statusCode: status),
      >= 500 => WooServerException(message, code: code, statusCode: status),
      _ => WooInvalidRequestException(
        message,
        code: code,
        statusCode: status,
        details: data,
      ),
    };
  }

  static String _snippet(String body) =>
      body.length <= 200 ? body : '${body.substring(0, 200)}…';
}
