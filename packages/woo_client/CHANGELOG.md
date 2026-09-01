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
