import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A webhook delivery from a WooCommerce store.
///
/// WooCommerce POSTs these when something happens — an order is placed, a
/// product changes, a customer registers. Anyone can POST to your endpoint, so
/// **check the signature before you believe the body**: without that, a
/// stranger can tell your system that an order was paid.
///
/// ```dart
/// // In your server's request handler:
/// final delivery = WooWebhookDelivery.fromRequest(
///   body: await request.readAsString(),
///   headers: request.headers,
/// );
///
/// if (!delivery.isSignedWith(secret)) {
///   return Response.forbidden('bad signature');
/// }
///
/// switch (delivery.topic) {
///   case 'order.created':
///     await handleNewOrder(WooOrder.fromJson(delivery.json));
///   case 'product.updated':
///     await reindex(delivery.resourceId);
/// }
/// ```
class WooWebhookDelivery {
  /// Creates a delivery.
  const WooWebhookDelivery({
    required this.body,
    required this.topic,
    required this.signature,
    this.source = '',
    this.deliveryId = '',
    this.resource = '',
    this.event = '',
    this.webhookId = 0,
  });

  /// Reads a delivery from a request's raw [body] and its [headers].
  ///
  /// [body] must be the **exact bytes as text** that arrived. Decoding to JSON
  /// and re-encoding changes the whitespace and key order, and the signature
  /// will then never match — this is the single commonest reason webhook
  /// verification "does not work".
  factory WooWebhookDelivery.fromRequest({
    required String body,
    required Map<String, String> headers,
  }) {
    final Map<String, String> lower = <String, String>{
      for (final MapEntry<String, String> e in headers.entries)
        e.key.toLowerCase(): e.value,
    };
    final String topic = lower['x-wc-webhook-topic'] ?? '';
    final List<String> halves = topic.split('.');
    return WooWebhookDelivery(
      body: body,
      topic: topic,
      resource: lower['x-wc-webhook-resource'] ?? halves.first,
      event:
          lower['x-wc-webhook-event'] ?? (halves.length > 1 ? halves[1] : ''),
      signature: lower['x-wc-webhook-signature'] ?? '',
      source: lower['x-wc-webhook-source'] ?? '',
      deliveryId: lower['x-wc-webhook-delivery-id'] ?? '',
      webhookId: int.tryParse(lower['x-wc-webhook-id'] ?? '') ?? 0,
    );
  }

  /// The exact body that arrived.
  final String body;

  /// What happened, such as `order.created`.
  final String topic;

  /// The resource half of [topic], such as `order`.
  final String resource;

  /// The event half of [topic], such as `created`.
  final String event;

  /// The `X-WC-Webhook-Signature` header: base64 of an HMAC-SHA256.
  final String signature;

  /// The store that sent it.
  final String source;

  /// This delivery's id, for de-duplicating retries.
  final String deliveryId;

  /// The id of the webhook that fired.
  final int webhookId;

  /// The body, decoded.
  ///
  /// Throws [FormatException] if the body is not JSON — which, for an
  /// unverified delivery, is something a stranger controls, so verify first.
  Map<String, Object?> get json =>
      jsonDecode(body) as Map<String, Object?>? ?? const <String, Object?>{};

  /// The id of the thing that changed, when the payload carries one.
  int get resourceId => (json['id'] as num?)?.toInt() ?? 0;

  /// Whether this really came from a store holding [secret].
  ///
  /// Compares in constant time, so the check does not leak how much of a
  /// forged signature was right.
  bool isSignedWith(String secret) {
    if (signature.isEmpty || secret.isEmpty) return false;
    return _constantTimeEquals(signature, signatureFor(body, secret));
  }

  /// The signature a store holding [secret] would send for [payload].
  ///
  /// Exposed for testing your own handlers: sign a fixture with it and your
  /// test exercises the real verification path.
  static String signatureFor(String payload, String secret) => base64Encode(
    Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(payload)).bytes,
  );

  /// Compares without an early exit, so timing says nothing about the answer.
  static bool _constantTimeEquals(String a, String b) {
    final List<int> x = utf8.encode(a);
    final List<int> y = utf8.encode(b);
    // Length is not secret — it is fixed by the algorithm — but comparing
    // different lengths must still not short-circuit inside the loop.
    if (x.length != y.length) return false;
    int diff = 0;
    for (int i = 0; i < x.length; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }

  @override
  String toString() =>
      'WooWebhookDelivery($topic${deliveryId.isEmpty ? '' : ', $deliveryId'})';
}
