# woo_client

A typed WooCommerce REST v3 client for Dart.

```dart
final woo = WooCommerce(
  baseUrl: 'https://your-store.com',
  credentials: WooCredentials.key(consumerKey: ck, consumerSecret: cs),
);

final page = await woo.products.list(search: 'satchel', onSale: true);

for (final product in page.items) {
  print('${product.name} — ${product.price}');
}
```

Pure Dart, so it runs in Flutter, on a server, and in a CLI. One dependency:
`http`.

## Why another one

- **Errors you can catch by kind.** `WooAuthException`, `WooNotFoundException`,
  `WooInvalidRequestException`, `WooServerException`, `WooNetworkException`,
  `WooBadResponseException` — a sealed hierarchy, so a `switch` over them is
  exhaustive. No parsing of error strings to find out what went wrong.
- **Pagination that carries the totals.** `WooPage` reads WooCommerce's
  `X-WP-Total` headers, so you know how many pages there are before you ask for
  the next one. `all()` walks them for you as a stream.
- **Nothing is hidden.** Every model keeps the entire response in `.raw`, so a
  field this package does not model — yours, or one from a plugin — is still one
  map lookup away. You are never blocked waiting for a release.
- **Unset is not zero.** WooCommerce sends `""` for "no price". Parsing that to
  `0.0` makes an unpriced variation look free. `WooPrice` keeps the distinction,
  and keeps the store's own formatting.
- **Testable.** Pass any `http.Client`, including
  [`MockClient`](https://pub.dev/documentation/http/latest/testing/MockClient-class.html),
  and your tests never touch a network.

## Install

```bash
dart pub add woo_client
```

## Credentials — please read this

WooCommerce API keys are **store credentials**, not user credentials. A
read/write key can change prices, read every customer's address, and refund
orders.

**Anything you ship to a user's device can be read by that user.** Keys in a
Flutter app are recoverable from the binary in minutes, no matter how you
obfuscate them. This is not a WooCommerce quirk; it is true of every API key in
every client app.

So:

| Where your code runs | What to do |
| --- | --- |
| Your server, a CLI, a build script, an admin tool you control | `WooCredentials.key(...)` is fine. |
| A shipped app, or a web page | Put your own backend in front of the store. The app talks to you; you talk to WooCommerce. |
| A shipped app where the user logs in | `WooCredentials.bearer(token)` with a JWT plugin, so each user acts as themselves. |

This client refuses to send a consumer secret over plain `http://` and throws an
`ArgumentError` instead — a key sent in a query string over HTTP is readable by
every hop in between. `http://localhost` for development is fine, because no
secret is involved when you pass no credentials.

## Reading

```dart
// Filters, all optional.
final page = await woo.products.list(
  search: 'leather',
  categories: [21],
  onSale: true,
  minPrice: '50',
  orderBy: WooProductOrderBy.popularity,
  perPage: 20,
);

page.totalItems;  // 57, from the store's own header
page.totalPages;  // 3
page.hasMore;     // true
page.nextPage;    // 2

final one = await woo.products.get(799);
final bySku = await woo.products.bySku('SATCHEL-01');   // null if none
final variations = await woo.products.variations(799);
```

Every model exposes the parts you reach for, typed:

```dart
product.onSale;         // bool
product.regularPrice;   // WooPrice('129.00')
product.salePrice;      // WooPrice('99.00')
product.stockQuantity;  // 4, or null when the store does not count
product.categories;     // List<WooTerm>
product.images;         // List<WooImage>
product.dateCreated;    // DateTime?
```

…and the whole response, for the parts it does not:

```dart
product.raw['_yoast_wpseo_title'];
product.raw['meta_data'];
```

### Every page, without a paging loop

```dart
await for (final product in woo.products.all(perPage: 100)) {
  await index(product);
}
```

`all()` fetches the next page only when you are ready for it, and stops as soon
as you stop listening — a `break` costs you one request, not the whole catalogue.

## Writing

```dart
final order = await woo.orders.create(
  lineItems: [
    WooLineItem.order(productId: 799, quantity: 2),
    WooLineItem.order(productId: 812, quantity: 1, variationId: 815),
  ],
  billing: WooAddress(
    firstName: 'Ada',
    lastName: 'Lovelace',
    address1: '12 Analytical Way',
    city: 'London',
    postcode: 'N1 7GU',
    country: 'GB',
    email: 'ada@example.com',
  ),
  paymentMethod: 'stripe',
  setPaid: false,
);

await woo.orders.setStatus(order.id, WooOrderStatus.completed);
```

`WooLineItem.order` deliberately sends only the product and the quantity. The
store applies its own prices, taxes, and coupons — a client that sends a price
is a client that can be told to send `0.01`.

Fields this package does not model go through untouched:

```dart
await woo.orders.create(
  lineItems: [...],
  extra: {
    'meta_data': [
      {'key': '_gift_note', 'value': 'Happy birthday'},
    ],
  },
);
```

## Errors

```dart
try {
  await woo.products.get(id);
} on WooNotFoundException {
  return null;
} on WooAuthException catch (e) {
  log('Key rejected: ${e.message}');
} on WooInvalidRequestException catch (e) {
  log('Store said no: ${e.code} ${e.details}');
} on WooServerException {
  return retryLater();
} on WooNetworkException catch (e) {
  log('Never reached the store: ${e.cause}');
} on WooBadResponseException catch (e) {
  // A plugin printing a notice, or a login wall on the REST route.
  log('Not JSON: ${e.body}');
}
```

`WooBadResponseException` earns its place: a misbehaving plugin can return HTML
with a `200`, and "unexpected character" from a JSON decoder several frames away
is a bad first clue.

All six extend `WooException`, which is `sealed` — so a `switch` over an error
is exhaustive, and adding a case later is a compile error rather than a silent
fall-through.

## Testing your own code

```dart
final woo = WooCommerce(
  baseUrl: 'https://example.com',
  httpClient: MockClient((request) async => http.Response(
    jsonEncode([{'id': 1, 'name': 'Satchel', 'price': '129.00'}]),
    200,
    headers: {'content-type': 'application/json', 'x-wp-total': '1'},
  )),
);
```

## What is covered

Products (and variations), orders, customers, and coupons: list, get, create,
update, delete, plus `all()` streams and the lookups you actually reach for
(`bySku`, `byEmail`, `byCode`).

Anything else in the REST API is one call away, with the same auth, paging, and
error handling:

```dart
final report = await woo.getOne('/reports/sales');
final refunds = await woo.getPage('/orders/5120/refunds');
```

## Compatibility

WooCommerce 3.5+ (REST API v3), any WordPress that runs it. Requires HTTPS for
key authentication.

---

Not affiliated with or endorsed by Automattic or WooCommerce.
