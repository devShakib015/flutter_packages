import 'package:flutter/material.dart';
import 'package:woo_client/woo_client.dart';

import 'demo_store.dart';

/// Point at a real shop with
/// `--dart-define=STORE=https://your-store.com`; otherwise the demo store in
/// [demoStoreClient] answers, so this runs with no network and no keys.
const String _storeUrl = String.fromEnvironment(
  'STORE',
  defaultValue: 'https://demo.test',
);
const bool _live = bool.hasEnvironment('STORE');

void main() => runApp(const StorefrontApp());

/// A small shop built on the Store API.
class StorefrontApp extends StatelessWidget {
  /// Creates the app.
  const StorefrontApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'woo_client',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFF7F54B3),
      scaffoldBackgroundColor: const Color(0xFFF4F4F7),
      fontFamily: 'Roboto',
    ),
    home: const Shop(),
  );
}

/// The shop screen: a catalogue on the left, the cart on the right.
class Shop extends StatefulWidget {
  /// Creates the screen.
  const Shop({super.key});

  @override
  State<Shop> createState() => _ShopState();
}

class _ShopState extends State<Shop> {
  late final WooStore _store = WooStore(
    baseUrl: _storeUrl,
    httpClient: _live ? null : demoStoreClient(),
  );

  List<StoreProduct> _products = const <StoreProduct>[];
  StoreCart? _cart;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _store.close();
    super.dispose();
  }

  Future<void> _load() async {
    final WooPage<StoreProduct> page = await _store.products.list(perPage: 12);
    if (!mounted) return;
    setState(() {
      _products = page.items;
      _busy = false;
    });
    await _demoScript();
  }

  /// Fills the cart so the screenshot shows a shop mid-use rather than empty.
  /// Every call here is the ordinary public API.
  Future<void> _demoScript() async {
    if (!Uri.base.queryParameters.containsKey('auto')) {
      await _refresh(await _store.cart.get());
      return;
    }
    await _store.cart.addItem(id: 38, quantity: 1);
    await _store.cart.addItem(id: 41, quantity: 2);
    await _store.cart.applyCoupon('WELCOME10');
    await _store.cart.updateCustomer(
      shippingAddress: const StoreAddress(
        city: 'London',
        postcode: 'N1 7GU',
        country: 'GB',
      ),
    );
    await _refresh(
      await _store.cart.selectShippingRate(packageId: 0, rateId: 'flat_rate:1'),
    );
  }

  Future<void> _refresh(StoreCart cart) async {
    if (!mounted) return;
    setState(() => _cart = cart);
  }

  Future<void> _run(Future<StoreCart> Function() call) async {
    setState(() => _busy = true);
    final StoreCart cart = await call();
    if (!mounted) return;
    setState(() {
      _cart = cart;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 20,
      title: Row(
        children: <Widget>[
          const Text(
            'woo_client',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: Color(0xFF1B1B22),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEFE9F7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Store API · no API keys',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B44A8),
              ),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 20),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.shopping_bag_outlined,
                size: 20,
                color: Color(0xFF4B4B57),
              ),
              const SizedBox(width: 6),
              Text(
                '${_cart?.itemsCount ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    ),
    body: _busy && _products.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(flex: 3, child: _catalogue()),
                const SizedBox(width: 18),
                SizedBox(
                  width: 348,
                  child: _CartPanel(cart: _cart, run: _run, store: _store),
                ),
              ],
            ),
          ),
  );

  Widget _catalogue() => GridView.builder(
    padding: EdgeInsets.zero,
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 230,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 0.82,
    ),
    itemCount: _products.length,
    itemBuilder: (BuildContext c, int i) => _ProductCard(
      product: _products[i],
      onAdd: () => _run(() => _store.cart.addItem(id: _products[i].id)),
    ),
  );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onAdd});

  final StoreProduct product;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final bool low = product.stockClass == 'low-stock';
    final bool out = !product.isInStock;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E6EE)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: ColoredBox(
              color: Color(tintFor(product.id)).withValues(alpha: 0.14),
              child: Center(
                child: Icon(
                  Icons.work_outline,
                  size: 34,
                  color: Color(tintFor(product.id)).withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    // "12900" from the wire, printed the way the store would.
                    Text(
                      '${product.price}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: Color(0xFF1B1B22),
                      ),
                    ),
                    if (product.onSale) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        '${product.regularPrice}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                // The store's own stock line, already worded and translated.
                Text(
                  product.stockText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: low || out ? FontWeight.w600 : FontWeight.w400,
                    color: out
                        ? Colors.grey.shade500
                        : low
                        ? const Color(0xFFB45309)
                        : const Color(0xFF15803D),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 30,
                  child: FilledButton(
                    onPressed: out ? null : onAdd,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(out ? 'Out of stock' : product.addToCartText),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.cart,
    required this.run,
    required this.store,
  });

  final StoreCart? cart;
  final WooStore store;
  final Future<void> Function(Future<StoreCart> Function()) run;

  @override
  Widget build(BuildContext context) {
    final StoreCart? c = cart;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E6EE)),
      ),
      child: c == null || c.isEmpty
          ? const Center(child: Text('Your basket is empty'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Text(
                    'Basket',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    children: <Widget>[
                      for (final StoreCartItem i in c.items) _line(i),
                      if (c.coupons.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        for (final StoreCartCoupon co in c.coupons)
                          Row(
                            children: <Widget>[
                              const Icon(
                                Icons.local_offer_outlined,
                                size: 14,
                                color: Color(0xFF15803D),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                co.code.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '−${co.totalDiscount}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                            ],
                          ),
                      ],
                      if (c.shippingPackages.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 14),
                        const Text(
                          'Delivery',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: Color(0xFF6B6B78),
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final StoreShippingRate r
                            in c.shippingPackages.first.rates)
                          _rate(context, c.shippingPackages.first.packageId, r),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    children: <Widget>[
                      _total('Items', '${c.totals.totalItems}'),
                      if (!c.totals.totalDiscount.isZero)
                        _total('Discount', '−${c.totals.totalDiscount}'),
                      _total('Delivery', '${c.totals.totalShipping}'),
                      _total('VAT', '${c.totals.totalTax}'),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1),
                      ),
                      _total('To pay', '${c.totals.totalPrice}', big: true),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: FilledButton(
                          onPressed: () {},
                          child: const Text('Checkout'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _line(StoreCartItem i) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Color(tintFor(i.id)).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            Icons.work_outline,
            size: 17,
            color: Color(tintFor(i.id)).withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                i.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${i.quantity} × ${i.price}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        Text(
          '${i.lineTotal}',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _rate(
    BuildContext context,
    int packageId,
    StoreShippingRate r,
  ) => InkWell(
    onTap: () => run(
      () =>
          store.cart.selectShippingRate(packageId: packageId, rateId: r.rateId),
    ),
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(
            r.selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 16,
            color: r.selected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade400,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(r.name, style: const TextStyle(fontSize: 12)),
                if (r.deliveryTime.isNotEmpty)
                  Text(
                    r.deliveryTime,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            r.isFree ? 'Free' : '${r.price}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );

  static Widget _total(String label, String value, {bool big = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: big ? 14 : 12.5,
                fontWeight: big ? FontWeight.w700 : FontWeight.w400,
                color: big ? const Color(0xFF1B1B22) : const Color(0xFF5A5A67),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: big ? 16 : 12.5,
                fontWeight: big ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}
