import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show parseHttpDate;

import 'exceptions.dart';

/// The `User-Agent` this package sends, so a store owner reading their access
/// log can tell which app is calling.
///
/// A test keeps this in step with the package version. Browsers forbid setting
/// this header and drop it, so on the web the browser's own is sent instead.
const String wooUserAgent = 'woo_client/0.2.1 (Dart)';

/// When to try a failed request again.
///
/// Retrying is off by default, because retrying is only safe when you know the
/// request is idempotent and this package cannot know that for a POST that
/// creates an order. [WooRetry.reads] is the sensible middle: GETs only.
///
/// ```dart
/// final woo = WooCommerce(
///   baseUrl: 'https://shop.example.com',
///   credentials: ...,
///   retry: const WooRetry.reads(),
/// );
/// ```
class WooRetry {
  /// Retries nothing.
  const WooRetry.none()
    : attempts = 1,
      readsOnly = true,
      baseDelay = Duration.zero;

  /// Retries GET requests only — safe, because a GET changes nothing.
  ///
  /// This is what almost everyone wants. A failed read costs a retry; a failed
  /// write is handed back to you to decide about.
  const WooRetry.reads({
    this.attempts = 3,
    this.baseDelay = const Duration(milliseconds: 400),
  }) : readsOnly = true;

  /// Retries every method, including writes.
  ///
  /// Only choose this if every call you make is idempotent. Retrying a
  /// `POST /orders` that timed out after the store accepted it creates the
  /// order twice.
  const WooRetry.everything({
    this.attempts = 3,
    this.baseDelay = const Duration(milliseconds: 400),
  }) : readsOnly = false;

  /// How many times to try in total, including the first.
  final int attempts;

  /// Whether only GET requests are retried.
  final bool readsOnly;

  /// The first backoff. Later ones double, plus jitter.
  final Duration baseDelay;

  /// Whether a request with this [method] and [error] should be tried again.
  bool shouldRetry(String method, Object error) {
    if (attempts <= 1) return false;
    if (readsOnly && method != 'GET') return false;
    return switch (error) {
      WooNetworkException() => true,
      WooServerException() => true,
      WooRateLimitException() => true,
      _ => false,
    };
  }

  /// How long to wait before try number [attempt], counting from one.
  ///
  /// Honours the store's own `Retry-After` when it sent one, since guessing
  /// shorter than the store asked only gets the next request refused too.
  Duration delayFor(int attempt, Object error) {
    if (error case WooRateLimitException(retryAfter: final Duration d)) {
      return d;
    }
    final int factor = 1 << (attempt - 1);
    final int millis = baseDelay.inMilliseconds * factor;
    // Deterministic jitter, so two clients that failed together do not retry
    // together. Seeded from the attempt, so tests stay predictable.
    final int jitter = (millis * 0.2 * ((attempt * 7919) % 100) / 100).round();
    return Duration(milliseconds: millis + jitter);
  }
}

/// Everything the two clients share: sending, decoding, and failing well.
///
/// Internal to the package.
class WooTransport {
  /// Creates a transport.
  WooTransport({
    required this.baseUrl,
    required this.timeout,
    required this.retry,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client(),
       _ownsClient = httpClient == null;

  /// The site root, with no trailing slash.
  final String baseUrl;

  /// How long to wait for one attempt.
  final Duration timeout;

  /// When to try again.
  final WooRetry retry;

  final http.Client _http;
  final bool _ownsClient;
  bool _closed = false;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  /// Builds a URI under [baseUrl].
  Uri uri(String path, [Map<String, Object?>? query]) {
    final Uri base = Uri.parse(baseUrl);
    final Map<String, String> params = <String, String>{
      for (final MapEntry<String, Object?> e in (query ?? const {}).entries)
        if (e.value != null &&
            !(e.value is Iterable && (e.value as Iterable).isEmpty))
          e.key: _param(e.value),
    };
    return base.replace(
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}$path',
      queryParameters: params.isEmpty ? null : params,
    );
  }

  static String _param(Object? value) => switch (value) {
    final List<Object?> list => list.map((Object? e) => '$e').join(','),
    final DateTime date => date.toUtc().toIso8601String(),
    final bool flag => flag ? 'true' : 'false',
    _ => '$value',
  };

  /// Sends one request, retrying according to [retry].
  Future<http.Response> send(
    String method,
    Uri target, {
    Map<String, String> headers = const <String, String>{},
    Object? body,
  }) async {
    if (_closed) {
      throw StateError('This client has been closed.');
    }
    Object? last;
    for (int attempt = 1; attempt <= math.max(1, retry.attempts); attempt++) {
      try {
        return await _once(method, target, headers, body);
      } on Object catch (e) {
        last = e;
        final bool more = attempt < retry.attempts;
        if (!more || !retry.shouldRetry(method, e)) rethrow;
        await Future<void>.delayed(retry.delayFor(attempt, e));
      }
    }
    throw last!;
  }

  Future<http.Response> _once(
    String method,
    Uri target,
    Map<String, String> headers,
    Object? body,
  ) async {
    final http.Request request = http.Request(method, target)
      ..headers.addAll(<String, String>{
        'Accept': 'application/json',
        'User-Agent': wooUserAgent,
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
        ...headers,
      });
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
      throw WooNetworkException('Could not reach $target: $e', cause: e);
    }
    if (response.statusCode >= 400) throw errorFor(response);
    return response;
  }

