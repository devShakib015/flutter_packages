import 'package:test/test.dart';
import 'package:woo_client/woo_client.dart';

void main() {
  const StoreCurrency usd = StoreCurrency(
    code: 'USD',
    symbol: r'$',
    prefix: r'$',
  );

  group('formatting', () {
    test('minor units become the price a shopper recognises', () {
      // The whole point: the Store API sends "1800" for eighteen dollars.
      // A client that prints the raw string shows $1800.
      expect(usd.format(1800), r'$18.00');
      expect(usd.format(8256), r'$82.56');
      expect(usd.format(5), r'$0.05');
      expect(usd.format(0), r'$0.00');
    });

    test('groups thousands', () {
      expect(usd.format(123456), r'$1,234.56');
      expect(usd.format(100000000), r'$1,000,000.00');
      expect(usd.format(99999), r'$999.99');
    });

    test('a negative goes before the symbol, not inside it', () {
      expect(usd.format(-1095), r'-$10.95');
    });

    test('a zero-decimal currency has no decimal part', () {
      const StoreCurrency jpy = StoreCurrency(
        code: 'JPY',
        symbol: '¥',
        prefix: '¥',
        minorUnit: 0,
      );
      // 1800 yen is 1800 yen, not 18.00.
      expect(jpy.format(1800), '¥1,800');
      expect(jpy.format(0), '¥0');
    });

    test('a three-decimal currency keeps all three', () {
      const StoreCurrency bhd = StoreCurrency(
        code: 'BHD',
        prefix: 'BD ',
        minorUnit: 3,
      );
      expect(bhd.format(1800), 'BD 1.800');
      expect(bhd.format(5), 'BD 0.005');
    });

    test("uses the store's own separators, not the locale's", () {
      const StoreCurrency eur = StoreCurrency(
        code: 'EUR',
        suffix: ' €',
        decimalSeparator: ',',
        thousandSeparator: '.',
      );
      expect(eur.format(123456), '1.234,56 €');
    });

    test('a store that groups nothing gets nothing grouped', () {
      const StoreCurrency plain = StoreCurrency(thousandSeparator: '');
      expect(plain.format(123456), '1234.56');
    });
  });

  group('amounts', () {
    StoreMoney money(int n) => StoreMoney(n, usd);

    test('reads a field and its currency out of one object', () {
      final StoreMoney m = StoreMoney.read(<String, Object?>{
        'total_price': '8256',
        'currency_code': 'GBP',
        'currency_prefix': '£',
        'currency_minor_unit': 2,
        'currency_decimal_separator': '.',
        'currency_thousand_separator': ',',
      }, 'total_price');
      expect(m.minorUnits, 8256);
      expect(m.currency.code, 'GBP');
      expect(m.toString(), '£82.56');
    });

    test('a missing field is zero, not a crash', () {
      final StoreMoney m = StoreMoney.read(const <String, Object?>{}, 'nope');
      expect(m.minorUnits, 0);
      expect(m.isZero, isTrue);
    });

    test('adds exactly, because it adds integers', () {
      // 0.1 + 0.2 in doubles is not 0.3. In minor units it is 30.
      final StoreMoney sum = money(10) + money(20);
      expect(sum.minorUnits, 30);
      expect(sum.amount, 0.30);
    });

    test('multiplies for a line total', () {
      expect((money(1800) * 3).toString(), r'$54.00');
    });

    test('subtracts, and may go negative', () {
      expect((money(1000) - money(1500)).toString(), r'-$5.00');
    });

    test('compares and sorts', () {
      expect(money(100) < money(200), isTrue);
      expect(money(200) >= money(200), isTrue);
      final List<StoreMoney> sorted = <StoreMoney>[
        money(500),
        money(100),
        money(300),
      ]..sort();
      expect(sorted.map((StoreMoney m) => m.minorUnits), <int>[100, 300, 500]);
    });

    test('two amounts of the same currency and size are equal', () {
      expect(money(1800), money(1800));
      expect(<StoreMoney>{money(1800), money(1800)}, hasLength(1));
    });

    test('amount is a convenience, not the source of truth', () {
      expect(money(8256).amount, 82.56);
      expect(money(1).amount, 0.01);
    });
  });
}
