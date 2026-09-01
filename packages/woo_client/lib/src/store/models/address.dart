import '../../json.dart';

/// A shopper's address, as the Store API represents it.
///
/// Every field is optional because a cart holds a partial address long before
/// it holds a complete one — a shopper who has typed only a postcode still
/// gets shipping quotes.
class StoreAddress {
  /// Creates an address.
  const StoreAddress({
    this.firstName = '',
    this.lastName = '',
    this.company = '',
    this.address1 = '',
    this.address2 = '',
    this.city = '',
    this.state = '',
    this.postcode = '',
    this.country = '',
    this.email = '',
    this.phone = '',
  });

  /// Reads the Store API's representation.
  factory StoreAddress.fromJson(Map<String, Object?> json) => StoreAddress(
    firstName: readString(json['first_name']),
    lastName: readString(json['last_name']),
    company: readString(json['company']),
    address1: readString(json['address_1']),
    address2: readString(json['address_2']),
    city: readString(json['city']),
    state: readString(json['state']),
    postcode: readString(json['postcode']),
    country: readString(json['country']),
    email: readString(json['email']),
    phone: readString(json['phone']),
  );

  /// Given name.
  final String firstName;

  /// Family name.
  final String lastName;

  /// Company, when the shopper gave one.
  final String company;

  /// First line of the street address.
  final String address1;

  /// Second line of the street address.
  final String address2;

  /// Town or city.
  final String city;

  /// State, province, or district — an ISO code or a name.
  final String state;

  /// Postal or ZIP code.
  final String postcode;

  /// Two-letter ISO country code, such as `GB`.
  final String country;

  /// Email. Shipping addresses do not carry one.
  final String email;

  /// Telephone number.
  final String phone;

  /// First and last name together, with no stray space when one is missing.
  String get fullName =>
      <String>[firstName, lastName].where((String s) => s.isNotEmpty).join(' ');

  /// Whether every field is empty, which is how a cart starts.
  bool get isEmpty =>
      firstName.isEmpty &&
      lastName.isEmpty &&
      address1.isEmpty &&
      city.isEmpty &&
      postcode.isEmpty &&
      country.isEmpty;

  /// A copy with the given fields replaced.
  StoreAddress copyWith({
    String? firstName,
    String? lastName,
    String? company,
    String? address1,
    String? address2,
    String? city,
    String? state,
    String? postcode,
    String? country,
    String? email,
    String? phone,
  }) => StoreAddress(
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    company: company ?? this.company,
    address1: address1 ?? this.address1,
    address2: address2 ?? this.address2,
    city: city ?? this.city,
    state: state ?? this.state,
    postcode: postcode ?? this.postcode,
    country: country ?? this.country,
    email: email ?? this.email,
    phone: phone ?? this.phone,
  );

  /// The Store API's representation.
  ///
  /// Sends every field, including the empty ones: the Store API treats an
  /// absent field as "leave it alone", so omitting them would make it
  /// impossible to clear a line of an address the shopper deleted.
  Map<String, Object?> toJson() => <String, Object?>{
    'first_name': firstName,
    'last_name': lastName,
    'company': company,
    'address_1': address1,
    'address_2': address2,
    'city': city,
    'state': state,
    'postcode': postcode,
    'country': country,
    if (email.isNotEmpty) 'email': email,
    if (phone.isNotEmpty) 'phone': phone,
  };

  @override
  String toString() =>
      'StoreAddress(${<String>[fullName, city, country].where((String s) => s.isNotEmpty).join(', ')})';
}
