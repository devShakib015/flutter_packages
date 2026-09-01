/// How to prove to the store who you are.
///
/// WooCommerce accepts the consumer key and secret as query parameters over
/// HTTPS, and this is the ordinary way to authenticate a REST client.
///
/// **Do not ship these in an app you hand to users.** Anyone with the binary
/// can read them, and a WooCommerce key is not scoped to one customer — a read
/// key exposes every order in the store, and a write key is worse. The safe
/// shape is a small server of your own that holds the key and re-exposes only
/// what a customer may see. This client is happy talking to that server
/// instead; see [WooCredentials.bearer].
sealed class WooCredentials {
  const WooCredentials._();

  /// A WooCommerce consumer key and secret, sent as query parameters.
  ///
  /// Requires HTTPS. WooCommerce rejects key authentication over plain HTTP,
  /// and so does this client, rather than sending your secret in the clear.
  const factory WooCredentials.key({
    required String consumerKey,
    required String consumerSecret,
  }) = KeyCredentials;

  /// An `Authorization: Bearer` token, for talking to your own backend or a
  /// JWT plugin rather than to WooCommerce directly.
  const factory WooCredentials.bearer(String token) = BearerCredentials;

  /// No credentials. Enough for public product listings on some stores.
  const factory WooCredentials.none() = NoCredentials;
}

/// Consumer key and secret.
final class KeyCredentials extends WooCredentials {
  /// Creates key credentials.
  const KeyCredentials({
    required this.consumerKey,
    required this.consumerSecret,
  }) : super._();

  /// The `ck_…` key.
  final String consumerKey;

  /// The `cs_…` secret.
  final String consumerSecret;
}

/// A bearer token.
final class BearerCredentials extends WooCredentials {
  /// Creates bearer credentials.
  const BearerCredentials(this.token) : super._();

  /// The token, sent as `Authorization: Bearer <token>`.
  final String token;
}

/// Nothing.
final class NoCredentials extends WooCredentials {
  /// Creates empty credentials.
  const NoCredentials() : super._();
}
