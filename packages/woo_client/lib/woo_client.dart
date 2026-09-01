/// A WooCommerce client for Dart: the admin REST API and the public Store API.
///
/// Two APIs, two clients, and the one you want depends on who is looking.
///
/// [WooStore] speaks the **Store API** — public, no keys, cart and checkout.
/// This is what a shopper's app should use.
///
/// ```dart
/// final store = WooStore(baseUrl: 'https://your-store.com');
///
/// await store.cart.addItem(id: 799, quantity: 2);
/// final cart = await store.cart.get();
/// print(cart.totals.totalPrice); // $82.56
/// ```
///
/// [WooCommerce] speaks the **admin REST API** — everything, behind a key.
/// This belongs on a server you control.
///
/// ```dart
/// final woo = WooCommerce(
///   baseUrl: 'https://your-store.com',
///   credentials: const WooCredentials.key(
///     consumerKey: 'ck_…',
///     consumerSecret: 'cs_…',
///   ),
/// );
///
/// final page = await woo.products.list(perPage: 20, onSale: true);
/// ```
///
/// Not affiliated with or endorsed by Automattic. WooCommerce is their
/// trademark; this is an independent client for their public APIs.
library;

export 'src/client.dart' show WooCommerce;
export 'src/credentials.dart'
    show
        BasicCredentials,
        BearerCredentials,
        KeyCredentials,
        NoCredentials,
        WooCredentials;
export 'src/exceptions.dart'
    show
        WooAuthException,
        WooBadResponseException,
        WooException,
        WooInvalidRequestException,
        WooNetworkException,
        WooNotFoundException,
        WooRateLimitException,
        WooServerException,
        WooTotalMismatchException;
export 'src/models/catalog.dart'
    show
        WooAttribute,
        WooAttributeTerm,
        WooCategory,
        WooOrderNote,
        WooPaymentGateway,
        WooRefund,
        WooReview,
        WooShippingClass,
        WooTag,
        WooTaxRate,
        WooWebhook;
export 'src/models/coupon.dart' show WooCoupon, WooDiscountType;
export 'src/models/customer.dart' show WooCustomer;
export 'src/models/money.dart' show WooPrice;
export 'src/models/order.dart'
    show WooAddress, WooLineItem, WooOrder, WooOrderStatus;
export 'src/models/product.dart'
    show WooImage, WooProduct, WooProductType, WooStockStatus, WooTerm;
export 'src/page.dart' show WooPage;
export 'src/resources/collection.dart' show WooBatchResult, WooCollection;
export 'src/resources/coupons.dart' show WooCoupons;
export 'src/resources/customers.dart' show WooCustomers;
export 'src/resources/orders.dart' show WooOrders;
export 'src/resources/products.dart' show WooProductOrderBy, WooProducts;
export 'src/resources/store_admin.dart'
    show WooAdminResources, WooData, WooReports, WooSettings, WooShippingZones;
export 'src/store/models/address.dart' show StoreAddress;
export 'src/store/models/cart.dart'
    show
        StoreCart,
        StoreCartCoupon,
        StoreCartError,
        StoreCartItem,
        StoreCartTotals,
        StoreImage,
        StoreQuantityLimits,
        StoreShippingPackage,
        StoreShippingRate;
export 'src/store/models/checkout.dart'
    show StoreCheckout, StorePaymentResult, StorePaymentStatus;
export 'src/store/models/store_product.dart'
    show
        StoreAttribute,
        StoreDimensions,
        StorePriceRange,
        StoreProduct,
        StoreTerm,
        StoreVariation;
export 'src/store/money.dart' show StoreCurrency, StoreMoney;
export 'src/store/resources/cart.dart' show StoreCartResource;
export 'src/store/resources/checkout.dart' show StoreCheckoutResource;
export 'src/store/resources/store_products.dart'
    show StoreProductOrderBy, StoreProducts;
export 'src/store/session.dart'
    show CartSession, CartTokenStore, InMemoryCartTokenStore;
export 'src/store/store.dart' show StoreBatchRequest, WooStore;
export 'src/transport.dart' show WooRetry;
export 'src/webhooks.dart' show WooWebhookDelivery;
