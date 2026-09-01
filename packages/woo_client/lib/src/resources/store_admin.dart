import '../client.dart';
import '../models/catalog.dart';
import '../page.dart';
import 'collection.dart';

/// Sales figures, as WooCommerce computes them.
///
/// Reports are returned as maps rather than typed models on purpose: their
/// shape depends on which report, which period, and which plugins are
/// installed, and a typed model would be a promise this package cannot keep.
class WooReports {
  /// Wraps [_client]'s report routes.
  WooReports(this._client);

  final WooCommerce _client;

  /// Headline counts: products, orders, customers, reviews, coupons.
  Future<List<Map<String, Object?>>> totals(String what) async =>
      (await _client.getPage('/reports/$what/totals', perPage: 100)).items;

  /// Sales over a period.
  ///
  /// Give either [period] (`week`, `month`, `last_month`, `year`) or a
  /// [dateMin]/[dateMax] pair.
  Future<List<Map<String, Object?>>> sales({
    String? period,
    DateTime? dateMin,
    DateTime? dateMax,
  }) async => (await _client.getPage(
    '/reports/sales',
    perPage: 100,
    query: <String, Object?>{
      'period': ?period,
      'date_min': ?dateMin?.toIso8601String().split('T').first,
      'date_max': ?dateMax?.toIso8601String().split('T').first,
    },
  )).items;

  /// Best-selling products over a period.
  Future<List<Map<String, Object?>>> topSellers({
    String period = 'week',
  }) async => (await _client.getPage(
    '/reports/top_sellers',
    perPage: 100,
    query: <String, Object?>{'period': period},
  )).items;

  /// Which reports this store offers.
  Future<List<Map<String, Object?>>> available() async =>
      (await _client.getPage('/reports', perPage: 100)).items;
}

/// The store's own settings.
class WooSettings {
  /// Wraps [_client]'s settings routes.
  WooSettings(this._client);

  final WooCommerce _client;

  /// The setting groups, such as `general`, `products`, `tax`.
  Future<List<Map<String, Object?>>> groups() async =>
      (await _client.getPage('/settings', perPage: 100)).items;

  /// Every option in one group.
  Future<List<Map<String, Object?>>> options(String group) async =>
      (await _client.getPage('/settings/$group', perPage: 100)).items;

  /// One option.
  Future<Map<String, Object?>> option(String group, String id) =>
      _client.getOne('/settings/$group/$id');

  /// Changes one option.
  Future<Map<String, Object?>> update(String group, String id, Object? value) =>
      _client.put('/settings/$group/$id', <String, Object?>{'value': value});

  /// The store's currency code, such as `GBP`.
  ///
  /// A shortcut for the option everyone looks up first.
  Future<String> currency() async =>
      '${(await option('general', 'woocommerce_currency'))['value'] ?? ''}';
}

/// Reference data WooCommerce publishes: countries, currencies, continents.
///
/// Useful for building an address form that matches the store's own — the
/// states of a country, and what its address fields are called, come from
/// here rather than from a list you maintain.
class WooData {
  /// Wraps [_client]'s data routes.
  WooData(this._client);

  final WooCommerce _client;

  /// Every country, with its states.
  Future<List<Map<String, Object?>>> countries() async =>
      (await _client.getPage('/data/countries', perPage: 100)).items;

  /// One country and its states, by two-letter code.
  Future<Map<String, Object?>> country(String code) =>
      _client.getOne('/data/countries/${code.toUpperCase()}');

  /// Every currency WooCommerce knows.
  Future<List<Map<String, Object?>>> currencies() async =>
      (await _client.getPage('/data/currencies', perPage: 200)).items;

  /// The store's own currency, with its symbol and position.
  Future<Map<String, Object?>> currentCurrency() =>
      _client.getOne('/data/currencies/current');

  /// Continents, with the countries in each.
  Future<List<Map<String, Object?>>> continents() async =>
      (await _client.getPage('/data/continents', perPage: 100)).items;
}

/// Shipping zones and what they cost.
class WooShippingZones {
  /// Wraps [_client]'s shipping zone routes.
  WooShippingZones(this._client);

  final WooCommerce _client;

  /// Every zone.
  Future<List<Map<String, Object?>>> list() async =>
      (await _client.getPage('/shipping/zones', perPage: 100)).items;

  /// One zone.
  Future<Map<String, Object?>> get(int id) =>
      _client.getOne('/shipping/zones/$id');

  /// Creates a zone.
  Future<Map<String, Object?>> create(Map<String, Object?> fields) =>
      _client.post('/shipping/zones', fields);

  /// Updates a zone.
  Future<Map<String, Object?>> update(int id, Map<String, Object?> fields) =>
      _client.put('/shipping/zones/$id', fields);

  /// Deletes a zone.
  Future<Map<String, Object?>> delete(int id) =>
      _client.delete('/shipping/zones/$id', force: true);

