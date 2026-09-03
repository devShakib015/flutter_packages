## 0.3.1

The README claimed "no other Dart package implements it" of the Store API. That
absolute is false and is now corrected.

`woocommerce` (last published 2020) and its fork `flutter_wp_woocommerce` (2022)
both define `URL_STORE_API_PATH = '/wp-json/wc/store/'` and call `cart`,
`cart/items` and `cart/items/{key}`. They are abandoned, but they exist, and the
claim as written was wrong.

What is actually true, checked by downloading and grepping all six WooCommerce
archives on pub.dev: `Cart-Token` appears in none of them, so every one depends
on a cookie session and none works from an app; none implements Store API
checkout or `select-shipping-rate`. The README now says that instead — narrower,
verified, and still the reason to use this package from Flutter.

Caught while cross-checking a distribution assessment that had asserted
`wc/store` appears in zero rival archives. It does not.

## 0.3.0

An audit of every package in this repo found five defects here. Two of them
could lose or leak real things, so this release is worth taking.

**Breaking:** `WooOrderStatus.unknown.wireName` now throws instead of returning
`'pending'`. Read an order whose status came from a plugin, call `setStatus`,
and 0.2.x quietly moved a paid order back to unpaid. There is no safe wire form
for a status this package does not model, so it refuses to invent one. Use the
new `WooOrder.statusName` to read the store's own spelling and
`WooOrders.setStatusRaw` to send it back. `orders.list(statuses:)` drops
`unknown` from the filter rather than substituting `pending`.

### Fixed

- **Credentials no longer reach an exception message.** Key authentication
  travels in the query string, and every `WooNetworkException` interpolated the
  full request URI — consumer key and secret included. Anyone logging that
  exception shipped their store credentials to their crash reporter. The URI is
  redacted now, and a test asserts the secret cannot appear.
- **`variationFor` could never match a global attribute.** WooCommerce builds a
  variation's attribute name with `wc_attribute_label`, so it is the display
  label (`Colour`), while `cart.addItem` requires the `pa_` taxonomy. The
  dartdoc told you to pass the taxonomy, which never matched, and the fixture
  used the taxonomy for both so the test agreed with the bug. It now accepts
  either spelling from either side, and the new `cartAttributes` rewrites a
  chosen map into the keys `addItem` actually wants.
- **Two concurrent first calls made two carts.** Both went out with no
  `Cart-Token`, the store created a cart for each, and whichever token arrived
  last won — the other's items were gone. The first tokenless request now
  claims the session and the rest wait for it, and a failed first request
  releases the gate instead of wedging everything behind it.
- **A partly failed batch was silent.** `cart.addItems` and `cart.clear` threw
  away the per-item results, so adding five items where one was out of stock
  returned a cart with four and no sign anything had failed. Both now throw a
  `WooInvalidRequestException` naming what the store refused.

202 tests, 160/160.

## 0.2.2

- A screenshot on pub.dev, from a real storefront built on the Store API. The
  demo lives in `storefront/` and runs with no network and no keys, because
  `WooStore` takes any `http.Client` — so everything in the picture is the
  package doing real parsing on real Store API payloads. Point it at your own
  shop with `--dart-define=STORE=https://your-store.com`.
- Regenerate it with `tool/shoot.sh`.

## 0.2.1

Verified the Store API parser against a live store — woocommerce.com's own,
which serves the public Store API — rather than only against fixtures. It
parsed, and it surfaced fields the documentation's own example omits:

- `stockText` and `stockClass`: the store's own stock line, already worded and
  translated (`Only 2 left in stock`). Better than composing one from
  `isInStock` and `lowStockRemaining`, because this one is in the shopper's
  language.
- `weight`, `formattedWeight`, `dimensions`, `formattedDimensions`. Note that
  stores commonly send the literal string `N/A` rather than an empty one.
- `groupedProducts` and `variationDescription`.

Also pinned: that store's product ids are thirteen digits, so the fixtures now
carry one.

## 0.2.0

The Store API — WooCommerce's public, keyless one — plus everything the admin
API exposes rather than only the four resources 0.1.0 shipped.

Nothing from 0.1.0 changed shape, so upgrading is a version bump.

### The Store API (new)

