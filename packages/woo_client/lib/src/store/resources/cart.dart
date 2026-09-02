import '../../exceptions.dart';
import '../../json.dart';
import '../models/address.dart';
import '../models/cart.dart';
import '../store.dart';

/// The shopper's cart.
///
/// Every method returns the whole cart afterwards, because that is what the
/// Store API sends back — adding one item can change shipping, tax, and which
/// coupons still apply, so a partial answer would be a lie. Render the result
/// and you are always in step with the store.
class StoreCartResource {
  /// Wraps [_store]'s cart routes.
  StoreCartResource(this._store);

  final WooStore _store;

  /// The current cart.
  ///
  /// The first call creates a cart and takes a `Cart-Token`, which every later
  /// call reuses.
  Future<StoreCart> get() async =>
      StoreCart.fromJson(await _store.getOne('/cart'));

  /// Adds [quantity] of the product or variation [id].
  ///
  /// For a variable product, pass [variation] — the id must be the
  /// **variation's** id, and the keys are attribute names as the store spells
  /// them. `StoreAttribute.wireName` gives you the right spelling: global
  /// attributes use their `pa_` taxonomy, product-specific ones use the name,
  /// and both are case sensitive.
  ///
  /// ```dart
  /// await store.cart.addItem(
  ///   id: 815,
  ///   variation: {'pa_colour': 'blue', 'Size': 'Large'},
  /// );
  /// ```
  Future<StoreCart> addItem({
    required int id,
    int quantity = 1,
    Map<String, String>? variation,
  }) async => StoreCart.fromJson(
    await _store.post(
      '/cart/add-item',
      body: <String, Object?>{
        'id': id,
        'quantity': quantity,
        if (variation != null && variation.isNotEmpty)
          'variation': <Object?>[
            for (final MapEntry<String, String> e in variation.entries)
              <String, Object?>{'attribute': e.key, 'value': e.value},
          ],
      },
    ),
  );

  /// Changes the quantity of the line [key].
  ///
  /// [key] is [StoreCartItem.key], not a product id — one product can occupy
  /// two lines with different options.
  Future<StoreCart> updateItem({
    required String key,
    required int quantity,
  }) async => StoreCart.fromJson(
    await _store.post(
      '/cart/update-item',
      body: <String, Object?>{'key': key, 'quantity': quantity},
    ),
  );

  /// Removes the line [key].
  Future<StoreCart> removeItem(String key) async => StoreCart.fromJson(
    await _store.post('/cart/remove-item', body: <String, Object?>{'key': key}),
  );

  /// Empties the cart.
  ///
  /// The Store API has no "empty cart" route, so this removes each line in one
  /// batch request rather than one round trip per item.
  Future<StoreCart> clear() async {
    final StoreCart current = await get();
    if (current.isEmpty) return current;
    _throwIfAnyFailed(
      await _store.batch(<StoreBatchRequest>[
        for (final StoreCartItem i in current.items)
          StoreBatchRequest.removeItem(i.key),
      ]),
      'remove',
    );
    return get();
  }

  /// Applies a coupon.
  ///
  /// The code is lowercased, because WooCommerce lowercases coupon codes when
  /// it stores them and would otherwise not find `SAVE10`.
  ///
  /// Throws [WooInvalidRequestException] when the store rejects it — expired,
  /// not applicable, minimum not met — with the shopper-facing reason in
  /// `message`.
  Future<StoreCart> applyCoupon(String code) async => StoreCart.fromJson(
    await _store.post(
      '/cart/apply-coupon',
      body: <String, Object?>{'code': code.toLowerCase()},
    ),
  );

  /// Removes a coupon.
  Future<StoreCart> removeCoupon(String code) async => StoreCart.fromJson(
    await _store.post(
      '/cart/remove-coupon',
      body: <String, Object?>{'code': code.toLowerCase()},
    ),
  );

  /// Sets the shopper's addresses, which is what makes shipping quotes appear.
  ///
  /// Call this as soon as you have a country and postcode — you do not need a
  /// full address for the store to quote. The returned cart has
  /// `shippingPackages` filled in and `hasCalculatedShipping` true.
  Future<StoreCart> updateCustomer({
    StoreAddress? billingAddress,
    StoreAddress? shippingAddress,
  }) async => StoreCart.fromJson(
    await _store.post(
      '/cart/update-customer',
      body: <String, Object?>{
        if (billingAddress != null) 'billing_address': billingAddress.toJson(),
        if (shippingAddress != null)
          'shipping_address': shippingAddress.toJson(),
      },
    ),
  );

  /// Chooses a shipping rate for one package.
  ///
  /// [packageId] is [StoreShippingPackage.packageId] and [rateId] is
  /// [StoreShippingRate.rateId] — usually you pass a rate the shopper tapped.
  Future<StoreCart> selectShippingRate({
    required int packageId,
    required String rateId,
  }) async => StoreCart.fromJson(
    await _store.post(
      '/cart/select-shipping-rate',
      body: <String, Object?>{'package_id': packageId, 'rate_id': rateId},
    ),
  );

  /// Adds several items in one round trip.
  ///
  /// One request and one cart recalculation instead of one of each per item.
  /// Worth it for a "buy it again" button, or restoring a saved basket.
  Future<StoreCart> addItems(Map<int, int> quantitiesByProductId) async {
    if (quantitiesByProductId.isEmpty) return get();
    _throwIfAnyFailed(
      await _store.batch(<StoreBatchRequest>[
        for (final MapEntry<int, int> e in quantitiesByProductId.entries)
          StoreBatchRequest.addItem(id: e.key, quantity: e.value),
      ]),
      'add',
    );
    return get();
  }

  /// The Store API's batch endpoint reports per-request status and keeps going
  /// after a failure, so an out-of-stock item in a batch of five is a 200 with
  /// one bad entry inside. Silently returning the cart would hide it.
  static void _throwIfAnyFailed(
    List<Map<String, Object?>> responses,
    String verb,
  ) {
    final List<Map<String, Object?>> failed = <Map<String, Object?>>[
      for (final Map<String, Object?> r in responses)
        if ((readIntOrNull(r['status']) ?? 200) >= 400) r,
    ];
    if (failed.isEmpty) return;
    final String why = failed
        .map((Map<String, Object?> r) {
          final Map<String, Object?> body = readMap(r['body']);
          return readString(body['message']).isEmpty
              ? 'HTTP ${r['status']}'
              : readString(body['message']);
        })
        .join('; ');
    throw WooInvalidRequestException(
      'The store refused to $verb ${failed.length} of ${responses.length} '
      'items: $why',
      code: 'woocommerce_rest_batch_partial_failure',
      details: <String, Object?>{'failed': failed},
    );
  }
}
