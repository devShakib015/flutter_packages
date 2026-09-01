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
