import '../client.dart';
import '../models/product.dart';
import '../page.dart';

/// How to sort a product listing.
enum WooProductOrderBy {
  /// By publication date.
  date,

  /// By product id.
  id,

  /// By name.
  title,

  /// By URL slug.
  slug,

  /// By price.
  price,

  /// By popularity, which WooCommerce takes to mean total sales.
  popularity,

  /// By average review score.
  rating;

  /// The string WooCommerce expects.
  String get wireName => name;
}

/// Products, variations and the queries over them.
class WooProducts {
  /// Creates the resource. Reached through `WooCommerce.products`.
  const WooProducts(this._client);

  final WooCommerce _client;

  /// Lists products.
  ///
  /// Every filter is optional and maps to a WooCommerce query parameter.
  /// [after] and [before] filter on creation date, which is the usual way to
  /// pull only what changed since a previous sync.
  Future<WooPage<WooProduct>> list({
    int page = 1,
    int perPage = 10,
    String? search,
    String? slug,
    String? sku,
    String? status,
    WooProductType? type,
    List<int>? categories,
    List<int>? tags,
    List<int>? include,
    List<int>? exclude,
    bool? featured,
    bool? onSale,
    String? minPrice,
    String? maxPrice,
    DateTime? after,
    DateTime? before,
    WooProductOrderBy orderBy = WooProductOrderBy.date,
    bool descending = true,
  }) async {
    final WooPage<Map<String, Object?>> raw = await _client.getPage(
      '/products',
      page: page,
      perPage: perPage,
      query: <String, Object?>{
        'search': search,
        'slug': slug,
        'sku': sku,
        'status': status,
        'type': type == null || type == WooProductType.unknown
            ? null
            : type.name,
        'category': categories,
        'tag': tags,
        'include': include,
        'exclude': exclude,
        'featured': featured,
        'on_sale': onSale,
        'min_price': minPrice,
        'max_price': maxPrice,
        'after': after,
        'before': before,
        'orderby': orderBy.wireName,
        'order': descending ? 'desc' : 'asc',
      },
    );
    return raw.map(WooProduct.fromJson);
  }

  /// Fetches one product.
  ///
  /// Throws [WooNotFoundException] when there is no such product.
  Future<WooProduct> get(int id) async =>
      WooProduct.fromJson(await _client.getOne('/products/$id'));

  /// Fetches one product by SKU, or null when nothing matches.
  ///
  /// WooCommerce has no by-SKU route, so this is a filtered list — which is
  /// also why it can return null rather than throwing.
  Future<WooProduct?> bySku(String sku) async {
    final WooPage<WooProduct> found = await list(sku: sku, perPage: 1);
    return found.isEmpty ? null : found.items.first;
  }

  /// The variations of a variable product.
  Future<WooPage<WooProduct>> variations(
    int productId, {
    int page = 1,
    int perPage = 100,
  }) async {
    final WooPage<Map<String, Object?>> raw = await _client.getPage(
      '/products/$productId/variations',
      page: page,
      perPage: perPage,
    );
    return raw.map(WooProduct.fromJson);
  }

  /// Creates a product. Requires a key with write access.
  Future<WooProduct> create(Map<String, Object?> fields) async =>
      WooProduct.fromJson(await _client.post('/products', fields));

  /// Updates a product, changing only the fields given.
  Future<WooProduct> update(int id, Map<String, Object?> fields) async =>
      WooProduct.fromJson(await _client.put('/products/$id', fields));

  /// Deletes a product.
  ///
  /// WooCommerce moves it to the trash unless [force] is set, and returns the
  /// product either way.
  Future<WooProduct> delete(int id, {bool force = false}) async =>
      WooProduct.fromJson(await _client.delete('/products/$id', force: force));

  /// Walks every page, yielding products as they arrive.
  ///
  /// Useful for a sync, where holding the whole catalogue in memory is worse
  /// than streaming it. Stops when the store says there are no more pages.
  Stream<WooProduct> all({int perPage = 100, String? status}) async* {
    int page = 1;
    while (true) {
      final WooPage<WooProduct> current = await list(
        page: page,
        perPage: perPage,
        status: status,
      );
      for (final WooProduct product in current.items) {
        yield product;
      }
      final int? next = current.nextPage;
      if (next == null) return;
      page = next;
    }
  }
}
