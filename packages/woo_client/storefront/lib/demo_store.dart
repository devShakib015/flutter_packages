import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A WooCommerce store that lives in this app.
///
/// `WooStore` talks to any `http.Client`, so the demo can run with no network,
/// no keys, and nobody's real shop behind it. Everything above this file — the
/// parsing, the minor-unit prices, the cart arithmetic, the shipping rates —
/// is the real package doing real work on real Store API payloads.
///
/// Point the app at a live store instead with:
///
///     flutter run -d chrome --dart-define=STORE=https://your-store.com
http.Client demoStoreClient() {
  final _Cart cart = _Cart();

  return MockClient((http.Request request) async {
    final String path = request.url.path;
    final Map<String, Object?> body = request.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(request.body) as Map<String, Object?>;

    Object? payload;
    if (path.endsWith('/products')) {
      payload = _catalogue;
    } else if (path.endsWith('/cart/add-item')) {
      cart.add(body['id']! as int, body['quantity'] as int? ?? 1);
      payload = cart.toJson();
    } else if (path.endsWith('/cart/update-item')) {
      cart.setQuantity(body['key']! as String, body['quantity']! as int);
      payload = cart.toJson();
    } else if (path.endsWith('/cart/remove-item')) {
      cart.remove(body['key']! as String);
      payload = cart.toJson();
    } else if (path.endsWith('/cart/apply-coupon')) {
      cart.coupon = '${body['code']}';
      payload = cart.toJson();
    } else if (path.endsWith('/cart/remove-coupon')) {
      cart.coupon = null;
      payload = cart.toJson();
    } else if (path.endsWith('/cart/select-shipping-rate')) {
      cart.rate = '${body['rate_id']}';
      payload = cart.toJson();
    } else if (path.endsWith('/cart/update-customer')) {
      cart.hasAddress = true;
      payload = cart.toJson();
    } else if (path.endsWith('/cart')) {
      payload = cart.toJson();
    } else {
      payload = const <String, Object?>{};
    }

    return http.Response(
      jsonEncode(payload),
      200,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
        'Cart-Token': 'demo-cart-token',
        'x-wp-total': '${_catalogue.length}',
        'x-wp-totalpages': '1',
      },
    );
  });
}

/// Sterling, with the formatting a real store sends alongside every amount.
const Map<String, Object?> _gbp = <String, Object?>{
  'currency_code': 'GBP',
  'currency_symbol': '£',
  'currency_minor_unit': 2,
  'currency_decimal_separator': '.',
  'currency_thousand_separator': ',',
  'currency_prefix': '£',
  'currency_suffix': '',
};

class _Product {
  const _Product(
    this.id,
    this.name,
    this.price,
    this.was,
    this.stock,
    this.tint,
  );
  final int id;
  final String name;
  final int price;
  final int? was;
  final String stock;
  final int tint;
}

const List<_Product> _products = <_Product>[
  _Product(38, 'Leather Satchel', 12900, null, 'In stock', 0xFF8B5E3C),
  _Product(
    41,
    'Canvas Weekender',
    8450,
    9900,
    'Only 2 left in stock',
    0xFF3F6C51,
  ),
  _Product(47, 'Card Holder', 2400, null, 'In stock', 0xFF9A3B3B),
  _Product(52, 'Belt, Chestnut', 5500, null, 'In stock', 0xFF6B4F2A),
  _Product(58, 'Passport Sleeve', 3200, 3900, 'In stock', 0xFF2F4858),
  _Product(63, 'Key Fob', 1450, null, 'Out of stock', 0xFF57534E),
  _Product(69, 'Wash Bag', 6900, null, 'In stock', 0xFF4C5C96),
  _Product(74, 'Luggage Tag', 1900, 2400, 'Only 3 left in stock', 0xFF7A5230),
];

/// Colour is baked into the payload so the demo needs no image files, and the
/// app can render a placeholder tile instead of loading anything.
List<Map<String, Object?>> get _catalogue => <Map<String, Object?>>[
  for (final _Product p in _products)
    <String, Object?>{
      'id': p.id,
      'name': p.name,
      'slug': p.name.toLowerCase().replaceAll(RegExp('[^a-z]+'), '-'),
      'type': 'simple',
      'parent': 0,
      'permalink': 'https://demo.test/product/${p.id}',
      'sku': 'DEMO-${p.id}',
      'short_description': '<p>Full-grain leather.</p>',
      'description': '<p>Full-grain leather.</p>',
      'on_sale': p.was != null,
      'prices': <String, Object?>{
        'price': '${p.price}',
        'regular_price': '${p.was ?? p.price}',
        'sale_price': '${p.price}',
        'price_range': null,
        ..._gbp,
      },
      'average_rating': '4.6',
      'review_count': 18,
      'images': <Object?>[],
      'categories': <Object?>[
        <String, Object?>{'id': 21, 'name': 'Leather', 'slug': 'leather'},
      ],
      'tags': <Object?>[],
      'attributes': <Object?>[],
      'variations': <Object?>[],
      'has_options': false,
      'is_purchasable': p.stock != 'Out of stock',
      'is_in_stock': p.stock != 'Out of stock',
      'is_on_backorder': false,
      'is_password_protected': false,
      'sold_individually': false,
      'low_stock_remaining': p.stock.startsWith('Only') ? 2 : null,
      'stock_availability': <String, Object?>{
        'text': p.stock,
        'class': p.stock == 'Out of stock'
            ? 'out-of-stock'
            : p.stock.startsWith('Only')
            ? 'low-stock'
            : 'in-stock',
      },
      'weight': '',
      'formatted_weight': 'N/A',
      'dimensions': <String, Object?>{'length': '', 'width': '', 'height': ''},
      'formatted_dimensions': 'N/A',
      'grouped_products': <Object?>[],
      'variation': '',
      'add_to_cart': <String, Object?>{'text': 'Add to cart'},
      'extensions': <String, Object?>{},
    },
];