`WooStore` speaks `wc/store/v1`, which needs **no API keys at all** and is the
API a shipped app should use. Nothing else in Dart implements it.

- Cart: add, update, remove, coupons, customer addresses, shipping rate
  selection, and a batch add that is one request and one recalculation instead
  of one of each per item.
- Checkout: the draft order, field persistence, submitting, retrying a declined
  payment, and off-site gateways (`needsRedirect` — the order is not paid until
  the shopper comes back).
- `expectedTotal` on submit, so a total that moved underneath is refused with
  `WooTotalMismatchException` — carrying the refreshed cart — instead of
  charging an amount the shopper never saw.
- Public product browsing, categories, tags, and reviews.
- `StoreMoney` and `StoreCurrency`. The Store API sends prices as integer minor
  units — `"1800"` is eighteen dollars — with the store's own symbol and
  separators alongside. These print what the store would print, in the store's
  own format, and do arithmetic on integers so it is exact.
- `CartSession` captures the `Cart-Token` and replays it. Supply a
  `CartTokenStore` and a shopper's basket survives an app restart. A cart token
  also removes the nonce requirement, which matters because a nonce can only be
  minted by WordPress, so an app has no way to produce one.
- `StoreQuantityLimits.clamp` respects minimums, maximums, and multiples, so a
  stepper cannot ask for a quantity the store will refuse.

### Admin API

- Categories, tags, attributes and their terms, reviews, shipping classes, tax
  rates and classes, shipping zones with locations and methods, payment
  gateways, webhooks, reports, settings, reference data, and system status —
  all under `woo.admin`.
- All of them, and products/orders/customers/coupons, are `WooCollection`s, so
  they share `list` / `get` / `create` / `update` / `delete` / `all()` /
  `batch()`. Nothing gets paging or batching only because someone got round to
  it.
- `batch()` does up to 100 operations in one request, and throws over that
  rather than letting WooCommerce silently truncate.

### Everywhere

- **Webhook signature verification.** `WooWebhookDelivery` parses a delivery and
  checks its HMAC-SHA256 in constant time. Without this a stranger can POST to
  your endpoint and tell your system an order was paid.
- **Application passwords.** `WooCredentials.applicationPassword` — built into
  WordPress since 5.6, revocable on its own, and running as a real user. The
  cosmetic spaces WordPress displays are stripped, since pasting them in is the
  commonest reason it fails.
- **Retry**, off by default because this package cannot know whether your POST
  is safe to repeat. `WooRetry.reads()` covers GETs; backoff is exponential with
  jitter and honours the store's own `Retry-After`.
- **Rate limiting** is `WooRateLimitException`, carrying how long to wait, read
  from WooCommerce's `RateLimit-Retry-After` or a proxy's `Retry-After` in
  either seconds or HTTP-date form.
- **Parsing tolerates a store that sends the wrong type.** WordPress writes a
  boolean as `true`, `"yes"`, `"1"`, or `1` depending on who wrote the field,
  and PHP turns a sparse array into an object. A hard cast lost the whole
  response over one field nobody was reading; now it costs that field. An absent
  moderation or webhook state deliberately does **not** default to approved or
  active.
- `HttpDate` was avoided in favour of `http_parser`, so the package still
  supports all six platforms including web and WASM.

### Fixed

- Store product paging headers lived on the client, so two list calls in flight
  at once read each other's totals.
- The README said `getOne('/reports/sales')`; that route returns an array.

## 0.1.0

First release.

- `WooCommerce` client for the WooCommerce REST API v3, over any `http.Client`.
- Products (with variations), orders, customers and coupons: list, get, create,
  update, delete, plus `bySku`, `byEmail`, `byCode` and `all()` streams.
- `WooPage` carries the store's own `X-WP-Total` and `X-WP-TotalPages`, so
  `hasMore` and `nextPage` are answers rather than guesses.
- A sealed `WooException` hierarchy: auth, not found, invalid request, server,
  network, and bad response are separate types you can catch by kind.
- `WooPrice` keeps WooCommerce's empty-string price distinct from zero, and
  keeps the store's own formatting.
- Every model keeps the full response in `raw`, so plugin fields and anything
  not modelled here are still reachable.
- Refuses to send a consumer secret over plain HTTP.
- Pure Dart, one dependency.
