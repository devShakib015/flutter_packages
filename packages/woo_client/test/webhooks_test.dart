import 'dart:convert';

import 'package:test/test.dart';
import 'package:woo_client/woo_client.dart';

void main() {
  const String secret = 'a-shared-secret';
  final String body = jsonEncode(<String, Object?>{
    'id': 5120,
    'status': 'processing',
    'total': '148.00',
  });

  WooWebhookDelivery deliver({String? withBody, String? signedWith}) {
    final String payload = withBody ?? body;
    return WooWebhookDelivery.fromRequest(
      body: payload,
      headers: <String, String>{
        'X-WC-Webhook-Topic': 'order.created',
        'X-WC-Webhook-Resource': 'order',
        'X-WC-Webhook-Event': 'created',
        'X-WC-Webhook-Source': 'https://shop.test',
        'X-WC-Webhook-ID': '7',
        'X-WC-Webhook-Delivery-ID': 'd-99',
        'X-WC-Webhook-Signature': WooWebhookDelivery.signatureFor(
          withBody ?? body,
          signedWith ?? secret,
        ),
      },
    );
  }

  test('reads the delivery headers', () {
    final WooWebhookDelivery d = deliver();
    expect(d.topic, 'order.created');
    expect(d.resource, 'order');
    expect(d.event, 'created');
    expect(d.webhookId, 7);
    expect(d.deliveryId, 'd-99');
    expect(d.source, 'https://shop.test');
    expect(d.resourceId, 5120);
  });

  test('header names are matched case-insensitively', () {
    // Servers normalise headers differently; shelf lowercases, others do not.
    final WooWebhookDelivery d = WooWebhookDelivery.fromRequest(
      body: body,
      headers: <String, String>{'x-wc-webhook-topic': 'product.updated'},
    );
    expect(d.topic, 'product.updated');
    expect(d.resource, 'product');
    expect(d.event, 'updated');
  });

  test('a genuine delivery verifies', () {
    expect(deliver().isSignedWith(secret), isTrue);
  });

  test('a tampered body does not', () {
    // The forgery this exists to stop: someone POSTs "your order is paid".
    final WooWebhookDelivery d = WooWebhookDelivery.fromRequest(
      body: jsonEncode(<String, Object?>{'id': 5120, 'status': 'completed'}),
      headers: <String, String>{
        'X-WC-Webhook-Topic': 'order.updated',
        'X-WC-Webhook-Signature': WooWebhookDelivery.signatureFor(body, secret),
      },
    );
    expect(d.isSignedWith(secret), isFalse);
  });

  test('the wrong secret does not', () {
    expect(deliver(signedWith: 'not-the-secret').isSignedWith(secret), isFalse);
  });

  test('a missing signature does not, and neither does a missing secret', () {
    final WooWebhookDelivery unsigned = WooWebhookDelivery.fromRequest(
      body: body,
      headers: const <String, String>{'X-WC-Webhook-Topic': 'order.created'},
    );
    expect(unsigned.isSignedWith(secret), isFalse);
    expect(deliver().isSignedWith(''), isFalse);
  });

  test('a signature of the wrong length is rejected without comparing', () {
    final WooWebhookDelivery d = WooWebhookDelivery.fromRequest(
      body: body,
      headers: const <String, String>{'X-WC-Webhook-Signature': 'short'},
    );
    expect(d.isSignedWith(secret), isFalse);
  });

  test(
    'the signature is a real HMAC-SHA256, not something self-consistent',
    () {
      // Both values were computed outside Dart. The second is the published
      // HMAC-SHA256 test vector for key "key", so this pins the algorithm to
      // the standard rather than to whatever this package happens to do.
      expect(
        WooWebhookDelivery.signatureFor('hello', 'key'),
        'kwezuRXvtRcf8U2MtV+8x5jGwO8UVtZt7RpqpyOli3s=',
      );
      expect(
        base64Decode(
          WooWebhookDelivery.signatureFor(
            'The quick brown fox jumps over the lazy dog',
            'key',
          ),
        ).map((int b) => b.toRadixString(16).padLeft(2, '0')).join(),
        'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8',
      );
    },
  );

  test('re-encoding the body breaks verification, as it must', () {
    // The commonest support question. Signing a re-serialised body would let
    // any body through, so this has to fail.
    final Map<String, Object?> parsed =
        jsonDecode(body) as Map<String, Object?>;
    final String reencoded = jsonEncode(<String, Object?>{
      'total': parsed['total'],
      'id': parsed['id'],
      'status': parsed['status'],
    });
    final WooWebhookDelivery d = WooWebhookDelivery.fromRequest(
      body: reencoded,
      headers: <String, String>{
        'X-WC-Webhook-Signature': WooWebhookDelivery.signatureFor(body, secret),
      },
    );
    expect(d.isSignedWith(secret), isFalse);
  });
}
