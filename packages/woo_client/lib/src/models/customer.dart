import 'order.dart' show WooAddress;

/// A customer account in the store.
class WooCustomer {
  /// Creates a customer.
  const WooCustomer({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.role,
    required this.isPayingCustomer,
    required this.ordersCount,
    required this.totalSpent,
    required this.avatarUrl,
    required this.billing,
    required this.shipping,
    required this.dateCreated,
    required this.raw,
  });

  /// Reads WooCommerce's representation.
  factory WooCustomer.fromJson(Map<String, Object?> json) => WooCustomer(
    id: (json['id'] as num?)?.toInt() ?? 0,
    email: json['email'] as String? ?? '',
    firstName: json['first_name'] as String? ?? '',
    lastName: json['last_name'] as String? ?? '',
    username: json['username'] as String? ?? '',
    role: json['role'] as String? ?? '',
    isPayingCustomer: json['is_paying_customer'] as bool? ?? false,
    // Present on the list endpoint, absent on some single reads.
    ordersCount: (json['orders_count'] as num?)?.toInt(),
    totalSpent: json['total_spent'] as String?,
    avatarUrl: json['avatar_url'] as String? ?? '',
    billing: WooAddress.fromJson(
      json['billing'] as Map<String, Object?>? ?? const <String, Object?>{},
    ),
    shipping: WooAddress.fromJson(
      json['shipping'] as Map<String, Object?>? ?? const <String, Object?>{},
    ),
    dateCreated: DateTime.tryParse(json['date_created'] as String? ?? ''),
    raw: json,
  );

  /// The customer id.
  final int id;

  /// Their email address.
  final String email;

  /// Given name.
  final String firstName;

  /// Family name.
  final String lastName;

  /// Their WordPress username.
  final String username;

  /// Their WordPress role, usually `customer`.
  final String role;

  /// Whether they have ever completed an order.
  final bool isPayingCustomer;

  /// How many orders they have placed, or null when the store did not say.
  final int? ordersCount;

  /// What they have spent in total, as the store's string, or null.
  final String? totalSpent;

  /// Their Gravatar.
  final String avatarUrl;

  /// Their billing address.
  final WooAddress billing;

  /// Their shipping address.
  final WooAddress shipping;

  /// When the account was made.
  final DateTime? dateCreated;

  /// Everything WooCommerce sent, untouched.
  final Map<String, Object?> raw;

  /// Both names, falling back to the username and then the email.
  String get displayName {
    final String name = '$firstName $lastName'.trim();
    if (name.isNotEmpty) return name;
    return username.isNotEmpty ? username : email;
  }

  @override
  String toString() => 'WooCustomer($id, $email)';
}
