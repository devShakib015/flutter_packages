// A shop, end to end, against any WooCommerce store — with no API keys.
//
//   dart run example/woo_client_example.dart https://your-store.com
//
// Everything here uses the public Store API, which is what a shipped app
// should use. For the admin API, see admin_example.dart in this directory.
import 'dart:io';

import 'package:woo_client/woo_client.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: woo_client_example <store-url>');
    exitCode = 64;
    return;
  }

  final WooStore store = WooStore(
    baseUrl: args.first,
    // Reads are retried; nothing here writes money.
    retry: const WooRetry.reads(),
  );

  try {
    final StoreProduct? pick = await _browse(store);
    if (pick == null) {
      stdout.writeln('Nothing purchasable in the catalogue; stopping here.');
      return;
    }
    await _fillCart(store, pick);
    await _quoteShipping(store);
    await _showCheckout(store);
  } on WooRateLimitException catch (e) {
    stderr.writeln('The store is rate limiting; retry in ${e.retryAfter}.');
    exitCode = 75;
  } on WooNetworkException catch (e) {
    stderr.writeln('Could not reach the store: ${e.message}');
    exitCode = 69;
  } finally {
    store.close();
  }
}

Future<StoreProduct?> _browse(WooStore store) async {
  final WooPage<StoreProduct> page = await store.products.list(
    perPage: 5,
    orderBy: StoreProductOrderBy.popularity,
  );

  stdout.writeln('Most popular of ${page.totalItems ?? '?'}:');
  for (final StoreProduct p in page.items) {
    // Prices arrive as minor units — "1800" — and print themselves the way
    // the store would, separators, symbol, and all.
    final String price = switch (p.priceRange) {
      final StorePriceRange r when !r.isFlat => '$r',
      _ => '${p.price}',
    };
    final String stock = p.isInStock ? '' : ' (out of stock)';
    stdout.writeln('  ${p.name} — $price$stock');
  }

  return page.items
      .where((StoreProduct p) => p.isPurchasable && p.isInStock)
      .firstOrNull;
}

Future<void> _fillCart(WooStore store, StoreProduct pick) async {
  // A variable product needs a variation chosen; pick the first of each
  // attribute so the example works against any catalogue.
  final Map<String, String>? variation = pick.needsOptions
      ? <String, String>{
          for (final StoreAttribute a in pick.attributes)
            if (a.terms.isNotEmpty) a.wireName: a.terms.first.slug,
        }
      : null;
  final int id = pick.needsOptions
      ? (pick.variationFor(variation!)?.id ?? pick.id)
      : pick.id;

  StoreCart cart = await store.cart.addItem(id: id, quantity: 1);
  stdout.writeln('\nAdded ${pick.name}. Cart: ${cart.totals.totalPrice}');

  // The limits know about minimums and multiples, so a stepper built on them
  // cannot ask for a quantity the store will refuse.
  final StoreCartItem line = cart.items.first;
  cart = await store.cart.updateItem(
    key: line.key,
    quantity: line.limits.clamp(3),
  );
  stdout.writeln(
    'Set quantity to ${cart.items.first.quantity}: '
    '${cart.totals.totalPrice}',
  );

  for (final StoreCartError e in cart.errors) {
    // Not a failure — the store telling you something changed underneath.
    stdout.writeln('  note: ${e.message}');
  }
}

Future<void> _quoteShipping(WooStore store) async {
  // A country and a postcode are enough; no full address needed to quote.
  final StoreCart cart = await store.cart.updateCustomer(
    shippingAddress: const StoreAddress(
      city: 'London',
      postcode: 'N1 7GU',
      country: 'GB',
    ),
  );

  if (!cart.needsShipping) {
    stdout.writeln('\nNothing to ship.');
    return;
  }

  stdout.writeln('\nShipping:');
  for (final StoreShippingPackage pkg in cart.shippingPackages) {
    for (final StoreShippingRate rate in pkg.rates) {
      final String mark = rate.selected ? '*' : ' ';
      stdout.writeln('  $mark ${rate.name} — ${rate.price}');
    }
    final StoreShippingRate? cheapest = pkg.rates.isEmpty
        ? null
        : (pkg.rates.toList()..sort(
                (StoreShippingRate a, StoreShippingRate b) =>
                    a.price.compareTo(b.price),
              ))
              .first;
    if (cheapest != null && !cheapest.selected) {
      final StoreCart after = await store.cart.selectShippingRate(
        packageId: pkg.packageId,
        rateId: cheapest.rateId,
      );
      stdout.writeln('  chose ${cheapest.name}: ${after.totals.totalPrice}');
    }
  }
}

Future<void> _showCheckout(WooStore store) async {
  final StoreCart cart = await store.cart.get();
  final StoreCheckout draft = await store.checkout.get();

  stdout
    ..writeln('\nCheckout')
    ..writeln('  draft order  ${draft.orderId} (${draft.status})')
    ..writeln('  items        ${cart.totals.totalItems}')
    ..writeln('  shipping     ${cart.totals.totalShipping}')
    ..writeln('  tax          ${cart.totals.totalTax}')
    ..writeln('  to pay       ${cart.totals.totalPrice}')
    ..writeln('  pay with     ${cart.paymentMethods.join(', ')}');

  // Deliberately not submitted: this example is safe to run against a real
  // store. Placing the order would be:
  //
  //   final result = await store.checkout.submitAndClear(
  //     billingAddress: address,
  //     paymentMethod: cart.paymentMethods.first,
  //     expectedTotal: cart.totals.totalPrice,  // refuses if the total moved
  //   );
  //
  //   if (result.paymentResult.needsRedirect) {
  //     // Off-site gateway: not paid until they come back.
  //     await launchUrl(Uri.parse(result.paymentResult.redirectUrl));
  //   }
  stdout.writeln('\n(Not submitting — this example does not place orders.)');
}
