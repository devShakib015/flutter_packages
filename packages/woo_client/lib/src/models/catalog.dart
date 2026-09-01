import '../json.dart';
import 'money.dart';

/// A product category.
class WooCategory {
  /// Creates a category.
  const WooCategory({
    required this.id,
    required this.name,
    required this.raw,
    this.slug = '',
    this.parent = 0,
    this.description = '',
    this.display = '',
    this.imageSrc = '',
    this.menuOrder = 0,
    this.count = 0,
  });

  /// Reads WooCommerce's representation.
  factory WooCategory.fromJson(Map<String, Object?> json) => WooCategory(
    id: readInt(json['id'], orElse: 0),
    name: readString(json['name']),
    slug: readString(json['slug']),
    parent: readInt(json['parent'], orElse: 0),
    description: readString(json['description']),
    display: readString(json['display']),
    imageSrc: switch (json['image']) {
      final Map<String, Object?> i => readString(i['src']),
      _ => '',
    },
    menuOrder: readInt(json['menu_order'], orElse: 0),
    count: readInt(json['count'], orElse: 0),
    raw: json,
  );

  /// Category id.
  final int id;

  /// Display name.
  final String name;

  /// URL slug.
  final String slug;

  /// The parent category, or 0 at the top level.
  final int parent;

  /// Description, as HTML.
  final String description;

  /// `default`, `products`, `subcategories`, or `both`.
  final String display;

  /// The category image, or empty.
  final String imageSrc;

  /// Where the store owner placed it.
  final int menuOrder;

  /// How many published products are in it.
  final int count;

  /// The whole category as the store sent it.
  final Map<String, Object?> raw;

  /// Whether this is a top-level category.
  bool get isTopLevel => parent == 0;

  @override
  String toString() => name;
}

/// A product tag.
class WooTag {
  /// Creates a tag.
  const WooTag({
    required this.id,
    required this.name,
    required this.raw,
    this.slug = '',
    this.description = '',
    this.count = 0,
  });

  /// Reads WooCommerce's representation.
  factory WooTag.fromJson(Map<String, Object?> json) => WooTag(
    id: readInt(json['id'], orElse: 0),
    name: readString(json['name']),
    slug: readString(json['slug']),
    description: readString(json['description']),
    count: readInt(json['count'], orElse: 0),
    raw: json,
  );

  /// Tag id.
  final int id;

  /// Display name.
  final String name;

  /// URL slug.
  final String slug;

  /// Description.
  final String description;

  /// How many published products carry it.
  final int count;

  /// The whole tag as the store sent it.
  final Map<String, Object?> raw;

  @override
  String toString() => name;
}

/// A global product attribute, such as Colour or Size.
class WooAttribute {
  /// Creates an attribute.
  const WooAttribute({
    required this.id,
    required this.name,
    required this.raw,
    this.slug = '',
    this.type = 'select',
    this.orderBy = 'menu_order',
    this.hasArchives = false,
  });

  /// Reads WooCommerce's representation.
  factory WooAttribute.fromJson(Map<String, Object?> json) => WooAttribute(
    id: readInt(json['id'], orElse: 0),
    name: readString(json['name']),
    slug: readString(json['slug']),
    type: readStringOr(json['type'], 'select'),
    orderBy: readStringOr(json['order_by'], 'menu_order'),
    hasArchives: readBool(json['has_archives']),
    raw: json,
  );

  /// Attribute id.
  final int id;

  /// Display name.
  final String name;

  /// The slug, which becomes the `pa_…` taxonomy.
  final String slug;

  /// `select` or `text`.
  final String type;

  /// How its terms are sorted.
  final String orderBy;

  /// Whether it has archive pages.
  final bool hasArchives;

  /// The whole attribute as the store sent it.
  final Map<String, Object?> raw;

  /// The taxonomy name, which is what a product carries.
  String get taxonomy => slug.startsWith('pa_') ? slug : 'pa_$slug';

  @override
  String toString() => name;
}

/// One value an attribute can take.
class WooAttributeTerm {
  /// Creates a term.
  const WooAttributeTerm({
    required this.id,
    required this.name,
    required this.raw,
    this.slug = '',
    this.description = '',
    this.menuOrder = 0,
    this.count = 0,
  });

  /// Reads WooCommerce's representation.
  factory WooAttributeTerm.fromJson(Map<String, Object?> json) =>
      WooAttributeTerm(
        id: readInt(json['id'], orElse: 0),
        name: readString(json['name']),
        slug: readString(json['slug']),
        description: readString(json['description']),
        menuOrder: readInt(json['menu_order'], orElse: 0),
        count: readInt(json['count'], orElse: 0),
        raw: json,
      );

  /// Term id.
  final int id;

  /// Display name, such as `Blue`.
  final String name;

  /// URL slug.
  final String slug;

  /// Description.
  final String description;

  /// Where the store owner placed it.
  final int menuOrder;

