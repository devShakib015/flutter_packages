import '../../page.dart';
import '../models/store_product.dart';
import '../store.dart';

/// How to order a public product listing.
enum StoreProductOrderBy {
  /// By publication date.
  date,

  /// By price.
  price,

  /// By average review score.
  rating,

  /// By how many have sold.
  popularity,

  /// By name.
  title,

  /// By menu order, which is the order the store owner arranged.
  menuOrder,

  /// By how well it matched the search term. Only meaningful with a search.
  relevance;

  /// WooCommerce's own spelling.
  String get wireName => switch (this) {
    date => 'date',
    price => 'price',
    rating => 'rating',
    popularity => 'popularity',
    title => 'title',
    menuOrder => 'menu_order',
    relevance => 'relevance',
  };
}

/// Public product browsing, with no API keys.
///
/// The same catalogue a shopper sees on the website: published products only,
/// prices in the store's own formatting, and nothing an admin would not want
/// public.
class StoreProducts {
  /// Wraps [_store]'s product routes.
  StoreProducts(this._store);

  final WooStore _store;

  /// Lists products.
  ///
  /// ```dart
  /// final page = await store.products.list(
  ///   search: 'beanie',
  ///   category: 21,
  ///   orderBy: StoreProductOrderBy.popularity,
  /// );
  /// ```
  Future<WooPage<StoreProduct>> list({
    int page = 1,
    int perPage = 10,
    String? search,
    List<String>? slugs,
    int? category,
    int? tag,
    List<int>? include,
    List<int>? exclude,
    int? offset,
    String? minPrice,
    String? maxPrice,
    String? stockStatus,
    bool? onSale,
    bool? featured,
    int? parent,
    String? type,
    StoreProductOrderBy orderBy = StoreProductOrderBy.date,
    bool descending = true,
  }) async {
    final WooPage<Map<String, Object?>> raw = await _store.getPage(
      '/products',
      page: page,
      perPage: perPage,
      query: <String, Object?>{
        'search': search,
        'slug': slugs,
        'category': category,
        'tag': tag,
        'include': include,
        'exclude': exclude,
        'offset': offset,
        'min_price': minPrice,
        'max_price': maxPrice,
        'stock_status': stockStatus,
        'on_sale': onSale,
        'featured': featured,
        'parent': parent,
        'type': type,
        'orderby': orderBy.wireName,
        'order': descending ? 'desc' : 'asc',
      },
    );
    return raw.map(StoreProduct.fromJson);
  }

  /// One product by id.
  Future<StoreProduct> get(int id) async =>
      StoreProduct.fromJson(await _store.getOne('/products/$id'));

  /// One product by URL slug, or null when there is none.
  ///
  /// Useful for deep links, which carry the slug rather than the id.
  Future<StoreProduct?> bySlug(String slug) async {
    final WooPage<StoreProduct> found = await list(
      slugs: <String>[slug],
      perPage: 1,
    );
    return found.isEmpty ? null : found.items.first;
  }

  /// The variations of a variable product.
  ///
  /// The Store API lists variations as ordinary products whose `parent` is the
  /// variable product.
  Future<WooPage<StoreProduct>> variations(int productId) =>
      list(parent: productId, perPage: 100, type: 'variation');

  /// Every product, page by page.
  ///
  /// Fetches the next page only when you are ready for it, and stops when you
  /// stop listening.
  Stream<StoreProduct> all({int perPage = 100, String? search}) async* {
    int page = 1;
    while (true) {
      final WooPage<StoreProduct> got = await list(
        page: page,
        perPage: perPage,
        search: search,
      );
      if (got.isEmpty) return;
      yield* Stream<StoreProduct>.fromIterable(got.items);
      if (!got.hasMore) return;
      page++;
    }
  }

  /// Product categories.
  Future<List<StoreTerm>> categories() async => <StoreTerm>[
    for (final Map<String, Object?> j in await _store.getList(
      '/products/categories',
      query: <String, Object?>{'per_page': 100},
    ))
      StoreTerm.fromJson(j),
  ];

  /// Product tags.
  Future<List<StoreTerm>> tags() async => <StoreTerm>[
    for (final Map<String, Object?> j in await _store.getList(
      '/products/tags',
      query: <String, Object?>{'per_page': 100},
    ))
      StoreTerm.fromJson(j),
  ];

  /// Reviews for a product, or for the whole store when [productId] is null.
  Future<List<Map<String, Object?>>> reviews({
    int? productId,
    int perPage = 10,
  }) => _store.getList(
    '/products/reviews',
    query: <String, Object?>{'product_id': ?productId, 'per_page': perPage},
  );
}
