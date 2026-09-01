import 'dart:convert';
import 'dart:io';

import 'package:woo_client/woo_client.dart';

void main() {
  final Object? decoded = jsonDecode(
    File(
      '/private/tmp/claude-501/-Users-devshakib-Projects/422a40fb-c07d-49d0-9ec0-e5bf2bdb790d/scratchpad/real.json',
    ).readAsStringSync(),
  );
  final List<Object?> list = decoded! as List<Object?>;
  for (final Object? raw in list) {
    final StoreProduct p = StoreProduct.fromJson(raw! as Map<String, Object?>);
    print('id            ${p.id}');
    print('name          ${p.name}');
    print('type          ${p.type}');
    print('price         ${p.price}');
    print('regular       ${p.regularPrice}');
    print('onSale        ${p.onSale}');
    print('inStock       ${p.isInStock}  purchasable ${p.isPurchasable}');
    print('rating        ${p.averageRating} (${p.reviewCount})');
    print('categories    ${p.categories}');
    print('image         ${p.image?.src}');
    print('addToCart     "${p.addToCartText}"');
    print('needsOptions  ${p.needsOptions}');
    print('priceRange    ${p.priceRange}');
    print(
      'unmodelled    ${p.raw.keys.where((String k) => !const {'id', 'name', 'slug', 'type', 'parent', 'permalink', 'sku', 'description', 'short_description', 'price_html', 'prices', 'on_sale', 'is_purchasable', 'is_in_stock', 'is_on_backorder', 'is_password_protected', 'has_options', 'sold_individually', 'low_stock_remaining', 'average_rating', 'review_count', 'images', 'categories', 'tags', 'brands', 'attributes', 'variations', 'add_to_cart'}.contains(k)).toList()}',
    );
  }
}
