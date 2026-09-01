import 'dart:async';

/// Where a cart token is kept between requests, and between app launches.
///
/// The default keeps it in memory, which means a cart survives a screen but
/// not a restart. To keep a shopper's basket, implement this over whatever
/// storage you already use — `shared_preferences`, `flutter_secure_storage`,
/// a file — and hand it to [CartSession].
///
/// ```dart
/// class PrefsCartTokens implements CartTokenStore {
///   PrefsCartTokens(this._prefs);
///   final SharedPreferences _prefs;
///
///   @override
///   Future<String?> read() async => _prefs.getString('woo_cart_token');
///
///   @override
///   Future<void> write(String? token) async => token == null
///       ? await _prefs.remove('woo_cart_token')
///       : await _prefs.setString('woo_cart_token', token);
/// }
/// ```
abstract interface class CartTokenStore {
  /// The stored token, or null when there is no cart yet.
  Future<String?> read();

  /// Stores [token], or forgets it when [token] is null.
  Future<void> write(String? token);
}

/// Keeps the token for as long as the process lives.
class InMemoryCartTokenStore implements CartTokenStore {
  /// Creates a store, optionally starting from a token you already have.
  InMemoryCartTokenStore([this._token]);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String? token) async => _token = token;
}

/// Holds the tokens that identify one shopper's cart.
///
/// The Store API is unauthenticated, so a cart is identified by a `Cart-Token`
/// header the store issues on the first `/cart` request. Send it back on every
/// later request and you get the same cart; forget it and the shopper's basket
/// is gone.
///
/// A `Cart-Token` also removes the nonce requirement — which matters, because
/// a nonce can only be minted by WordPress itself (`wp_create_nonce`), so an
/// app has no way to produce one. Token-based is the only workable flow for a
/// client that is not a web page on the store's own domain.
///
/// This class does the bookkeeping: it reads the tokens out of every response
/// and puts them back on every request. You rarely touch it directly.
class CartSession {
  /// Creates a session backed by [tokens], in memory when none is given.
  CartSession({CartTokenStore? tokens})
    : _tokens = tokens ?? InMemoryCartTokenStore();

  final CartTokenStore _tokens;
  String? _nonce;

  /// The current cart token, or null before the first request.
  Future<String?> get cartToken => _tokens.read();

  /// The most recent nonce the store sent back.
  ///
  /// Only useful when running inside the store's own site, where a nonce is
  /// available. Token-based clients can ignore it.
  String? get nonce => _nonce;

  /// Adopts a token obtained elsewhere — from a web view, or from a previous
  /// run of the app.
  Future<void> adopt(String token) => _tokens.write(token);

  /// Forgets the cart, so the next request starts an empty one.
  ///
  /// Use this after a successful checkout, or when a shopper signs out.
  Future<void> clear() async {
    _nonce = null;
    await _tokens.write(null);
  }

  /// Headers to attach to a Store API request.
  Future<Map<String, String>> headers() async {
    final String? token = await _tokens.read();
    return <String, String>{
      if (token case final String t) 'Cart-Token': t,
      if (_nonce case final String n) 'Nonce': n,
    };
  }

  /// Records the tokens a response carried.
  Future<void> absorb(Map<String, String> responseHeaders) async {
    // Header names arrive lowercased from dart:io and may not from a browser.
    final Map<String, String> lower = <String, String>{
      for (final MapEntry<String, String> e in responseHeaders.entries)
        e.key.toLowerCase(): e.value,
    };
    if (lower['nonce'] case final String n when n.isNotEmpty) _nonce = n;
    if (lower['cart-token'] case final String t when t.isNotEmpty) {
      await _tokens.write(t);
    }
  }
}