  /// Where a zone applies — countries, states, postcodes.
  Future<List<Map<String, Object?>>> locations(int zoneId) async =>
      (await _client.getPage(
        '/shipping/zones/$zoneId/locations',
        perPage: 100,
      )).items;

  /// Replaces a zone's locations wholesale.
  ///
  /// WooCommerce has no "add one location" route; a PUT sets the whole list.
  Future<List<Map<String, Object?>>> setLocations(
    int zoneId,
    List<Map<String, Object?>> locations,
  ) => _client.putList('/shipping/zones/$zoneId/locations', locations);

  /// The methods available in a zone, with their settings and costs.
  Future<List<Map<String, Object?>>> methods(int zoneId) async =>
      (await _client.getPage(
        '/shipping/zones/$zoneId/methods',
        perPage: 100,
      )).items;

  /// Adds a method to a zone.
  Future<Map<String, Object?>> addMethod(
    int zoneId, {
    required String methodId,
    Map<String, Object?> settings = const <String, Object?>{},
  }) => _client.post('/shipping/zones/$zoneId/methods', <String, Object?>{
    'method_id': methodId,
    if (settings.isNotEmpty) 'settings': settings,
  });
}

/// Everything else the admin API exposes, grouped.
///
/// Internal wiring for [WooCommerce]; you reach these through the client.
class WooAdminResources {
  /// Creates the group.
  WooAdminResources(WooCommerce client)
    : productCategories = WooCollection<WooCategory>(
        client,
        '/products/categories',
        WooCategory.fromJson,
      ),
      productTags = WooCollection<WooTag>(
        client,
        '/products/tags',
        WooTag.fromJson,
      ),
      productAttributes = WooCollection<WooAttribute>(
        client,
        '/products/attributes',
        WooAttribute.fromJson,
      ),
      reviews = WooCollection<WooReview>(
        client,
        '/products/reviews',
        WooReview.fromJson,
      ),
      shippingClasses = WooCollection<WooShippingClass>(
        client,
        '/products/shipping_classes',
        WooShippingClass.fromJson,
      ),
      taxRates = WooCollection<WooTaxRate>(
        client,
        '/taxes',
        WooTaxRate.fromJson,
      ),
      webhooks = WooCollection<WooWebhook>(
        client,
        '/webhooks',
        WooWebhook.fromJson,
      ),
      reports = WooReports(client),
      settings = WooSettings(client),
      data = WooData(client),
      shippingZones = WooShippingZones(client),
      _client = client;

  final WooCommerce _client;

  /// Product categories.
  final WooCollection<WooCategory> productCategories;

  /// Product tags.
  final WooCollection<WooTag> productTags;

  /// Global product attributes.
  final WooCollection<WooAttribute> productAttributes;

  /// Product reviews.
  final WooCollection<WooReview> reviews;

  /// Shipping classes.
  final WooCollection<WooShippingClass> shippingClasses;

  /// Tax rates.
  final WooCollection<WooTaxRate> taxRates;

  /// Webhooks.
  final WooCollection<WooWebhook> webhooks;

  /// Sales reports.
  final WooReports reports;

  /// Store settings.
  final WooSettings settings;

  /// Countries, currencies, continents.
  final WooData data;

  /// Shipping zones, their locations, and their methods.
  final WooShippingZones shippingZones;

  /// The values one attribute can take.
  WooCollection<WooAttributeTerm> attributeTerms(int attributeId) =>
      WooCollection<WooAttributeTerm>(
        _client,
        '/products/attributes/$attributeId/terms',
        WooAttributeTerm.fromJson,
      );

  /// The notes on one order.
  WooCollection<WooOrderNote> orderNotes(int orderId) =>
      WooCollection<WooOrderNote>(
        _client,
        '/orders/$orderId/notes',
        WooOrderNote.fromJson,
      );

  /// The refunds against one order.
  WooCollection<WooRefund> refunds(int orderId) => WooCollection<WooRefund>(
    _client,
    '/orders/$orderId/refunds',
    WooRefund.fromJson,
  );

  /// The tax classes the store defines.
  Future<List<Map<String, Object?>>> taxClasses() async =>
      (await _client.getPage('/taxes/classes', perPage: 100)).items;

  /// The payment gateways the store has, with their settings.
  Future<List<WooPaymentGateway>> paymentGateways() async {
    final WooPage<Map<String, Object?>> page = await _client.getPage(
      '/payment_gateways',
      perPage: 100,
    );
    return page.items.map(WooPaymentGateway.fromJson).toList(growable: false);
  }

  /// One payment gateway.
  Future<WooPaymentGateway> paymentGateway(String id) async =>
      WooPaymentGateway.fromJson(await _client.getOne('/payment_gateways/$id'));

  /// The store's system status: versions, environment, active plugins.
  ///
  /// The first thing to ask for when a store is behaving oddly.
  Future<Map<String, Object?>> systemStatus() =>
      _client.getOne('/system_status');
}
