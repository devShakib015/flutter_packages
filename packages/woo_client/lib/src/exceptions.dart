/// Base class for everything this client throws.
///
/// A `switch` over the subclasses is exhaustive, so a caller can handle
/// "your credentials are wrong" differently from "that product is gone"
/// without matching on strings.
sealed class WooException implements Exception {
  /// Creates an exception.
  const WooException(this.message, {this.code, this.statusCode});

  /// What went wrong, in words. Comes from WooCommerce where it said
  /// something useful, and from this client where it did not.
  final String message;

  /// WooCommerce's own error code, such as `woocommerce_rest_invalid_id`.
  final String? code;

  /// The HTTP status, when there was one.
  final int? statusCode;

  @override
  String toString() {
    final String detail = <String>[
      if (statusCode != null) 'HTTP $statusCode',
      ?code,
    ].join(' ');
    return detail.isEmpty
        ? '$runtimeType: $message'
        : '$runtimeType($detail): $message';
  }
}

/// The store rejected the credentials, or they are missing a permission.
///
/// Most often the key lacks write access, or the request reached the store
/// over plain HTTP where WooCommerce refuses key authentication entirely.
class WooAuthException extends WooException {
  /// Creates the exception.
  const WooAuthException(super.message, {super.code, super.statusCode});
}

/// The thing asked for is not there.
class WooNotFoundException extends WooException {
  /// Creates the exception.
  const WooNotFoundException(super.message, {super.code, super.statusCode});
}

/// The store understood the request and refused it — a missing required
/// field, an invalid value, a duplicate SKU.
class WooInvalidRequestException extends WooException {
  /// Creates the exception.
  const WooInvalidRequestException(
    super.message, {
    super.code,
    super.statusCode,
    this.details,
  });

  /// Whatever WooCommerce put in `data`, which for validation failures names
  /// the offending parameters.
  final Map<String, Object?>? details;
}

/// The store is there but broke while answering.
class WooServerException extends WooException {
  /// Creates the exception.
  const WooServerException(super.message, {super.code, super.statusCode});
}

/// The request never got an answer — no network, DNS failure, timeout.
///
/// Distinct from [WooServerException] because retrying is often reasonable
/// here and rarely reasonable there.
class WooNetworkException extends WooException {
  /// Creates the exception.
  const WooNetworkException(super.message, {this.cause});

  /// The underlying error, if you need it.
  final Object? cause;
}

/// The store answered with something that is not the JSON this client expects.
///
/// Usually a WordPress plugin printing a notice before the JSON body, or an
/// HTML login page where the REST route should be.
class WooBadResponseException extends WooException {
  /// Creates the exception.
  const WooBadResponseException(super.message, {super.statusCode, this.body});

  /// The first part of what came back, to make the cause obvious.
  final String? body;
}

/// The store is refusing requests because too many arrived too quickly.
///
/// WooCommerce can rate limit the Store API, and hosts often rate limit the
/// whole REST API. Distinct from [WooServerException] because the fix is to
/// wait exactly [retryAfter] and try again, not to give up.
class WooRateLimitException extends WooException {
  /// Creates the exception.
  const WooRateLimitException(
    super.message, {
    super.code,
    super.statusCode,
    this.retryAfter,
    this.limit,
    this.remaining,
  });

  /// How long to wait, when the store said. Comes from `RateLimit-Retry-After`
  /// or the standard `Retry-After` header.
  final Duration? retryAfter;

  /// Requests allowed per window, when the store said.
  final int? limit;

  /// Requests left in this window, when the store said.
  final int? remaining;
}

/// The shopper confirmed a total the store no longer agrees with.
///
/// Thrown when a checkout was submitted with an `expectedTotal` and something
/// changed underneath — a coupon expired, stock ran out, a shipping rate
/// moved. Nothing was charged. Show [cart] and ask the shopper again.
class WooTotalMismatchException extends WooException {
  /// Creates the exception.
  const WooTotalMismatchException(
    super.message, {
    super.code,
    super.statusCode,
    this.cart,
  });

  /// The store's refreshed cart, so you can show the new total without a
  /// second round trip. Null if the store did not include one.
  final Map<String, Object?>? cart;
}
