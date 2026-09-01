import '../client.dart';
import '../page.dart';

/// The shape every WooCommerce collection shares.
///
/// WooCommerce's REST API is highly regular: almost every resource is a list,
/// a get, a create, an update, a delete, and a batch, at one path. This models
/// that once so the twenty-odd smaller resources are a line each instead of a
/// file each — and so they all get paging, streaming, and batching rather than
/// only the ones someone got round to.
///
/// Filters differ per resource and are passed as [query]; the WooCommerce REST
/// documentation lists them per endpoint. The four resources people spend
/// their time in — products, orders, customers, coupons — have named
/// parameters instead.
class WooCollection<T> {
  /// Creates a collection at [path], parsing items with [parse].
  WooCollection(this._client, this.path, this.parse);

  final WooCommerce _client;

  /// The REST path, such as `/products/categories`.
  final String path;

  /// Turns one JSON object into a [T].
  final T Function(Map<String, Object?>) parse;

  /// Lists items.
  Future<WooPage<T>> list({
    int page = 1,
    int perPage = 10,
    Map<String, Object?> query = const <String, Object?>{},
  }) async {
    final WooPage<Map<String, Object?>> raw = await _client.getPage(
      path,
      page: page,
      perPage: perPage,
      query: query,
    );
    return raw.map(parse);
  }

  /// Fetches one item.
  Future<T> get(int id) async => parse(await _client.getOne('$path/$id'));

  /// Creates an item.
  Future<T> create(Map<String, Object?> fields) async =>
      parse(await _client.post(path, fields));

  /// Updates an item, changing only the fields given.
  Future<T> update(int id, Map<String, Object?> fields) async =>
      parse(await _client.put('$path/$id', fields));

  /// Deletes an item.
  Future<T> delete(int id, {bool force = false}) async =>
      parse(await _client.delete('$path/$id', force: force));

  /// Every item, page by page.
  Stream<T> all({
    int perPage = 100,
    Map<String, Object?> query = const <String, Object?>{},
  }) async* {
    int page = 1;
    while (true) {
      final WooPage<T> got = await list(
        page: page,
        perPage: perPage,
        query: query,
      );
      if (got.isEmpty) return;
      yield* Stream<T>.fromIterable(got.items);
      if (!got.hasMore) return;
      page++;
    }
  }

  /// Creates, updates, and deletes in one request.
  ///
  /// WooCommerce handles up to 100 operations per call, which is the
  /// difference between a catalogue sync that takes a minute and one that
  /// takes an hour. Items to update and delete must carry an `id`.
  ///
  /// ```dart
  /// await woo.productCategories.batch(
  ///   create: [{'name': 'Bags'}, {'name': 'Belts'}],
  ///   update: [{'id': 21, 'description': 'Leather bags'}],
  ///   delete: [44],
  /// );
  /// ```
  ///
  /// Returns what the store did, split the same way. A failure in one
  /// operation does not fail the others — check each returned item.
  Future<WooBatchResult<T>> batch({
    List<Map<String, Object?>> create = const <Map<String, Object?>>[],
    List<Map<String, Object?>> update = const <Map<String, Object?>>[],
    List<int> delete = const <int>[],
  }) async {
    if (create.length + update.length + delete.length > 100) {
      // WooCommerce silently truncates past its limit, which looks like data
      // loss. Say so instead.
      throw ArgumentError(
        'WooCommerce accepts at most 100 operations per batch; this one has '
        '${create.length + update.length + delete.length}. Split it.',
      );
    }
    final Map<String, Object?> body = await _client.post(
      '$path/batch',
      <String, Object?>{
        if (create.isNotEmpty) 'create': create,
        if (update.isNotEmpty) 'update': update,
        if (delete.isNotEmpty) 'delete': delete,
      },
    );
    List<T> read(String key) => <T>[
      for (final Object? e in body[key] as List<Object?>? ?? const [])
        if (e is Map<String, Object?>) parse(e),
    ];
    return WooBatchResult<T>(
      created: read('create'),
      updated: read('update'),
      deleted: read('delete'),
    );
  }
}

/// What a batch call did.
class WooBatchResult<T> {
  /// Creates a result.
  const WooBatchResult({
    required this.created,
    required this.updated,
    required this.deleted,
  });

  /// Items created.
  final List<T> created;

  /// Items updated.
  final List<T> updated;

  /// Items deleted.
  final List<T> deleted;

  /// How many operations the store reported on.
  int get total => created.length + updated.length + deleted.length;

  @override
  String toString() =>
      'WooBatchResult(+${created.length} ~${updated.length} '
      '-${deleted.length})';
}
