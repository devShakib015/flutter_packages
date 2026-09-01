/// A typed WooCommerce REST v3 client for Dart.
///
/// ```dart
/// final woo = WooCommerce(
///   baseUrl: 'https://shop.example.com',
///   credentials: const WooCredentials.key(
///     consumerKey: 'ck_…',
///     consumerSecret: 'cs_…',
///   ),
/// );
///
/// final page = await woo.products.list(perPage: 20, onSale: true);
/// for (final product in page.items) {
///   print('${product.name} — ${product.price}');
/// }
/// woo.close();
/// ```
///
/// Not affiliated with or endorsed by Automattic. WooCommerce is their
/// trademark; this is an independent client for their public REST API.
library;

export 'src/client.dart' show WooCommerce;
export 'src/credentials.dart'
    show BearerCredentials, KeyCredentials, NoCredentials, WooCredentials;
export 'src/exceptions.dart'
    show
        WooAuthException,
        WooBadResponseException,
        WooException,
        WooInvalidRequestException,
        WooNetworkException,
        WooNotFoundException,
        WooServerException;
export 'src/models/coupon.dart' show WooCoupon, WooDiscountType;
export 'src/models/customer.dart' show WooCustomer;
export 'src/models/money.dart' show WooPrice;
export 'src/models/order.dart'
    show WooAddress, WooLineItem, WooOrder, WooOrderStatus;
export 'src/models/product.dart'
    show WooImage, WooProduct, WooProductType, WooStockStatus, WooTerm;
export 'src/page.dart' show WooPage;
export 'src/resources/coupons.dart' show WooCoupons;
export 'src/resources/customers.dart' show WooCustomers;
export 'src/resources/orders.dart' show WooOrders;
export 'src/resources/products.dart' show WooProductOrderBy, WooProducts;