  /// How many products use it.
  final int count;

  /// The whole term as the store sent it.
  final Map<String, Object?> raw;

  @override
  String toString() => name;
}

/// A customer's review of a product.
class WooReview {
  /// Creates a review.
  const WooReview({
    required this.id,
    required this.productId,
    required this.rating,
    required this.review,
    required this.raw,
    this.status = 'approved',
    this.reviewer = '',
    this.reviewerEmail = '',
    this.reviewerAvatar = '',
    this.verified = false,
    this.dateCreated,
  });

  /// Reads WooCommerce's representation.
  factory WooReview.fromJson(Map<String, Object?> json) => WooReview(
    id: readInt(json['id'], orElse: 0),
    productId: readInt(json['product_id'], orElse: 0),
    rating: readInt(json['rating'], orElse: 0),
    review: readString(json['review']),
    // Not defaulted: an absent moderation state must not read as
    // approved, or a held review renders as a published one.
    status: readString(json['status']),
    reviewer: readString(json['reviewer']),
    reviewerEmail: readString(json['reviewer_email']),
    reviewerAvatar: switch (json['reviewer_avatar_urls']) {
      final Map<String, Object?> a =>
        '${a['96'] ?? a.values.firstOrNull ?? ''}',
      _ => '',
    },
    verified: readBool(json['verified']),
    dateCreated: readDate(json['date_created']),
    raw: json,
  );

  /// Review id.
  final int id;

  /// The product reviewed.
  final int productId;

  /// One to five.
  final int rating;

  /// The text, as HTML.
  final String review;

  /// `approved`, `hold`, `spam`, `unspam`, `trash`, or `untrash`.
  final String status;

  /// Who wrote it.
  final String reviewer;

  /// Their email. Only present to an authenticated admin.
  final String reviewerEmail;

  /// A Gravatar URL for them.
  final String reviewerAvatar;

  /// Whether they actually bought the product.
  final bool verified;

  /// When it was written.
  final DateTime? dateCreated;

  /// The whole review as the store sent it.
  final Map<String, Object?> raw;

  /// Whether it is publicly visible.
  bool get isApproved => status == 'approved';
}

/// A shipping class, which lets rates differ per product group.
class WooShippingClass {
  /// Creates a shipping class.
  const WooShippingClass({
    required this.id,
    required this.name,
    required this.raw,
    this.slug = '',
    this.description = '',
    this.count = 0,
  });

  /// Reads WooCommerce's representation.
  factory WooShippingClass.fromJson(Map<String, Object?> json) =>
      WooShippingClass(
        id: readInt(json['id'], orElse: 0),
        name: readString(json['name']),
        slug: readString(json['slug']),
        description: readString(json['description']),
        count: readInt(json['count'], orElse: 0),
        raw: json,
      );

  /// Class id.
  final int id;

  /// Display name.
  final String name;

  /// URL slug.
  final String slug;

  /// Description.
  final String description;

  /// How many products are in it.
  final int count;

  /// The whole class as the store sent it.
  final Map<String, Object?> raw;

  @override
  String toString() => name;
}

/// A note attached to an order.
class WooOrderNote {
  /// Creates a note.
  const WooOrderNote({
    required this.id,
    required this.note,
    required this.raw,
    this.author = '',
    this.customerNote = false,
    this.dateCreated,
  });

  /// Reads WooCommerce's representation.
  factory WooOrderNote.fromJson(Map<String, Object?> json) => WooOrderNote(
    id: readInt(json['id'], orElse: 0),
    note: readString(json['note']),
    author: readString(json['author']),
    customerNote: readBool(json['customer_note']),
    dateCreated: readDate(json['date_created']),
    raw: json,
  );

  /// Note id.
  final int id;

  /// The text.
  final String note;

  /// Who wrote it, or `system`.
  final String author;

  /// Whether the customer was emailed it. False means it is internal.
  final bool customerNote;

  /// When it was written.
  final DateTime? dateCreated;

  /// The whole note as the store sent it.
  final Map<String, Object?> raw;

  /// Whether only staff can see this.
  bool get isPrivate => !customerNote;
}

/// Money given back on an order.
class WooRefund {
  /// Creates a refund.
  const WooRefund({
    required this.id,
    required this.amount,
    required this.raw,
    this.reason = '',
    this.refundedBy = 0,
    this.dateCreated,
  });

  /// Reads WooCommerce's representation.
  factory WooRefund.fromJson(Map<String, Object?> json) => WooRefund(
    id: readInt(json['id'], orElse: 0),
    amount: WooPrice(readString(json['amount'])),
    reason: readString(json['reason']),
    refundedBy: readInt(json['refunded_by'], orElse: 0),
    dateCreated: readDate(json['date_created']),
    raw: json,
  );

  /// Refund id.
  final int id;

  /// How much went back.
  final WooPrice amount;

  /// Why, when someone said.
  final String reason;

