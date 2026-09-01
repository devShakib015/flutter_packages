import '../client.dart';
import '../models/customer.dart';
import '../page.dart';

/// Customers and the queries over them.
class WooCustomers {
  /// Creates the resource. Reached through `WooCommerce.customers`.
  const WooCustomers(this._client);

  final WooCommerce _client;

  /// Lists customers.
  Future<WooPage<WooCustomer>> list({
    int page = 1,
    int perPage = 10,
    String? search,
    String? email,
    String? role,
    List<int>? include,
    List<int>? exclude,
    bool descending = true,
  }) async {
    final WooPage<Map<String, Object?>> raw = await _client.getPage(
      '/customers',
      page: page,
      perPage: perPage,
      query: <String, Object?>{
        'search': search,
        'email': email,
        'role': role,
        'include': include,
        'exclude': exclude,
        'order': descending ? 'desc' : 'asc',
      },
    );
    return raw.map(WooCustomer.fromJson);
  }

  /// Fetches one customer.
  Future<WooCustomer> get(int id) async =>
      WooCustomer.fromJson(await _client.getOne('/customers/$id'));

  /// Finds a customer by email, or null when there is none.
  ///
  /// [email] is sent exactly as given. Whether the match is case sensitive is
  /// the store database's decision, not this client's: MySQL's usual
  /// collations ignore case, but a store on a binary collation will not. That
  /// is why this does not lowercase, while `WooCoupons.byCode` does — coupon
  /// codes are lowercased by WooCommerce itself before they are stored.
  Future<WooCustomer?> byEmail(String email) async {
    final WooPage<WooCustomer> found = await list(email: email, perPage: 1);
    return found.isEmpty ? null : found.items.first;
  }

  /// Creates a customer.
  Future<WooCustomer> create(Map<String, Object?> fields) async =>
      WooCustomer.fromJson(await _client.post('/customers', fields));

  /// Updates a customer, changing only the fields given.
  Future<WooCustomer> update(int id, Map<String, Object?> fields) async =>
      WooCustomer.fromJson(await _client.put('/customers/$id', fields));

  /// Deletes a customer.
  ///
  /// WooCommerce requires `force` here — customers have no trash — so this
  /// always deletes permanently, and says so rather than offering a flag that
  /// does nothing.
  Future<WooCustomer> delete(int id, {int? reassignTo}) async =>
      WooCustomer.fromJson(
        await _client.delete(
          '/customers/$id',
          force: true,
          query: <String, Object?>{'reassign': reassignTo},
        ),
      );
}