/// The bookkeeping a real store would do, so the totals in the demo add up.
class _Cart {
  final Map<String, int> _lines = <String, int>{};

  String? coupon;
  String? rate;
  bool hasAddress = false;

  static String _keyFor(int id) => 'line-$id';

  void add(int id, int quantity) => _lines.update(
    _keyFor(id),
    (int q) => q + quantity,
    ifAbsent: () => quantity,
  );

  void setQuantity(String key, int quantity) {
    if (quantity <= 0) {
      _lines.remove(key);
    } else {
      _lines[key] = quantity;
    }
  }

  void remove(String key) => _lines.remove(key);

  _Product _productFor(String key) =>
      _products.firstWhere((_Product p) => _keyFor(p.id) == key);

  int get _itemsTotal => _lines.entries.fold(
    0,
    (int sum, MapEntry<String, int> e) =>
        sum + _productFor(e.key).price * e.value,
  );

  int get _discount => coupon == null ? 0 : (_itemsTotal * 0.1).round();

  int get _shipping => _lines.isEmpty
      ? 0
      : rate == 'free_shipping:11'
      ? 0
      : 495;

  Map<String, Object?> toJson() {
    final int items = _itemsTotal;
    final int discount = _discount;
    final int shipping = _shipping;
    final int tax = ((items - discount) * 0.2).round();

    return <String, Object?>{
      'items': <Object?>[
        for (final MapEntry<String, int> e in _lines.entries)
          _line(_productFor(e.key), e.key, e.value),
      ],
      'coupons': <Object?>[
        if (coupon case final String code)
          <String, Object?>{
            'code': code,
            'discount_type': 'percent',
            'totals': <String, Object?>{
              'total_discount': '$discount',
              'total_discount_tax': '0',
              ..._gbp,
            },
          },
      ],
      'fees': <Object?>[],
      'totals': <String, Object?>{
        'total_items': '$items',
        'total_items_tax': '0',
        'total_fees': '0',
        'total_fees_tax': '0',
        'total_discount': '$discount',
        'total_discount_tax': '0',
        'total_shipping': '$shipping',
        'total_shipping_tax': '0',
        'total_tax': '$tax',
        'total_price': '${items - discount + shipping + tax}',
        'tax_lines': <Object?>[],
        ..._gbp,
      },
      'billing_address': const <String, Object?>{},
      'shipping_address': hasAddress
          ? const <String, Object?>{
              'city': 'London',
              'postcode': 'N1 7GU',
              'country': 'GB',
            }
          : const <String, Object?>{},
      'needs_payment': true,
      'needs_shipping': _lines.isNotEmpty,
      'has_calculated_shipping': hasAddress,
      'shipping_rates': hasAddress && _lines.isNotEmpty
          ? <Object?>[
              <String, Object?>{
                'package_id': 0,
                'name': 'Shipment 1',
                'destination': const <String, Object?>{'country': 'GB'},
                'items': <Object?>[],
                'shipping_rates': <Object?>[
                  _rate(
                    'flat_rate:1',
                    'Royal Mail Tracked 48',
                    495,
                    '2 to 3 days',
                    rate != 'free_shipping:11',
                  ),
                  _rate(
                    'free_shipping:11',
                    'Free over £100',
                    0,
                    '3 to 5 days',
                    rate == 'free_shipping:11',
                  ),
                ],
              },
            ]
          : <Object?>[],
      'items_count': _lines.values.fold<int>(0, (int a, int b) => a + b),
      'items_weight': 0,
      'cross_sells': <Object?>[],
      'errors': <Object?>[],
      'payment_methods': <Object?>['stripe', 'cod'],
      'extensions': const <String, Object?>{},
    };
  }

  static Map<String, Object?> _rate(
    String id,
    String name,
    int price,
    String when,
    bool selected,
  ) => <String, Object?>{
    'rate_id': id,
    'name': name,
    'description': '',
    'delivery_time': when,
    'price': '$price',
    'taxes': '0',
    'method_id': id.split(':').first,
    'instance_id': 1,
    'selected': selected,
    ..._gbp,
  };

  static Map<String, Object?> _line(_Product p, String key, int quantity) =>
      <String, Object?>{
        'key': key,
        'id': p.id,
        'quantity': quantity,
        'quantity_limits': <String, Object?>{
          'minimum': 1,
          'maximum': 10,
          'multiple_of': 1,
          'editable': true,
        },
        'name': p.name,
        'short_description': '',
        'sku': 'DEMO-${p.id}',
        'low_stock_remaining': null,
        'backorders_allowed': false,
        'sold_individually': false,
        'permalink': '',
        'images': <Object?>[],
        'variation': <Object?>[],
        'prices': <String, Object?>{
          'price': '${p.price}',
          'regular_price': '${p.was ?? p.price}',
          'sale_price': '${p.price}',
          'price_range': null,
          ..._gbp,
        },
        'totals': <String, Object?>{
          'line_subtotal': '${p.price * quantity}',
          'line_subtotal_tax': '0',
          'line_total': '${p.price * quantity}',
          'line_total_tax': '0',
          ..._gbp,
        },
      };
}

/// The colour to draw for a product, since the demo ships no images.
int tintFor(int productId) =>
    _products.firstWhere((_Product p) => p.id == productId).tint;