  /// The user who issued it.
  final int refundedBy;

  /// When.
  final DateTime? dateCreated;

  /// The whole refund as the store sent it.
  final Map<String, Object?> raw;
}

/// A tax rate.
class WooTaxRate {
  /// Creates a tax rate.
  const WooTaxRate({
    required this.id,
    required this.rate,
    required this.name,
    required this.raw,
    this.country = '',
    this.state = '',
    this.postcode = '',
    this.city = '',
    this.priority = 1,
    this.compound = false,
    this.shipping = true,
    this.taxClass = '',
  });

  /// Reads WooCommerce's representation.
  factory WooTaxRate.fromJson(Map<String, Object?> json) => WooTaxRate(
    id: readInt(json['id'], orElse: 0),
    rate: readDouble(json['rate']),
    name: readString(json['name']),
    country: readString(json['country']),
    state: readString(json['state']),
    postcode: readString(json['postcode']),
    city: readString(json['city']),
    priority: readInt(json['priority'], orElse: 1),
    compound: readBool(json['compound']),
    shipping: readBool(json['shipping'], orElse: true),
    taxClass: readString(json['class']),
    raw: json,
  );

  /// Rate id.
  final int id;

  /// The percentage, as a number — `20.0` for twenty percent.
  final double rate;

  /// What to call it on an invoice, such as `VAT`.
  final String name;

  /// Two-letter country code, or empty for everywhere.
  final String country;

  /// State code, or empty.
  final String state;

  /// Postcode, or empty.
  final String postcode;

  /// City, or empty.
  final String city;

  /// Which rate wins when several match; lower goes first.
  final int priority;

  /// Whether it applies on top of other taxes.
  final bool compound;

  /// Whether shipping is taxed at this rate.
  final bool shipping;

  /// The tax class, empty for standard.
  final String taxClass;

  /// The whole rate as the store sent it.
  final Map<String, Object?> raw;

  @override
  String toString() => '$name $rate%';
}

/// A payment gateway the store has configured.
class WooPaymentGateway {
  /// Creates a gateway.
  const WooPaymentGateway({
    required this.id,
    required this.title,
    required this.enabled,
    required this.raw,
    this.description = '',
    this.methodTitle = '',
    this.methodDescription = '',
    this.order = 0,
  });

  /// Reads WooCommerce's representation.
  factory WooPaymentGateway.fromJson(Map<String, Object?> json) =>
      WooPaymentGateway(
        id: readString(json['id']),
        title: readString(json['title']),
        description: readString(json['description']),
        methodTitle: readString(json['method_title']),
        methodDescription: readString(json['method_description']),
        order: readInt(json['order'], orElse: 0),
        enabled: readBool(json['enabled']),
        raw: json,
      );

  /// The id to send as an order's `payment_method`, such as `cod`.
  final String id;

  /// What the shopper sees at checkout.
  final String title;

  /// The longer text under it.
  final String description;

  /// What the store owner sees in settings.
  final String methodTitle;

  /// The admin description.
  final String methodDescription;

  /// Where it sits in the checkout list.
  final int order;

  /// Whether it is switched on.
  final bool enabled;

  /// The whole gateway as the store sent it, including its settings.
  final Map<String, Object?> raw;

  @override
  String toString() => '$id ($title)';
}

/// A webhook the store will call.
class WooWebhook {
  /// Creates a webhook.
  const WooWebhook({
    required this.id,
    required this.topic,
    required this.deliveryUrl,
    required this.raw,
    this.name = '',
    this.status = 'active',
    this.resource = '',
    this.event = '',
    this.secret = '',
    this.dateCreated,
  });

  /// Reads WooCommerce's representation.
  factory WooWebhook.fromJson(Map<String, Object?> json) => WooWebhook(
    id: readInt(json['id'], orElse: 0),
    name: readString(json['name']),
    // Not defaulted, for the same reason: an unknown state must not
    // read as one that will fire.
    status: readString(json['status']),
    topic: readString(json['topic']),
    resource: readString(json['resource']),
    event: readString(json['event']),
    deliveryUrl: readString(json['delivery_url']),
    secret: readString(json['secret']),
    dateCreated: readDate(json['date_created']),
    raw: json,
  );

  /// Webhook id.
  final int id;

  /// A label.
  final String name;

  /// `active`, `paused`, or `disabled`.
  final String status;

  /// What fires it, such as `order.created`.
  final String topic;

  /// The resource half of [topic].
  final String resource;

  /// The event half of [topic].
  final String event;

  /// Where the store will POST.
  final String deliveryUrl;

  /// The signing secret. Only returned when the webhook is created.
  final String secret;

  /// When it was made.
  final DateTime? dateCreated;

  /// The whole webhook as the store sent it.
  final Map<String, Object?> raw;

  /// Whether it will fire.
  bool get isActive => status == 'active';

  @override
  String toString() => '$topic -> $deliveryUrl';
}
