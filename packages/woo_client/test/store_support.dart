import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A fake Store API. Records requests, replays scripted responses, and issues
/// a `Cart-Token` the way a real store does.
class FakeStoreApi {
  /// Answers every request with what [_reply] returns.
  FakeStoreApi(this._reply, {this.issueToken = 'cart-token-1'});

  final Object? Function(http.Request request) _reply;

  /// The token to hand back on cart routes, or null to hand back none.
  final String? issueToken;

  /// Every request made, in order.
  final List<http.Request> calls = <http.Request>[];

  /// The last request's URI.
  Uri get lastUri => calls.last.url;

  /// The last request's decoded body.
  Map<String, Object?> get lastBody =>
      jsonDecode(calls.last.body) as Map<String, Object?>;

  /// The `Cart-Token` header sent on the last request, if any.
  String? get lastSentToken => calls.last.headers['Cart-Token'];

  /// The client to hand to `WooStore(httpClient: ...)`.
  http.Client get client => MockClient((http.Request request) async {
    calls.add(request);
    final Object? body = _reply(request);
    if (body is http.Response) return body;
    return http.Response(
      jsonEncode(body),
      200,
      headers: <String, String>{
        'content-type': 'application/json; charset=utf-8',
        if (issueToken case final String t) 'Cart-Token': t,
      },
    );
  });
}

/// An error body shaped the way WooCommerce shapes them.
http.Response wooError(
  int status,
  String code,
  String message, {
  Map<String, Object?>? data,
  Map<String, String> headers = const <String, String>{},
}) => http.Response(
  jsonEncode(<String, Object?>{
    'code': code,
    'message': message,
    'data': <String, Object?>{'status': status, ...?data},
  }),
  status,
  headers: <String, String>{
    'content-type': 'application/json; charset=utf-8',
    ...headers,
  },
);

/// A cart as the Store API actually sends one, trimmed of the longest tails.
Map<String, Object?> cartJson({
  int quantity = 1,
  String totalPrice = '8256',
  List<Object?>? coupons,
  List<Object?>? errors,
  bool needsShipping = true,
}) => <String, Object?>{
  'items': <Object?>[
    <String, Object?>{
      'key': 'a5771bce93e200c36f7cd9dfd0e5deaa',
      'id': 38,
      'quantity': quantity,
      'quantity_limits': <String, Object?>{
        'minimum': 1,
        'maximum': 12,
        'multiple_of': 2,
        'editable': true,
      },
      'name': 'Beanie with Logo',
      'short_description': '<p>A simple product.</p>',
      'sku': 'Woo-beanie-logo',
      'low_stock_remaining': null,
      'backorders_allowed': false,
      'sold_individually': false,
      'permalink': 'https://shop.test/product/beanie-with-logo/',
      'images': <Object?>[
        <String, Object?>{
          'id': 61,
          'src': 'https://shop.test/beanie.jpg',
          'thumbnail': 'https://shop.test/beanie-450x450.jpg',
          'alt': '',
        },
      ],
      'variation': <Object?>[
        <String, Object?>{'attribute': 'pa_colour', 'value': 'blue'},
      ],
      'prices': <String, Object?>{
        'price': '1800',
        'regular_price': '2000',
        'sale_price': '1800',
        'price_range': null,
        ..._usd,
      },
      'totals': <String, Object?>{
        'line_subtotal': '1800',
        'line_subtotal_tax': '180',
        'line_total': '1530',
        'line_total_tax': '153',
        ..._usd,
      },
    },
  ],
  'coupons': coupons ?? <Object?>[],
  'fees': <Object?>[],
  'totals': <String, Object?>{
    'total_items': '7300',
    'total_items_tax': '730',
    'total_fees': '0',
    'total_fees_tax': '0',
    'total_discount': '1095',
    'total_discount_tax': '110',
    'total_shipping': '1300',
    'total_shipping_tax': '130',
    'total_price': totalPrice,
    'total_tax': '751',
    'tax_lines': <Object?>[],
    ..._usd,
  },
  'shipping_address': <String, Object?>{
    'first_name': 'John',
    'last_name': 'Doe',
    'address_1': 'Hello street',
    'city': 'beverly hills',
    'state': 'CA',
    'postcode': '90211',
    'country': 'US',
  },
  'billing_address': <String, Object?>{
    'first_name': 'John',
    'last_name': 'Doe',
    'address_1': 'Hello street',
    'city': 'beverly hills',
    'state': 'CA',
    'postcode': '90211',
    'country': 'US',
    'email': 'john@example.com',
    'phone': '123456778',
  },
  'needs_payment': true,
  'needs_shipping': needsShipping,
  'has_calculated_shipping': true,
  'shipping_rates': <Object?>[
    <String, Object?>{
      'package_id': 0,
      'name': 'Shipment 1',
      'destination': <String, Object?>{
        'city': 'beverly hills',
        'country': 'US',
      },
      'items': <Object?>[
        <String, Object?>{'key': 'a5771bce', 'name': 'Beanie with Logo'},
      ],
      'shipping_rates': <Object?>[
        <String, Object?>{
          'rate_id': 'flat_rate:10',
          'name': 'Flat rate',
          'price': '1300',
          'taxes': '130',
          'method_id': 'flat_rate',
          'instance_id': 10,
          'selected': true,
          ..._usd,
        },
        <String, Object?>{
          'rate_id': 'free_shipping:11',
          'name': 'Free shipping',
          'price': '0',
          'taxes': '0',
          'method_id': 'free_shipping',
          'instance_id': 11,
          'selected': false,
          ..._usd,
        },
      ],
    },
  ],
  'items_count': quantity,
  'items_weight': 0,
  'cross_sells': <Object?>[],
  'errors': errors ?? <Object?>[],
  'payment_methods': <Object?>['cod', 'bacs'],
  'extensions': <String, Object?>{},
};

