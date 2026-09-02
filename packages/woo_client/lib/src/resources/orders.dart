import '../client.dart';
import '../models/order.dart';
import '../page.dart';
import 'collection.dart';

/// Orders and the queries over them.
class WooOrders {
  /// Creates the resource. Reached through `WooCommerce.orders`.
  const WooOrders(this._client);

  final WooCommerce _client;

  /// Lists orders.
  Future<WooPage<WooOrder>> list({
    int page = 1,
    int perPage = 10,
    String? search,
    List<WooOrderStatus>? statuses,
    int? customerId,
    int? productId,
    List<int>? include,
    List<int>? exclude,
    DateTime? after,
    DateTime? before,
    bool descending = true,
  }) async {
    final WooPage<Map<String, Object?>> raw = await _client.getPage(
      '/orders',
      page: page,
      perPage: perPage,
      query: <String, Object?>{
        'search': search,
        // unknown has no wire form, so it cannot be a filter. Dropping it
        // beats sending 'pending' and quietly listing the wrong orders.
        'status': statuses
            ?.where((WooOrderStatus s) => s != WooOrderStatus.unknown)
            .map((WooOrderStatus s) => s.wireName)
            .toList(growable: false),
        'customer': customerId,
        'product': productId,
        'include': include,
        'exclude': exclude,
        'after': after,
        'before': before,
        'order': descending ? 'desc' : 'asc',
      },
    );
    return raw.map(WooOrder.fromJson);
  }

  /// Fetches one order.
  Future<WooOrder> get(int id) async =>
      WooOrder.fromJson(await _client.getOne('/orders/$id'));

  /// Places an order.
  ///
  /// The line items carry only product and quantity — the store prices them.
  /// That is deliberate: a client that sent its own prices would let a
  /// tampered app decide what things cost.
  Future<WooOrder> create({
    required List<WooLineItem> lineItems,
    WooAddress? billing,
    WooAddress? shipping,
    String? paymentMethod,
    String? paymentMethodTitle,
    String? customerNote,
    int? customerId,
    bool setPaid = false,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    assert(lineItems.isNotEmpty, 'an order needs at least one line');
    return WooOrder.fromJson(
      await _client.post('/orders', <String, Object?>{
        'line_items': lineItems
            .map((WooLineItem l) => l.toJson())
            .toList(growable: false),
        'billing': ?billing?.toJson(),
        'shipping': ?shipping?.toJson(),
        'payment_method': ?paymentMethod,
        'payment_method_title': ?paymentMethodTitle,
        'customer_note': ?customerNote,
        'customer_id': ?customerId,
        'set_paid': setPaid,
        ...extra,
      }),
    );
  }

  /// Moves an order to a new status.
  Future<WooOrder> setStatus(int id, WooOrderStatus status) async =>
      WooOrder.fromJson(
        await _client.put('/orders/$id', <String, Object?>{
          'status': status.wireName,
        }),
      );

  /// Moves an order to a status this package does not model.
  ///
  /// For plugin statuses — a subscription state, a booking state, a shop's own
  /// workflow. [status] is sent verbatim, so pass WooCommerce's own spelling
  /// (`awaiting-pickup`, not `awaitingPickup`); read the current one from
  /// `WooOrder.statusName`.
  Future<WooOrder> setStatusRaw(int id, String status) async =>
      WooOrder.fromJson(
        await _client.put('/orders/$id', <String, Object?>{'status': status}),
      );

  /// Updates an order, changing only the fields given.
  Future<WooOrder> update(int id, Map<String, Object?> fields) async =>
      WooOrder.fromJson(await _client.put('/orders/$id', fields));

  /// Deletes an order, to the trash unless [force] is set.
  Future<WooOrder> delete(int id, {bool force = false}) async =>
      WooOrder.fromJson(await _client.delete('/orders/$id', force: force));

  /// Walks every page, yielding orders as they arrive.
  Stream<WooOrder> all({
    int perPage = 100,
    List<WooOrderStatus>? statuses,
    DateTime? after,
  }) async* {
    int page = 1;
    while (true) {
      final WooPage<WooOrder> current = await list(
        page: page,
        perPage: perPage,
        statuses: statuses,
        after: after,
      );
      for (final WooOrder order in current.items) {
        yield order;
      }
      final int? next = current.nextPage;
      if (next == null) return;
      page = next;
    }
  }

  /// Creates, updates, and deletes in one request.
  ///
  /// WooCommerce handles up to 100 operations per call. For a catalogue sync
  /// this is the difference between a minute and an hour.
  ///
  /// ```dart
  /// await woo.orders.batch(
  ///   update: [
  ///     {'id': 799, 'regular_price': '119.00'},
  ///     {'id': 812, 'stock_quantity': 0},
  ///   ],
  /// );
  /// ```
  Future<WooBatchResult<WooOrder>> batch({
    List<Map<String, Object?>> create = const <Map<String, Object?>>[],
    List<Map<String, Object?>> update = const <Map<String, Object?>>[],
    List<int> delete = const <int>[],
  }) => WooCollection<WooOrder>(
    _client,
    '/orders',
    WooOrder.fromJson,
  ).batch(create: create, update: update, delete: delete);
}
