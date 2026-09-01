import 'package:test/test.dart';
import 'package:woo_client/woo_client.dart';

import 'store_support.dart';
import 'support.dart';

void main() {
  // WordPress is not strict about JSON types, and plugins are less strict
  // still. A hard cast turns one odd field into a lost response.
  group('a store that sends the wrong type does not lose the response', () {
    test('booleans written the several ways WordPress writes them', () {
      bool onSale(Object? v) =>
          WooProduct.fromJson(<String, Object?>{'on_sale': v}).onSale;

      expect(onSale(true), isTrue);
      expect(onSale('yes'), isTrue);
      expect(onSale('1'), isTrue);
      expect(onSale(1), isTrue);
      expect(onSale(false), isFalse);
      expect(onSale('no'), isFalse);
      expect(onSale(''), isFalse);
      expect(onSale(0), isFalse);
      // Something nobody anticipated: fall back, do not throw.
      expect(onSale(<String, Object?>{}), isFalse);
    });

    test('a boolean whose sensible default is true keeps it', () {
      final WooTaxRate t = WooTaxRate.fromJson(const <String, Object?>{
        'id': 1,
        'shipping': <String, Object?>{'unexpected': true},
      });
      // This crashed the whole tax-rate parse before the readers coerced.
      expect(t.shipping, isTrue);
      expect(t.id, 1);
    });

    test('ids that arrive as strings', () {
      expect(WooProduct.fromJson(const <String, Object?>{'id': '799'}).id, 799);
      expect(
        StoreCartItem.fromJson(const <String, Object?>{
          'id': '38',
          'quantity': '2',
        }).quantity,
        2,
      );
    });

    test('a number that arrives as a float string', () {
      expect(
        WooProduct.fromJson(const <String, Object?>{'average_rating': '4.67'})
            .averageRating,
        closeTo(4.67, 0.001),
      );
      expect(
        WooTaxRate.fromJson(const <String, Object?>{'rate': '20.0000'}).rate,
        20.0,
      );
    });

    test('a list field that arrives as an object', () {
      // PHP's json_encode turns a non-sequential array into an object, so a
      // field that is a list on one store is a map on another.
      final WooProduct p = WooProduct.fromJson(const <String, Object?>{
        'categories': <String, Object?>{
          '0': <String, Object?>{'id': 21, 'name': 'Bags'},
          '2': <String, Object?>{'id': 22, 'name': 'Belts'},
        },
      });
      expect(p.categories.map((WooTerm t) => t.name), <String>[
        'Bags',
        'Belts',
      ]);
    });

    test('an object field that arrives as an empty list', () {
      // PHP sends [] for an empty associative array.
      final StoreCart cart = StoreCart.fromJson(const <String, Object?>{
        'totals': <Object?>[],
        'billing_address': <Object?>[],
      });
      expect(cart.totals.totalPrice.minorUnits, 0);
      expect(cart.billingAddress.isEmpty, isTrue);
    });

    test('a null where a string was expected', () {
      final WooProduct p = WooProduct.fromJson(const <String, Object?>{
        'name': null,
        'sku': null,
      });
      expect(p.name, isEmpty);
      expect(p.sku, isEmpty);
    });

    test('a whole product of nonsense still parses', () {
      final WooProduct p = WooProduct.fromJson(const <String, Object?>{
        'id': <Object?>[],
        'name': 42,
        'price': <String, Object?>{},
        'categories': 'not a list',
        'date_created': 'not a date',
      });
      expect(p.id, 0);
      expect(p.name, '42');
      expect(p.dateCreated, isNull);
      // And the original is still there to look at.
      expect(p.raw['categories'], 'not a list');
    });
  });

  group('currency formatting survives a partial store', () {
    test('a missing minor unit assumes two', () {
      final StoreMoney m = StoreMoney.read(const <String, Object?>{
        'price': '1800',
      }, 'price');
      expect(m.currency.minorUnit, 2);
      expect(m.toString(), '18.00');
    });

    test(
      'an empty decimal separator falls back, an empty grouping does not',
      () {
        // "" for a decimal separator would render 8256 as "8256". "" for the
        // thousand separator is a real choice — some stores group nothing.
        final StoreCurrency c = StoreCurrency.fromJson(const <String, Object?>{
          'currency_decimal_separator': '',
          'currency_thousand_separator': '',
        });
        expect(c.decimalSeparator, '.');
        expect(c.thousandSeparator, '');
        expect(c.format(123456), '1234.56');
      },
    );

    test('minor units sent as an integer, not a string', () {
      final StoreMoney m = StoreMoney.read(const <String, Object?>{
        'price': 1800,
      }, 'price');
      expect(m.minorUnits, 1800);
    });
  });

  test(
    'an empty response for a whole collection is empty, not an error',
    () async {
      final FakeStore store = FakeStore((_) => Reply(<Object?>[]));
      final WooCommerce woo = WooCommerce(
        baseUrl: 'https://shop.test',
        credentials: const WooCredentials.key(
          consumerKey: 'ck',
          consumerSecret: 'cs',
        ),
        httpClient: store.client,
      );
      addTearDown(woo.close);

      expect((await woo.admin.productCategories.list()).items, isEmpty);
      expect(await woo.admin.paymentGateways(), isEmpty);
    },
  );

  test('a cart with nothing in it reads as empty', () {
    final StoreCart cart = StoreCart.fromJson(const <String, Object?>{});
    expect(cart.isEmpty, isTrue);
    expect(cart.itemsCount, 0);
    expect(cart.hasErrors, isFalse);
    expect(cart.totals.totalPrice.isZero, isTrue);
    expect(cartJson()['items'], isNotEmpty, reason: 'sanity check on fixture');
  });

  group('a missing state fails closed, not open', () {
    test('a review with no status is not treated as approved', () {
      expect(
        WooReview.fromJson(const <String, Object?>{'id': 1}).isApproved,
        isFalse,
      );
      expect(
        WooReview.fromJson(const <String, Object?>{'status': 'approved'})
            .isApproved,
        isTrue,
      );
    });

    test('a webhook with no status is not treated as active', () {
      expect(
        WooWebhook.fromJson(const <String, Object?>{'id': 1}).isActive,
        isFalse,
      );
      expect(
        WooWebhook.fromJson(const <String, Object?>{'status': 'active'})
            .isActive,
        isTrue,
      );
    });
  });
}
