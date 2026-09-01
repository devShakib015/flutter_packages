import '../client.dart';
import '../models/coupon.dart';
import '../page.dart';

/// Coupons and the queries over them.
class WooCoupons {
  /// Creates the resource. Reached through `WooCommerce.coupons`.
  const WooCoupons(this._client);

  final WooCommerce _client;

  /// Lists coupons.
  Future<WooPage<WooCoupon>> list({
    int page = 1,
    int perPage = 10,
    String? search,
    String? code,
    List<int>? include,
    List<int>? exclude,
    DateTime? after,
    DateTime? before,
  }) async {
    final WooPage<Map<String, Object?>> raw = await _client.getPage(
      '/coupons',
      page: page,
      perPage: perPage,
      query: <String, Object?>{
        'search': search,
        'code': code,
        'include': include,
        'exclude': exclude,
        'after': after,
        'before': before,
      },
    );
    return raw.map(WooCoupon.fromJson);
  }

  /// Fetches one coupon.
  Future<WooCoupon> get(int id) async =>
      WooCoupon.fromJson(await _client.getOne('/coupons/$id'));

  /// Looks a coupon up by the code a customer types, or null when there is
  /// none.
  ///
  /// WooCommerce lowercases coupon codes, so this does too — otherwise
  /// `SAVE10` finds nothing while `save10` works, which is a confusing thing
  /// to debug.
  Future<WooCoupon?> byCode(String code) async {
    final WooPage<WooCoupon> found = await list(
      code: code.toLowerCase(),
      perPage: 1,
    );
    return found.isEmpty ? null : found.items.first;
  }

  /// Creates a coupon.
  Future<WooCoupon> create(Map<String, Object?> fields) async =>
      WooCoupon.fromJson(await _client.post('/coupons', fields));

  /// Updates a coupon, changing only the fields given.
  Future<WooCoupon> update(int id, Map<String, Object?> fields) async =>
      WooCoupon.fromJson(await _client.put('/coupons/$id', fields));

  /// Deletes a coupon, to the trash unless [force] is set.
  Future<WooCoupon> delete(int id, {bool force = false}) async =>
      WooCoupon.fromJson(await _client.delete('/coupons/$id', force: force));
}