/// A checkout as the Store API sends one.
Map<String, Object?> checkoutJson({
  int orderId = 146,
  String status = 'checkout-draft',
  String paymentStatus = '',
  String redirectUrl = '',
}) => <String, Object?>{
  'order_id': orderId,
  'status': status,
  'order_key': 'wc_order_VPffqyvgWVqWL',
  'customer_note': '',
  'customer_id': 0,
  'billing_address': <String, Object?>{
    'first_name': 'Ada',
    'last_name': 'Lovelace',
    'country': 'GB',
    'email': 'ada@example.com',
  },
  'shipping_address': <String, Object?>{
    'first_name': 'Ada',
    'last_name': 'Lovelace',
    'country': 'GB',
  },
  'payment_method': 'cod',
  'payment_result': <String, Object?>{
    'payment_status': paymentStatus,
    'payment_details': <Object?>[],
    'redirect_url': redirectUrl,
  },
};

/// A public product as the Store API sends one.
Map<String, Object?> storeProductJson({
  int id = 34,
  String type = 'simple',
  Map<String, Object?>? priceRange,
}) => <String, Object?>{
  'id': id,
  'name': 'WordPress Pennant',
  'slug': 'wordpress-pennant',
  'type': type,
  'parent': 0,
  'permalink': 'https://shop.test/product/wordpress-pennant/',
  'sku': 'wp-pennant',
  'short_description': '<p>A pennant.</p>',
  'description': '<p>A longer description.</p>',
  'on_sale': false,
  'prices': <String, Object?>{
    'price': '1105',
    'regular_price': '1105',
    'sale_price': '1105',
    'price_range': priceRange,
    ..._gbp,
  },
  'price_html': r'<span>£11.05</span>',
  'average_rating': '4.5',
  'review_count': 12,
  'images': <Object?>[
    <String, Object?>{'id': 57, 'src': 'https://shop.test/pennant.jpg'},
  ],
  'categories': <Object?>[
    <String, Object?>{'id': 21, 'name': 'Flags', 'slug': 'flags'},
  ],
  'tags': <Object?>[],
  'attributes': <Object?>[
    <String, Object?>{
      'id': 3,
      'name': 'Colour',
      'taxonomy': 'pa_colour',
      'has_variations': true,
      'terms': <Object?>[
        <String, Object?>{'id': 9, 'name': 'Blue', 'slug': 'blue'},
        <String, Object?>{'id': 10, 'name': 'Red', 'slug': 'red'},
      ],
    },
  ],
  'variations': type == 'variable'
      ? <Object?>[
          <String, Object?>{
            'id': 35,
            'attributes': <Object?>[
              <String, Object?>{'name': 'pa_colour', 'value': 'blue'},
            ],
          },
          <String, Object?>{
            'id': 36,
            'attributes': <Object?>[
              <String, Object?>{'name': 'pa_colour', 'value': 'red'},
            ],
          },
        ]
      : <Object?>[],
  'has_options': type == 'variable',
  'is_purchasable': true,
  'is_in_stock': true,
  'is_password_protected': false,
  'low_stock_remaining': null,
  'add_to_cart': <String, Object?>{'text': 'Add to cart'},
  // Fields a live store sends that the docs' example omits, captured from
  // woocommerce.com's own Store API.
  'variation': '',
  'grouped_products': <Object?>[],
  'stock_availability': <String, Object?>{
    'text': 'Only 2 left in stock',
    'class': 'low-stock',
  },
  'weight': '',
  'formatted_weight': 'N/A',
  'dimensions': <String, Object?>{'length': '20', 'width': '15', 'height': '5'},
  'formatted_dimensions': '20 × 15 × 5 cm',
  'extensions': <String, Object?>{},
};

const Map<String, Object?> _usd = <String, Object?>{
  'currency_code': 'USD',
  'currency_symbol': r'$',
  'currency_minor_unit': 2,
  'currency_decimal_separator': '.',
  'currency_thousand_separator': ',',
  'currency_prefix': r'$',
  'currency_suffix': '',
};

const Map<String, Object?> _gbp = <String, Object?>{
  'currency_code': 'GBP',
  'currency_symbol': '£',
  'currency_minor_unit': 2,
  'currency_decimal_separator': '.',
  'currency_thousand_separator': ',',
  'currency_prefix': '£',
  'currency_suffix': '',
};
