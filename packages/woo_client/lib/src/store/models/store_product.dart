import '../../json.dart';
import '../money.dart';
import 'cart.dart';

/// A category, tag, or brand attached to a product.
class StoreTerm {
  /// Creates a term.
  const StoreTerm({
    this.id = 0,
    this.name = '',
    this.slug = '',
    this.link = '',
  });

  /// Reads the Store API's representation.
  factory StoreTerm.fromJson(Map<String, Object?> json) => StoreTerm(
    id: readInt(json['id'], orElse: 0),
    name: readString(json['name']),
    slug: readString(json['slug']),
    link: readString(json['link']),
  );

  /// Term id.
  final int id;

  /// Display name.
  final String name;

  /// URL slug.
  final String slug;

  /// Link to the archive page.
  final String link;

  @override
  String toString() => name;
}

/// One attribute of a product, with the values it can take.
class StoreAttribute {
  /// Creates an attribute.
  const StoreAttribute({
    this.id = 0,
    this.name = '',
    this.taxonomy = '',
    this.hasVariations = false,
    this.terms = const <StoreTerm>[],
  });

  /// Reads the Store API's representation.
  factory StoreAttribute.fromJson(Map<String, Object?> json) => StoreAttribute(
    id: readInt(json['id'], orElse: 0),
    name: readString(json['name']),
    taxonomy: readString(json['taxonomy']),
    hasVariations: readBool(json['has_variations']),
    terms: <StoreTerm>[
      for (final Map<String, Object?> t in readObjects(json['terms']))
        StoreTerm.fromJson(t),
    ],
  );

  /// Attribute id. Zero for a product-specific attribute.
  final int id;

  /// Display name, such as `Colour`.
  final String name;

  /// The taxonomy, such as `pa_colour`. Empty for product-specific ones.
  ///
  /// This is what to send as the attribute when adding a variation to the
  /// cart — see [StoreCartItem.variation]. Global attributes use the
  /// taxonomy, product-specific ones use the name.
  final String taxonomy;

  /// Whether choosing this attribute picks a variation.
  final bool hasVariations;

  /// The values on offer.
  final List<StoreTerm> terms;

  /// What to send as the `attribute` key when adding to the cart.
  String get wireName => taxonomy.isNotEmpty ? taxonomy : name;
}

/// A variation of a variable product, as listed on its parent.
class StoreVariation {
  /// Creates a variation reference.
  const StoreVariation({
    this.id = 0,
    this.attributes = const <String, String>{},
  });

  /// Reads the Store API's representation.
  factory StoreVariation.fromJson(Map<String, Object?> json) => StoreVariation(
    id: readInt(json['id'], orElse: 0),
    attributes: <String, String>{
      for (final Map<String, Object?> a in readObjects(json['attributes']))
        readString(a['name']): readString(a['value']),
    },
  );

  /// The variation's product id — this is what goes in `addItem`.
  final int id;

  /// The attribute values that select it.
  final Map<String, String> attributes;
}

/// A product's size, as the store records it.
class StoreDimensions {
  /// Creates dimensions.
  const StoreDimensions({this.length = '', this.width = '', this.height = ''});

  /// Reads the Store API's representation.
  factory StoreDimensions.fromJson(Map<String, Object?> json) =>
      StoreDimensions(
        length: readString(json['length']),
        width: readString(json['width']),
        height: readString(json['height']),
      );

  /// Length, in the store's unit.
  final String length;

  /// Width, in the store's unit.
  final String width;

  /// Height, in the store's unit.
  final String height;

  /// Whether the store records any of them.
  bool get isEmpty => length.isEmpty && width.isEmpty && height.isEmpty;
}

/// The range a variable product's price falls in.
class StorePriceRange {
  /// Creates a range.
  const StorePriceRange({required this.min, required this.max});

  /// The cheapest variation.
  final StoreMoney min;

  /// The dearest variation.
  final StoreMoney max;

