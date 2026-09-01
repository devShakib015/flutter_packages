import 'dart:convert';

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

  /// A WordPress **Application Password**, sent as HTTP Basic.
  ///
  /// Built into WordPress since 5.6, so no plugin is needed. A user creates
  /// one under Users → Profile → Application Passwords, and it can be revoked
  /// on its own without touching their real password.
  ///
  /// Better than a consumer key for anything acting *as a person*: the request
  /// runs with that user's capabilities, so a shop manager cannot do what an
  /// administrator can, and the audit trail names them. Requires HTTPS —
  /// WordPress refuses to issue application passwords over plain HTTP.
  ///
  /// Still a full credential, so the warning above applies: not in a shipped
  /// app.
  const factory WooCredentials.applicationPassword({
    required String username,
    required String password,
  }) = BasicCredentials;

  /// No credentials. Enough for the public Store API, and for public product
  /// listings on some stores.
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

/// A username and password, sent as HTTP Basic.
final class BasicCredentials extends WooCredentials {
  /// Creates basic credentials.
  const BasicCredentials({required this.username, required this.password})
    : super._();

  /// The WordPress user name.
  final String username;

  /// The application password. WordPress shows it in groups of four
  /// characters; the spaces are cosmetic and are stripped here, because
  /// pasting them in is the commonest reason this fails.
  final String password;

  /// The base64 of `username:password`, as the header wants it.
  String get encoded =>
      base64Encode(utf8.encode('$username:${password.replaceAll(' ', '')}'));
}

/// Nothing.
final class NoCredentials extends WooCredentials {
  /// Creates empty credentials.
  const NoCredentials() : super._();
}
