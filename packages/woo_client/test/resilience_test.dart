import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:woo_client/woo_client.dart';

void main() {
  WooCommerce admin(http.Client c, {WooRetry retry = const WooRetry.none()}) =>
      WooCommerce(
        baseUrl: 'https://shop.test',
        credentials: const WooCredentials.key(
          consumerKey: 'ck',
          consumerSecret: 'cs',
        ),
        httpClient: c,
        retry: retry,
      );

  group('rate limiting', () {
    test('429 is its own exception, carrying how long to wait', () async {
      final WooCommerce woo = admin(
        MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'code': 'too_many_requests',
              'message': 'Too many requests.',
            }),
            429,
            headers: <String, String>{
              'content-type': 'application/json',
              'ratelimit-limit': '5',
              'ratelimit-remaining': '0',
              'ratelimit-retry-after': '28',
            },
          ),
        ),
      );
      addTearDown(woo.close);

      try {
        await woo.products.list();
        fail('should have thrown');
      } on WooRateLimitException catch (e) {
        expect(e.retryAfter, const Duration(seconds: 28));
        expect(e.limit, 5);
        expect(e.remaining, 0);
      }
    });

    test('a plain Retry-After in seconds is understood too', () async {
      // WooCommerce sends RateLimit-Retry-After; the host in front of it
      // sends the standard header, and only one of the two usually appears.
      final WooCommerce woo = admin(
        MockClient(
          (_) async => http.Response(
            '{}',
            429,
            headers: <String, String>{
              'content-type': 'application/json',
              'retry-after': '12',
            },
          ),
        ),
      );
      addTearDown(woo.close);
      await expectLater(
        woo.products.list(),
        throwsA(
          isA<WooRateLimitException>().having(
            (WooRateLimitException e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 12),
          ),
        ),
      );
    });

    test('a Retry-After given as a date is understood', () async {
      final WooCommerce woo = admin(
        MockClient(
          (_) async => http.Response(
            '{}',
            429,
            headers: <String, String>{
              'content-type': 'application/json',
              'retry-after': 'Sun, 06 Nov 2044 08:49:37 GMT',
            },
          ),
        ),
      );
      addTearDown(woo.close);
      try {
        await woo.products.list();
        fail('should have thrown');
      } on WooRateLimitException catch (e) {
        expect(e.retryAfter, isNotNull);
        expect(e.retryAfter!.inDays, greaterThan(1000));
      }
    });
  });

  group('retry', () {
    test('is off unless asked for', () async {
      int calls = 0;
      final WooCommerce woo = admin(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 503);
        }),
      );
      addTearDown(woo.close);
      await expectLater(
        woo.products.list(),
        throwsA(isA<WooServerException>()),
      );
      expect(calls, 1);
    });

    test('retries a read past a 5xx and succeeds', () async {
      int calls = 0;
      final WooCommerce woo = admin(
        MockClient((_) async {
          calls++;
          if (calls < 3) return http.Response('{}', 503);
          return http.Response(
            '[]',
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
        retry: const WooRetry.reads(baseDelay: Duration(milliseconds: 1)),
      );
      addTearDown(woo.close);

      final WooPage<WooProduct> page = await woo.products.list();
      expect(page.items, isEmpty);
      expect(calls, 3);
    });

    test('gives up after the allowed attempts', () async {
      int calls = 0;
      final WooCommerce woo = admin(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 500);
        }),
        retry: const WooRetry.reads(
          attempts: 2,
          baseDelay: Duration(milliseconds: 1),
        ),
      );
      addTearDown(woo.close);
      await expectLater(
        woo.products.list(),
        throwsA(isA<WooServerException>()),
      );
      expect(calls, 2);
    });

    test('never retries a write under WooRetry.reads', () async {
      // Retrying a POST /orders that timed out after the store accepted it
      // creates the order twice. That is not a tradeoff to make silently.
      int calls = 0;
      final WooCommerce woo = admin(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 503);
        }),
        retry: const WooRetry.reads(baseDelay: Duration(milliseconds: 1)),
      );
      addTearDown(woo.close);

      await expectLater(
        woo.orders.create(
          lineItems: <WooLineItem>[
            WooLineItem.order(productId: 1, quantity: 1),
          ],
        ),
        throwsA(isA<WooServerException>()),
      );
      expect(calls, 1);
    });

    test('retries a write only when explicitly told to', () async {
      int calls = 0;
      final WooCommerce woo = admin(
        MockClient((_) async {
          calls++;
          if (calls < 2) return http.Response('{}', 503);
          return http.Response(
            '{"id":1}',
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
        retry: const WooRetry.everything(baseDelay: Duration(milliseconds: 1)),
      );
      addTearDown(woo.close);

      await woo.products.create(const <String, Object?>{'name': 'Tote'});
      expect(calls, 2);
    });

    test('does not retry a 4xx, because it will fail the same way', () async {
      int calls = 0;
      final WooCommerce woo = admin(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 400);
        }),
        retry: const WooRetry.reads(baseDelay: Duration(milliseconds: 1)),
      );
      addTearDown(woo.close);
      await expectLater(
        woo.products.list(),
        throwsA(isA<WooInvalidRequestException>()),
      );
      expect(calls, 1);
    });

    test('waits as long as the store asked, not its own guess', () {
      const WooRetry retry = WooRetry.reads(baseDelay: Duration(seconds: 1));
      const WooRateLimitException limited = WooRateLimitException(
        'slow down',
        retryAfter: Duration(seconds: 30),
      );
      // Guessing shorter than the store asked only gets refused again.
      expect(retry.delayFor(1, limited), const Duration(seconds: 30));
    });

    test('backs off exponentially otherwise', () {
      const WooRetry retry = WooRetry.reads(
        baseDelay: Duration(milliseconds: 100),
      );
      const WooServerException boom = WooServerException('boom');
      final int first = retry.delayFor(1, boom).inMilliseconds;
      final int second = retry.delayFor(2, boom).inMilliseconds;
      final int third = retry.delayFor(3, boom).inMilliseconds;
      expect(first, greaterThanOrEqualTo(100));
      expect(second, greaterThan(first));
      expect(third, greaterThan(second));
    });

    test('a network failure is retried', () async {
      int calls = 0;
      final WooCommerce woo = admin(
        MockClient((_) async {
          calls++;
          if (calls < 2) throw const SocketishException();
          return http.Response(
            '[]',
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
        retry: const WooRetry.reads(baseDelay: Duration(milliseconds: 1)),
      );
      addTearDown(woo.close);
      await woo.products.list();
      expect(calls, 2);
    });
  });

  group('application passwords', () {
    test('go in an Authorization header, base64 encoded', () async {
      late http.Request seen;
      final WooCommerce woo = WooCommerce(
        baseUrl: 'https://shop.test',
        credentials: const WooCredentials.applicationPassword(
          username: 'ada',
          password: 'abcd EFGH ijkl MNOP qrst UVWX',
        ),
        httpClient: MockClient((http.Request r) async {
          seen = r;
          return http.Response(
            '[]',
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(woo.close);
      await woo.products.list();

      // WordPress shows the password in groups of four; the spaces are
      // cosmetic, and pasting them in is the commonest reason this fails.
      expect(
        seen.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('ada:abcdEFGHijklMNOPqrstUVWX'))}',
      );
      expect(seen.url.queryParameters.containsKey('consumer_key'), isFalse);
    });

    test('are refused over plain http, like a consumer key', () {
      expect(
        () => WooCommerce(
          baseUrl: 'http://shop.test',
          credentials: const WooCredentials.applicationPassword(
            username: 'ada',
            password: 'secret',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

/// Stands in for a dart:io SocketException, which is not importable on web.
class SocketishException implements Exception {
  const SocketishException();
  @override
  String toString() => 'Connection refused';
}
