// A small tour of the client, runnable against any WooCommerce store.
//
//   dart run example/woo_client_example.dart https://your-store.com ck_... cs_...
//
// The read-only key you can make under WooCommerce → Settings → Advanced →
// REST API is enough for everything here.
import 'dart:io';

import 'package:woo_client/woo_client.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln('usage: woo_client_example <store-url> <key> <secret>');
    exitCode = 64;
    return;
  }

  final WooCommerce woo = WooCommerce(
    baseUrl: args[0],
    credentials: WooCredentials.key(
      consumerKey: args[1],
      consumerSecret: args[2],
    ),
  );

  try {
    await _products(woo);
    await _oneProduct(woo);
    await _orders(woo);
    await _everything(woo);
  } on WooAuthException catch (e) {
    stderr.writeln('The store refused those credentials: ${e.message}');
    exitCode = 77;
  } on WooNetworkException catch (e) {
    stderr.writeln('Could not reach the store: ${e.message}');
    exitCode = 69;
  } finally {
    woo.close();
  }
}

Future<void> _products(WooCommerce woo) async {
  final WooPage<WooProduct> page = await woo.products.list(
    perPage: 5,
    orderBy: WooProductOrderBy.popularity,
  );

  print('Most popular (${page.totalItems ?? '?'} products in the store):');
  for (final WooProduct p in page.items) {
    final String price = p.onSale
        ? '${p.salePrice} (was ${p.regularPrice})'
        : '${p.price}';
    final String stock = switch (p.stockQuantity) {
      final int n => '$n left',
      null => p.stockStatus.name,
    };
    print('  ${p.name} — $price — $stock');
  }
}

Future<void> _oneProduct(WooCommerce woo) async {
  final WooPage<WooProduct> first = await woo.products.list(perPage: 1);
  if (first.isEmpty) return;

  // A missing product is a WooNotFoundException, not a null.
  final WooProduct p = await woo.products.get(first.items.first.id);
  print('\n${p.name}');
  print('  sku        ${p.sku.isEmpty ? '(none)' : p.sku}');
  print('  categories ${p.categories.map((WooTerm t) => t.name).join(', ')}');
  print('  rating     ${p.averageRating} from ${p.ratingCount}');

  if (p.type == WooProductType.variable) {
    final WooPage<WooProduct> variations = await woo.products.variations(p.id);
    print('  ${variations.items.length} variations');
  }

  // Anything this package does not model is still there.
  print('  status     ${p.raw['status']}');
}

Future<void> _orders(WooCommerce woo) async {
  final WooPage<WooOrder> page = await woo.orders.list(
    statuses: <WooOrderStatus>[
      WooOrderStatus.processing,
      WooOrderStatus.onHold,
    ],
    perPage: 5,
  );

  print('\nOrders needing attention: ${page.totalItems ?? page.items.length}');
  for (final WooOrder o in page.items) {
    print(
      '  #${o.number}  ${o.total}  ${o.itemCount} items  '
      '${o.billing.fullName}  ${o.status.name}',
    );
  }
}

Future<void> _everything(WooCommerce woo) async {
  // all() pages behind the scenes; it stops as soon as you stop listening.
  int counted = 0;
  await for (final WooProduct _ in woo.products.all(perPage: 100)) {
    counted++;
    if (counted >= 250) break;
  }
  print('\nWalked $counted products without writing a paging loop.');
}
