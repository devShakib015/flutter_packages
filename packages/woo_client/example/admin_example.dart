// The admin API: everything, behind a consumer key.
//
//   dart run example/admin_example.dart https://your-store.com ck_… cs_…
//
// Run this from a server, a CLI, or a script — never from a shipped app.
// A key here can read every customer's address and change every price.
import 'dart:io';

import 'package:woo_client/woo_client.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln('usage: admin_example <store-url> <key> <secret>');
    exitCode = 64;
    return;
  }

  final WooCommerce woo = WooCommerce(
    baseUrl: args[0],
    credentials: WooCredentials.key(
      consumerKey: args[1],
      consumerSecret: args[2],
    ),
    retry: const WooRetry.reads(),
  );

  try {
    await _catalogue(woo);
    await _orders(woo);
    await _store(woo);
    await _bulk(woo);
  } on WooAuthException catch (e) {
    stderr.writeln('The store refused those credentials: ${e.message}');
    exitCode = 77;
  } finally {
    woo.close();
  }
}

Future<void> _catalogue(WooCommerce woo) async {
  final WooPage<WooProduct> products = await woo.products.list(
    perPage: 5,
    orderBy: WooProductOrderBy.popularity,
  );
  stdout.writeln('${products.totalItems ?? '?'} products. Top sellers:');
  for (final WooProduct p in products.items) {
    stdout.writeln('  ${p.name} — ${p.price} — ${p.stockStatus.name}');
  }

  final WooPage<WooCategory> categories = await woo.admin.productCategories
      .list(perPage: 100);
  stdout.writeln(
    '\n${categories.items.length} categories: '
    '${categories.items.take(6).map((WooCategory c) => c.name).join(', ')}',
  );

  for (final WooAttribute a
      in (await woo.admin.productAttributes.list()).items) {
    final WooPage<WooAttributeTerm> terms = await woo.admin
        .attributeTerms(a.id)
        .list(perPage: 100);
    stdout.writeln(
      '  ${a.name} (${a.taxonomy}): '
      '${terms.items.map((WooAttributeTerm t) => t.name).join(', ')}',
    );
  }
}

Future<void> _orders(WooCommerce woo) async {
  final WooPage<WooOrder> page = await woo.orders.list(
    statuses: <WooOrderStatus>[
      WooOrderStatus.processing,
      WooOrderStatus.onHold,
    ],
    perPage: 3,
  );

  stdout.writeln('\n${page.totalItems ?? 0} orders need attention:');
  for (final WooOrder o in page.items) {
    stdout.writeln('  #${o.number}  ${o.total}  ${o.billing.fullName}');
    for (final WooOrderNote n
        in (await woo.admin.orderNotes(o.id).list()).items) {
      stdout.writeln('    note: ${n.note}');
    }
  }
}

Future<void> _store(WooCommerce woo) async {
  stdout.writeln('\nStore');
  stdout.writeln('  currency  ${await woo.admin.settings.currency()}');

  final List<WooPaymentGateway> gateways = await woo.admin.paymentGateways();
  final Iterable<WooPaymentGateway> live = gateways.where(
    (WooPaymentGateway g) => g.enabled,
  );
  stdout.writeln(
    '  payments  ${live.map((WooPaymentGateway g) => g.id).join(', ')}',
  );

  for (final WooTaxRate t in (await woo.admin.taxRates.list()).items) {
    stdout.writeln('  tax       $t in ${t.country}');
  }

  final Map<String, Object?> status = await woo.admin.systemStatus();
  final Map<String, Object?> env =
      status['environment'] as Map<String, Object?>? ?? const {};
  stdout.writeln(
    '  versions  WooCommerce ${env['version']}, WP ${env['wp_version']}',
  );
}

Future<void> _bulk(WooCommerce woo) async {
  // A price change across a catalogue is one request per hundred products,
  // not one per product.
  final WooPage<WooProduct> onSale = await woo.products.list(
    onSale: true,
    perPage: 100,
  );
  if (onSale.isEmpty) {
    stdout.writeln('\nNothing on sale, so nothing to bulk-edit.');
    return;
  }
  stdout.writeln(
    '\n${onSale.items.length} products on sale — a single batch call could '
    'reprice all of them:',
  );
  for (final WooProduct p in onSale.items.take(3)) {
    stdout.writeln('  ${p.name}: ${p.regularPrice} -> ${p.salePrice}');
  }
  // await woo.products.batch(update: [
  //   for (final p in onSale.items) {'id': p.id, 'sale_price': ''},
  // ]);
}