  /// Whether every variation costs the same, so a range need not be shown.
  bool get isFlat => min == max;

  @override
  String toString() => isFlat ? '$min' : '$min – $max';
}

/// A product, as the public Store API describes it.
///
/// This is a different shape from `WooProduct`, which comes from the
/// authenticated admin API: prices here are minor units with formatting
/// attached, and nothing sensitive (cost, stock counts, private meta) is
/// present. Use this one for anything a shopper sees.
class StoreProduct {
  /// Creates a product.
  const StoreProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.regularPrice,
    required this.salePrice,
    required this.raw,
    this.slug = '',
    this.type = '',
    this.parent = 0,
    this.permalink = '',
    this.sku = '',
    this.description = '',
    this.shortDescription = '',
    this.priceHtml = '',
    this.priceRange,
    this.onSale = false,
    this.isPurchasable = false,
    this.isInStock = false,
    this.isOnBackorder = false,
    this.isPasswordProtected = false,
    this.hasOptions = false,
    this.soldIndividually = false,
    this.lowStockRemaining,
    this.averageRating = 0,
    this.reviewCount = 0,
    this.images = const <StoreImage>[],
    this.categories = const <StoreTerm>[],
    this.tags = const <StoreTerm>[],
    this.brands = const <StoreTerm>[],
    this.attributes = const <StoreAttribute>[],
    this.variations = const <StoreVariation>[],
    this.addToCartText = '',
    this.stockText = '',
    this.stockClass = '',
    this.weight = '',
    this.formattedWeight = '',
    this.dimensions = const StoreDimensions(),
    this.formattedDimensions = '',
    this.groupedProducts = const <int>[],
    this.variationDescription = '',
  });

  /// Reads the Store API's representation.
  factory StoreProduct.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> prices = readMap(json['prices']);
    final StoreCurrency currency = StoreCurrency.fromJson(prices);
    final Object? range = prices['price_range'];
    return StoreProduct(
      id: readInt(json['id'], orElse: 0),
      name: readString(json['name']),
      slug: readString(json['slug']),
      type: readString(json['type']),
      parent: readInt(json['parent'], orElse: 0),
      permalink: readString(json['permalink']),
      sku: readString(json['sku']),
      description: readString(json['description']),
      shortDescription: readString(json['short_description']),
      priceHtml: readString(json['price_html']),
      price: StoreMoney.read(prices, 'price', currency),
      regularPrice: StoreMoney.read(prices, 'regular_price', currency),
      salePrice: StoreMoney.read(prices, 'sale_price', currency),
      priceRange: range is Map<String, Object?>
          ? StorePriceRange(
              min: StoreMoney.read(range, 'min_amount', currency),
              max: StoreMoney.read(range, 'max_amount', currency),
            )
          : null,
      onSale: readBool(json['on_sale']),
      isPurchasable: readBool(json['is_purchasable']),
      isInStock: readBool(json['is_in_stock']),
      isOnBackorder: readBool(json['is_on_backorder']),
      isPasswordProtected: readBool(json['is_password_protected']),
      hasOptions: readBool(json['has_options']),
      soldIndividually: readBool(json['sold_individually']),
      lowStockRemaining: readIntOrNull(json['low_stock_remaining']),
      averageRating: readDouble(json['average_rating']),
      reviewCount: readInt(json['review_count'], orElse: 0),
      images: <StoreImage>[
        for (final Map<String, Object?> i in readObjects(json['images']))
          StoreImage.fromJson(i),
      ],
      categories: _terms(json['categories']),
      tags: _terms(json['tags']),
      brands: _terms(json['brands']),
      attributes: <StoreAttribute>[
        for (final Map<String, Object?> a in readObjects(json['attributes']))
          StoreAttribute.fromJson(a),
      ],
      variations: <StoreVariation>[
        for (final Map<String, Object?> v in readObjects(json['variations']))
          StoreVariation.fromJson(v),
      ],
      stockText: switch (json['stock_availability']) {
        final Map<String, Object?> a => readString(a['text']),
        _ => '',
      },
      stockClass: switch (json['stock_availability']) {
        final Map<String, Object?> a => readString(a['class']),
        _ => '',
      },
      weight: readString(json['weight']),
      formattedWeight: readString(json['formatted_weight']),
      dimensions: StoreDimensions.fromJson(readMap(json['dimensions'])),
      formattedDimensions: readString(json['formatted_dimensions']),
      groupedProducts: readInts(json['grouped_products']),
      variationDescription: readString(json['variation']),
      addToCartText: switch (json['add_to_cart']) {
        final Map<String, Object?> a => readString(a['text']),
        _ => '',
      },
      raw: json,
    );
  }

  static List<StoreTerm> _terms(Object? value) => <StoreTerm>[
    for (final Map<String, Object?> t in readObjects(value))
      StoreTerm.fromJson(t),
  ];

  /// Product id — what to pass to `cart.addItem` for a simple product.
  final int id;

  /// Display name.
  final String name;

  /// URL slug.
  final String slug;

  /// `simple`, `variable`, `grouped`, `external`, or a plugin's own.
  final String type;

  /// The parent product, for a variation. Zero otherwise.
  final int parent;

  /// Link to the product page on the store.
  final String permalink;

  /// Stock keeping unit.
  final String sku;

  /// Full description, as HTML. Empty while password-protected.
  final String description;

  /// Short description, as HTML. Empty while password-protected.
  final String shortDescription;

  /// The store's own rendered price, as HTML. Handy when a plugin prices
  /// things in a way the plain fields cannot express.
  final String priceHtml;

  /// What one costs now.
  final StoreMoney price;

  /// What one costs when not on sale.
  final StoreMoney regularPrice;

  /// The sale price. Equal to [regularPrice] when there is no sale.
  final StoreMoney salePrice;

  /// For a variable product, the span its variations cover.
  final StorePriceRange? priceRange;

  /// Whether it is discounted.
  final bool onSale;

  /// Whether it can be bought at all.
  final bool isPurchasable;

  /// Whether there is stock.
  final bool isInStock;

  /// Whether it can be ordered despite being out of stock.
  final bool isOnBackorder;

  /// Whether the store is hiding the descriptions behind a password.
  final bool isPasswordProtected;

  /// Whether the shopper must choose something before adding to the cart.
  final bool hasOptions;

  /// Whether only one may be bought at a time.
  final bool soldIndividually;

  /// How many are left, when the store is showing a low-stock warning.
  final int? lowStockRemaining;

  /// Average review score, 0 when unrated.
  final double averageRating;

  /// How many reviews.
  final int reviewCount;

  /// Product images.
  final List<StoreImage> images;

  /// Categories.
  final List<StoreTerm> categories;

  /// Tags.
  final List<StoreTerm> tags;

  /// Brands, when the store uses them.
  final List<StoreTerm> brands;

  /// Attributes and their possible values.
  final List<StoreAttribute> attributes;

  /// The variations, for a variable product.
  final List<StoreVariation> variations;

  /// The store's own wording for the button, such as `Add to cart` or
  /// `Select options`.
  final String addToCartText;

  /// The store's own stock line, already worded and translated — `In stock`,
  /// `Only 2 left in stock`, or empty when the store shows nothing.
  ///
  /// Worth preferring over composing your own from [isInStock] and
  /// [lowStockRemaining]: this one is in the shopper's language and follows
  /// the store's settings.
  final String stockText;

  /// A CSS class for [stockText], such as `in-stock` or `low-stock`. Useful as
  /// a key for choosing a colour.
  final String stockClass;

  /// Weight, in the store's unit.
  final String weight;

  /// Weight with its unit, as the store writes it — `1.2 kg`.
  ///
  /// Stores commonly send the literal string `N/A` here rather than an empty
  /// one, so check before putting it on screen.
  final String formattedWeight;

  /// Size, in the store's unit.
  final StoreDimensions dimensions;

  /// Size with its units, as the store writes it — `20 × 15 × 5 cm`.
  ///
  /// Like [formattedWeight], often the literal `N/A`.
  final String formattedDimensions;

  /// For a grouped product, the ids it contains.
  final List<int> groupedProducts;

  /// For a variation, the attributes as one line — `Colour: Blue, Size: L`.
  final String variationDescription;

  /// The whole product as the store sent it.
  final Map<String, Object?> raw;

  /// The first image, or null.
  StoreImage? get image => images.isEmpty ? null : images.first;

  /// Whether adding this to a cart needs a variation chosen first.
  bool get needsOptions => hasOptions || variations.isNotEmpty;

  /// The variation whose attributes match [chosen], or null when the
  /// combination is not one the store sells.
  ///
  /// Keys may be either spelling. WooCommerce is inconsistent here and it is
  /// worth knowing why: a variation's attributes come back keyed by the
  /// **display label** (`Colour`, via `wc_attribute_label`), while
  /// `StoreCartResource.addItem` requires the **taxonomy** (`pa_colour`).
  /// This accepts both and resolves between them using the product's own
  /// [attributes] list, which carries each pair. Values are term slugs.
  ///
  /// ```dart
  /// final variation = product.variationFor({'Colour': 'blue'});
  /// await store.cart.addItem(
  ///   id: variation!.id,
  ///   variation: product.cartAttributes({'Colour': 'blue'}),
  /// );
  /// ```
  StoreVariation? variationFor(Map<String, String> chosen) {
    if (chosen.isEmpty) return null;
    for (final StoreVariation v in variations) {
      if (v.attributes.length != chosen.length) continue;
      final bool matches = v.attributes.entries.every(
        (MapEntry<String, String> e) =>
            e.value.isEmpty || _chose(chosen, e.key) == e.value,
      );
      if (matches) return v;
    }
    return null;
  }

  /// What the caller chose for [key], under whichever spelling they used.
  ///
  /// Stores are not consistent: a variation is keyed by the display label on
  /// stock WooCommerce, but plugins and older versions key it by the `pa_`
  /// taxonomy. Accepting both means neither shape silently returns null.
  String? _chose(Map<String, String> chosen, String key) {
    if (chosen[key] case final String v) return v;
    for (final StoreAttribute a in attributes) {
      final bool isThis = a.name == key || a.taxonomy == key;
      if (!isThis) continue;
      if (chosen[a.name] case final String v) return v;
      if (a.taxonomy.isEmpty) continue;
      if (chosen[a.taxonomy] case final String v) return v;
    }
    return null;
  }

  /// Rewrites [chosen] into the keys `StoreCartResource.addItem` expects.
  ///
  /// Global attributes must be posted under their `pa_` taxonomy;
  /// product-specific ones under their name. Accepts either spelling in and
  /// always gives the right one out.
  Map<String, String> cartAttributes(Map<String, String> chosen) {
    final Map<String, String> out = <String, String>{};
    for (final MapEntry<String, String> e in _byLabel(chosen).entries) {
      final StoreAttribute? a = attributes
          .where((StoreAttribute x) => x.name == e.key)
          .firstOrNull;
      out[a?.wireName ?? e.key] = e.value;
    }
    return out;
  }

  /// Normalises a chosen map onto the labels variations are keyed by.
  Map<String, String> _byLabel(Map<String, String> chosen) {
    final Map<String, String> labelFor = <String, String>{
      for (final StoreAttribute a in attributes)
        if (a.taxonomy.isNotEmpty) a.taxonomy: a.name,
    };
    return <String, String>{
      for (final MapEntry<String, String> e in chosen.entries)
        labelFor[e.key] ?? e.key: e.value,
    };
  }

  @override
  String toString() => 'StoreProduct($id, $name, $price)';
}
