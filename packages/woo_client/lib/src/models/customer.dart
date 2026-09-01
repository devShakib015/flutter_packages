import '../json.dart';
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
    id: readInt(json['id'], orElse: 0),
    email: readString(json['email']),
    firstName: readString(json['first_name']),
    lastName: readString(json['last_name']),
    username: readString(json['username']),
    role: readString(json['role']),
    isPayingCustomer: readBool(json['is_paying_customer']),
    // Present on the list endpoint, absent on some single reads.
    ordersCount: readIntOrNull(json['orders_count']),
    totalSpent: json.containsKey('total_spent')
        ? readString(json['total_spent'])
        : null,
    avatarUrl: readString(json['avatar_url']),
    billing: WooAddress.fromJson(readMap(json['billing'])),
    shipping: WooAddress.fromJson(readMap(json['shipping'])),
    dateCreated: DateTime.tryParse(readString(json['date_created'])),
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
