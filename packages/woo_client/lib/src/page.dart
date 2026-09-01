/// One page of a list response, with the totals WooCommerce reports alongside.
///
/// The store returns `X-WP-Total` and `X-WP-TotalPages` headers, which is the
/// only way to know how much there is. Returning a bare `List` throws them
/// away and leaves every caller to guess whether to ask for more.
class WooPage<T> {
  /// Creates a page.
  const WooPage({
    required this.items,
    required this.page,
    required this.perPage,
    required this.totalItems,
    required this.totalPages,
  });

  /// What came back.
  final List<T> items;

  /// Which page this is, starting at 1.
  final int page;

  /// How many were asked for.
  final int perPage;

  /// How many exist in total, or null when the store did not say.
  final int? totalItems;

  /// How many pages exist in total, or null when the store did not say.
  final int? totalPages;

  /// Whether asking for [page] + 1 would return anything.
  ///
  /// Falls back to "the page came back full" when the store sent no totals,
  /// which is the best available guess and is right except on an exact
  /// multiple.
  bool get hasMore => totalPages != null
      ? page < totalPages!
      : items.length == perPage && items.isNotEmpty;

  /// The page number to ask for next, or null if this is the end.
  int? get nextPage => hasMore ? page + 1 : null;

  /// Whether nothing came back.
  bool get isEmpty => items.isEmpty;

  /// Whether anything came back.
  bool get isNotEmpty => items.isNotEmpty;

  /// How many items are on this page.
  int get length => items.length;

  /// Maps the items, keeping the paging information.
  WooPage<R> map<R>(R Function(T item) transform) => WooPage<R>(
    items: items.map(transform).toList(growable: false),
    page: page,
    perPage: perPage,
    totalItems: totalItems,
    totalPages: totalPages,
  );

  @override
  String toString() =>
      'WooPage(${items.length} of ${totalItems ?? "?"}, '
      'page $page of ${totalPages ?? "?"})';
}
