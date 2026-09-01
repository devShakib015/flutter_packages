import 'money.dart';

/// Whether a product is on sale, and how it is sold.
enum WooProductType {
  /// A single item.
  simple,

  /// A product with variations, each with its own price and stock.
  variable,

  /// A product made of other products.
  grouped,

  /// A link out to somewhere else.
  external,

  /// Something this client does not recognise. The original string is in
  /// [WooProduct.raw] under `type`.
  unknown;

  /// Reads WooCommerce's value.
  static WooProductType parse(Object? value) => switch (value) {
    'simple' => simple,
    'variable' => variable,
    'grouped' => grouped,
    'external' => external,
    _ => unknown,
  };
}

/// Whether the store will sell it right now.
enum WooStockStatus {
  /// Available.
  inStock,

  /// Not available.
  outOfStock,

  /// Orderable, arriving later.
  onBackorder,

  /// Something this client does not recognise.
  unknown;

  /// Reads WooCommerce's value.
  static WooStockStatus parse(Object? value) => switch (value) {
    'instock' => inStock,
    'outofstock' => outOfStock,
    'onbackorder' => onBackorder,
    _ => unknown,
  };
}

/// An image attached to a product.
class WooImage {
  /// Creates an image.
  const WooImage({required this.id, required this.src, required this.alt});

  /// Reads WooCommerce's representation.
  factory WooImage.fromJson(Map<String, Object?> json) => WooImage(
    id: (json['id'] as num?)?.toInt() ?? 0,
    src: json['src'] as String? ?? '',
    alt: json['alt'] as String? ?? '',
  );

  /// The attachment id.
  final int id;

  /// Where the image is.
  final String src;

  /// Alternative text, which stores frequently leave empty.
  final String alt;

  @override
  String toString() => 'WooImage($id)';
}

/// A category or tag a product belongs to.
class WooTerm {
  /// Creates a term.
  const WooTerm({required this.id, required this.name, required this.slug});

  /// Reads WooCommerce's representation.
  factory WooTerm.fromJson(Map<String, Object?> json) => WooTerm(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    slug: json['slug'] as String? ?? '',
  );

  /// The term id.
  final int id;

  /// Its display name.
  final String name;

  /// Its URL slug.
  final String slug;

  @override
  String toString() => 'WooTerm($name)';
}

/// A product in the store.
///
/// WooCommerce sends a large object with a long tail of fields, plugins add
/// more, and the shape shifts between versions. The named fields below are the
/// ones almost every store has; **[raw] is always the whole response**, so a
/// field this client does not model is still reachable and a field WooCommerce
/// renames leaves the typed value empty rather than throwing.
class WooProduct {
  /// Creates a product.
  const WooProduct({
    required this.id,
    required this.name,
    required this.slug,
    required this.permalink,
    required this.type,
    required this.status,
    required this.description,
    required this.shortDescription,
    required this.sku,
    required this.price,
    required this.regularPrice,
    required this.salePrice,
    required this.onSale,
    required this.stockStatus,
    required this.stockQuantity,
    required this.manageStock,
    required this.categories,
    required this.tags,
    required this.images,
    required this.variations,
    required this.averageRating,
    required this.ratingCount,
    required this.dateCreated,
    required this.dateModified,
    required this.raw,
  });

  /// Reads WooCommerce's representation.
  factory WooProduct.fromJson(Map<String, Object?> json) {
    List<T> listOf<T>(String key, T Function(Map<String, Object?>) read) {
      final Object? value = json[key];
      if (value is! List) return <T>[];
      return value
          .whereType<Map<String, Object?>>()
          .map(read)
          .toList(growable: false);
    }

    return WooProduct(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      permalink: json['permalink'] as String? ?? '',
      type: WooProductType.parse(json['type']),
      status: json['status'] as String? ?? '',
      description: json['description'] as String? ?? '',
      shortDescription: json['short_description'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      price: WooPrice(json['price'] as String? ?? ''),
      regularPrice: WooPrice(json['regular_price'] as String? ?? ''),
      salePrice: WooPrice(json['sale_price'] as String? ?? ''),
      onSale: json['on_sale'] as bool? ?? false,
      stockStatus: WooStockStatus.parse(json['stock_status']),
      stockQuantity: (json['stock_quantity'] as num?)?.toInt(),
      manageStock: json['manage_stock'] == true,
      categories: listOf('categories', WooTerm.fromJson),
      tags: listOf('tags', WooTerm.fromJson),
      images: listOf('images', WooImage.fromJson),
      variations: <int>[
        for (final Object? v
            in (json['variations'] as List<Object?>? ?? const <Object?>[]))
          if (v is num) v.toInt(),
      ],
      averageRating:
          double.tryParse(json['average_rating'] as String? ?? '') ?? 0,
      ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
      dateCreated: DateTime.tryParse(json['date_created'] as String? ?? ''),
      dateModified: DateTime.tryParse(json['date_modified'] as String? ?? ''),
      raw: json,
    );
  }

  /// The product id.
  final int id;

  /// Its name.
  final String name;

  /// Its URL slug.
  final String slug;

  /// The full link to it on the store.
  final String permalink;

  /// Simple, variable, grouped or external.
  final WooProductType type;

  /// `publish`, `draft`, `private`, and so on.
  final String status;

  /// The long description, as HTML.
  final String description;

  /// The short description, as HTML.
  final String shortDescription;

  /// The stock keeping unit, often empty.
  final String sku;

  /// The price actually charged.
  final WooPrice price;

  /// The price before any sale.
  final WooPrice regularPrice;

  /// The sale price, unset when not on sale.
  final WooPrice salePrice;

  /// Whether a sale is running.
  final bool onSale;

  /// Whether it can be bought.
  final WooStockStatus stockStatus;

  /// How many are left, or null when the store does not track quantity.
  ///
  /// Null and zero mean different things: null is "not counted", zero is
  /// "counted, and there are none".
  final int? stockQuantity;

  /// Whether the store counts this product's stock.
  final bool manageStock;

  /// Categories it belongs to.
  final List<WooTerm> categories;

  /// Tags on it.
  final List<WooTerm> tags;

  /// Its images, the first being the featured one.
  final List<WooImage> images;

  /// Ids of this product's variations, for a variable product.
  final List<int> variations;

  /// Average review score, zero when unrated.
  final double averageRating;

  /// How many reviews it has.
  final int ratingCount;

  /// When it was created.
  final DateTime? dateCreated;

  /// When it last changed.
  final DateTime? dateModified;

  /// Everything WooCommerce sent, untouched.
  final Map<String, Object?> raw;

  /// Whether the store will currently sell it.
  bool get isPurchasable =>
      status == 'publish' && stockStatus != WooStockStatus.outOfStock;

  /// The featured image, or null when the product has none.
  WooImage? get featuredImage => images.isEmpty ? null : images.first;

  @override
  String toString() => 'WooProduct($id, $name)';
}