  /// Decodes a JSON body, or explains why it could not.
  Object? decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw WooBadResponseException(
        'The store did not send JSON. A plugin printing a notice before the '
        'body, or an HTML page where the REST route should be, both look like '
        'this.',
        statusCode: response.statusCode,
        body: snippet(response.body),
      );
    }
  }

  /// Decodes a JSON object, or explains why it could not.
  Map<String, Object?> asMap(http.Response response) {
    final Object? decoded = decode(response);
    if (decoded is Map<String, Object?>) return decoded;
    throw WooBadResponseException(
      'Expected an object but the store sent ${decoded.runtimeType}.',
      statusCode: response.statusCode,
      body: snippet(response.body),
    );
  }

  /// Decodes a JSON array of objects, or explains why it could not.
  List<Map<String, Object?>> asList(http.Response response) {
    final Object? decoded = decode(response);
    if (decoded is List<Object?>) {
      return <Map<String, Object?>>[
        for (final Object? e in decoded)
          if (e is Map<String, Object?>) e,
      ];
    }
    throw WooBadResponseException(
      'Expected a list but the store sent ${decoded.runtimeType}.',
      statusCode: response.statusCode,
      body: snippet(response.body),
    );
  }

  /// Turns an error response into something catchable by kind.
  WooException errorFor(http.Response response) {
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

    if (status == 429) {
      return WooRateLimitException(
        message,
        code: code,
        statusCode: status,
        retryAfter: _retryAfter(response.headers),
        limit: int.tryParse(response.headers['ratelimit-limit'] ?? ''),
        remaining: int.tryParse(response.headers['ratelimit-remaining'] ?? ''),
      );
    }
    if (status == 409 && code == 'woocommerce_rest_checkout_total_mismatch') {
      return WooTotalMismatchException(
        message,
        code: code,
        statusCode: status,
        cart: data?['cart'] as Map<String, Object?>?,
      );
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

  static Duration? _retryAfter(Map<String, String> headers) {
    // WooCommerce sends RateLimit-Retry-After; hosts and proxies send the
    // standard Retry-After, which may be seconds or an HTTP date.
    final String? woo = headers['ratelimit-retry-after'];
    if (int.tryParse(woo ?? '') case final int s) return Duration(seconds: s);
    final String? std = headers['retry-after'];
    if (std == null) return null;
    if (int.tryParse(std) case final int s) return Duration(seconds: s);
    final DateTime? when = _httpDate(std);
    if (when == null) return null;
    final Duration d = when.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  static DateTime? _httpDate(String value) {
    try {
      return parseHttpDate(value);
    } catch (_) {
      return null;
    }
  }

  /// The first part of a body, for putting in an error message.
  static String snippet(String body) =>
      body.length <= 300 ? body : '${body.substring(0, 300)}…';

  /// Releases the underlying HTTP client, if this created it.
  void close() {
    _closed = true;
    if (_ownsClient) _http.close();
  }
}
