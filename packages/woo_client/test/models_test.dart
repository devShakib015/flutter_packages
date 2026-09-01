import 'package:test/test.dart';
import 'package:woo_client/woo_client.dart';

import 'support.dart';

void main() {
  group('prices', () {
    test('an unset price is not zero', () {
      // WooCommerce sends "" for no price. Parsing that to 0.0 would make an
      // unpriced variation indistinguishable from a free one.
      const WooPrice none = WooPrice('');
      expect(none.isSet, isFalse);
      expect(none.amount, isNull);
      expect(none.amountOrZero, 0);
      expect(none.toString(), '(no price)');
    });

    test('a set price keeps the store\'s own text', () {
      const WooPrice p = WooPrice('129.00');
      expect(p.isSet, isTrue);
      expect(p.raw, '129.00', reason: 'trailing zeros are the store\'s choice');
      expect(p.amount, 129.0);
    });

    test('nonsense parses to null rather than throwing', () {
      expect(const WooPrice('n/a').amount, isNull);
      expect(const WooPrice('n/a').amountOrZero, 0);
    });

    test('prices order by value', () {
      final List<WooPrice> prices = <WooPrice>[
        const WooPrice('20.00'),
        const WooPrice('3.50'),
        const WooPrice(''),
      ]..sort();
      expect(prices.map((WooPrice p) => p.raw), <String>['', '3.50', '20.00']);
    });
  });

  group('products', () {
    test('reads the fields a store actually sends', () {
      final WooProduct p = WooProduct.fromJson(productJson());
      expect(p.id, 799);
      expect(p.name, 'Leather Satchel');
      expect(p.sku, 'SATCHEL-01');
      expect(p.type, WooProductType.simple);
      expect(p.regularPrice.amount, 129.0);
      expect(p.stockStatus, WooStockStatus.inStock);
      expect(p.categories.single.name, 'Bags');
      expect(p.images.single.src, endsWith('satchel.jpg'));
      expect(p.averageRating, closeTo(4.67, 0.001));
      expect(p.dateCreated?.year, 2026);
    });

    test('a sale exposes both prices', () {
      final WooProduct p = WooProduct.fromJson(
        productJson(price: '129.00', salePrice: '99.00'),
      );
      expect(p.onSale, isTrue);
      expect(p.regularPrice.amount, 129.0);
      expect(p.salePrice.amount, 99.0);
      expect(p.price.amount, 99.0, reason: 'price is what is charged');
    });

    test('untracked stock is null, not zero', () {
      final WooProduct untracked = WooProduct.fromJson(
        productJson(stockQuantity: null),
      );
      final WooProduct soldOut = WooProduct.fromJson(
        productJson(stockQuantity: 0, stockStatus: 'outofstock'),
      );
      // "not counted" and "counted, none left" are different facts.
      expect(untracked.stockQuantity, isNull);
      expect(untracked.manageStock, isFalse);
      expect(soldOut.stockQuantity, 0);
      expect(soldOut.isPurchasable, isFalse);
    });

    test('a variable product lists its variation ids', () {
      final WooProduct p = WooProduct.fromJson(productJson(type: 'variable'));
      expect(p.type, WooProductType.variable);
      expect(p.variations, <int>[801, 802]);
    });

    test('an unfamiliar type degrades instead of throwing', () {
      final WooProduct p = WooProduct.fromJson(
        productJson(type: 'subscription'),
      );
      expect(p.type, WooProductType.unknown);
      // The original is still reachable, which is the point of keeping raw.
      expect(p.raw['type'], 'subscription');
    });

    test('an empty object parses to an empty product', () {
      final WooProduct p = WooProduct.fromJson(const <String, Object?>{});
      expect(p.id, 0);
      expect(p.name, isEmpty);
      expect(p.categories, isEmpty);
      expect(p.featuredImage, isNull);
    });

    test('raw keeps what the typed fields do not model', () {
      final WooProduct p = WooProduct.fromJson(<String, Object?>{
        ...productJson(),
        'some_plugin_field': <String, Object?>{'x': 1},
      });
      expect((p.raw['some_plugin_field']! as Map<String, Object?>)['x'], 1);
    });
  });

  group('orders', () {
    test('reads the order and its lines', () {
      final WooOrder o = WooOrder.fromJson(orderJson());
      expect(o.id, 5120);
      expect(o.status, WooOrderStatus.processing);
      expect(o.currency, 'GBP');
      expect(o.total.amount, 148.0);
      expect(o.lineItems.single.productId, 799);
      expect(o.itemCount, 1);
      expect(o.billing.email, 'ada@example.com');
      expect(o.billing.fullName, 'Ada Lovelace');
      expect(o.shipping.city, 'London');
      expect(o.isPaid, isTrue);
      expect(o.isGuest, isFalse);
    });

    test('computes a subtotal WooCommerce does not send', () {
      final Map<String, Object?> json = orderJson();
      (json['line_items']! as List<Object?>).add(<String, Object?>{
        'id': 2,
        'product_id': 801,
        'quantity': 2,
        'subtotal': '40.00',
        'total': '40.00',
      });
      final WooOrder o = WooOrder.fromJson(json);
      // The order object carries no subtotal; only the lines do.
      expect(o.subtotal.amount, 169.0);
      expect(o.itemCount, 3);
    });

    test('an unpaid guest order reads as one', () {
      final WooOrder o = WooOrder.fromJson(
        orderJson(status: 'pending', customerId: 0, datePaid: null),
      );
      expect(o.isPaid, isFalse);
      expect(o.isGuest, isTrue);
      expect(o.status, WooOrderStatus.pending);
    });

    test('a plugin status degrades but is still readable', () {
      final WooOrder o = WooOrder.fromJson(
        orderJson(status: 'awaiting-pickup'),
      );
      expect(o.status, WooOrderStatus.unknown);
      expect(o.raw['status'], 'awaiting-pickup');
    });

    test('status round-trips through the wire name', () {
      // on-hold and checkout-draft are hyphenated; the enum names are not.
      for (final WooOrderStatus s in WooOrderStatus.values) {
        if (s == WooOrderStatus.unknown) continue;
        expect(WooOrderStatus.parse(s.wireName), s, reason: s.name);
      }
    });

    test('a line for ordering sends only product and quantity', () {
      final WooLineItem line = WooLineItem.order(productId: 799, quantity: 2);
      expect(line.toJson(), <String, Object?>{
        'product_id': 799,
        'quantity': 2,
      });
      // No price: the store decides what things cost.
      expect(line.toJson().containsKey('total'), isFalse);
    });

    test('a variation line carries the variation id', () {
      final WooLineItem line = WooLineItem.order(
        productId: 799,
        quantity: 1,
        variationId: 801,
      );
      expect(line.toJson()['variation_id'], 801);
    });

    test('an address round-trips to the wire form', () {
      const WooAddress a = WooAddress(
        firstName: 'Ada',
        lastName: 'Lovelace',
        address1: '12 Analytical Way',
        city: 'London',
        country: 'GB',
      );
      final Map<String, Object?> json = a.toJson();
      expect(json['first_name'], 'Ada');
      expect(json['address_1'], '12 Analytical Way');
      // Empty optional fields are omitted rather than sent blank.
      expect(json.containsKey('email'), isFalse);
      expect(WooAddress.fromJson(json).fullName, 'Ada Lovelace');
    });
  });

  group('coupons', () {
    Map<String, Object?> couponJson({
      String? expires,
      int? limit,
      int used = 0,
    }) => <String, Object?>{
      'id': 12,
      'code': 'save10',
      'amount': '10.00',
      'discount_type': 'percent',
      'description': 'Ten percent off',
      'date_expires': expires,
      'usage_count': used,
      'usage_limit': limit,
      'minimum_amount': '50.00',
      'maximum_amount': '',
      'free_shipping': false,
      'product_ids': <Object?>[799],
    };

    test('reads the discount', () {
      final WooCoupon c = WooCoupon.fromJson(couponJson());
      expect(c.code, 'save10');
      expect(c.discountType, WooDiscountType.percent);
      expect(c.amount.amount, 10.0);
      expect(c.minimumAmount.amount, 50.0);
      expect(c.maximumAmount.isSet, isFalse);
      expect(c.productIds, <int>[799]);
    });

    test('an expired coupon says so', () {
      final WooCoupon c = WooCoupon.fromJson(
        couponJson(expires: '2020-01-01T00:00:00'),
      );
      expect(c.isExpired, isTrue);
      expect(c.looksUsable, isFalse);
    });

    test('a used-up coupon says so, separately from expiry', () {
      final WooCoupon c = WooCoupon.fromJson(couponJson(limit: 5, used: 5));
      expect(c.isExpired, isFalse);
      expect(c.isUsedUp, isTrue);
      expect(c.looksUsable, isFalse);
    });

    test('no limit means never used up', () {
      final WooCoupon c = WooCoupon.fromJson(couponJson(used: 9999));
      expect(c.isUsedUp, isFalse);
      expect(c.looksUsable, isTrue);
    });
  });

  group('customers', () {
    test('falls back through name, username, then email', () {
      WooCustomer make(Map<String, Object?> extra) => WooCustomer.fromJson(
        <String, Object?>{'id': 33, 'email': 'ada@example.com', ...extra},
      );
      expect(
        make(<String, Object?>{'first_name': 'Ada', 'last_name': 'Lovelace'})
            .displayName,
        'Ada Lovelace',
      );
      expect(make(<String, Object?>{'username': 'ada'}).displayName, 'ada');
      expect(make(<String, Object?>{}).displayName, 'ada@example.com');
    });

    test('counts absent on a single read stay null, not zero', () {
      final WooCustomer c = WooCustomer.fromJson(<String, Object?>{
        'id': 33,
        'email': 'ada@example.com',
      });
      // The list endpoint sends orders_count; some single reads do not.
      expect(c.ordersCount, isNull);
      expect(c.totalSpent, isNull);
    });
  });
}
