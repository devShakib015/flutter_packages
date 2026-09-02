import 'package:flutter/foundation.dart';

/// A description of the shape you want the model to produce.
///
/// Swift's `@Generable` macro runs at compile time, so it can never see a type
/// declared in Dart. This is the way round that: the schema is described as
/// data, rebuilt natively as a `DynamicGenerationSchema`, and used to
/// constrain generation. The model is then structurally unable to return
/// something that does not fit.
///
/// ```dart
/// final recipe = Schema.object(
///   name: 'Recipe',
///   {
///     'name': Schema.string(description: 'dish name'),
///     'minutes': Schema.integer(description: 'total cook time'),
///     'steps': Schema.array(Schema.string(), maxItems: 5),
///     'vegetarian': Schema.boolean(),
///   },
/// );
///
/// final json = await session.respondAs('A simple pasta dish.', schema: recipe);
/// ```
///
/// This is a generation constraint, not a validator: it shapes what the model
/// may emit rather than checking what it did.
@immutable
class Schema {
  const Schema._(this._json);

  /// A string value.
  ///
  /// [pattern] is a regular expression the output must match. It constrains
  /// generation rather than validating afterwards, so the model cannot produce
  /// a value that fails it.
  factory Schema.string({String? description, String? pattern}) =>
      Schema._(<String, Object?>{
        'type': 'string',
        'description': description,
        'pattern': pattern,
      });

  /// A whole number, optionally bounded.
  ///
  /// Bounds are enforced during generation, which is the difference between
  /// asking for a 1-to-5 rating and actually getting one:
  ///
  /// ```dart
  /// Schema.integer(min: 1, max: 5, description: 'severity')
  /// ```
  factory Schema.integer({String? description, int? min, int? max}) {
    assert(min == null || max == null || min <= max, 'min must not exceed max');
    return Schema._(<String, Object?>{
      'type': 'integer',
      'description': description,
      'minimum': min,
      'maximum': max,
    });
  }

  /// A decimal number, optionally bounded.
  factory Schema.number({String? description, double? min, double? max}) {
    assert(min == null || max == null || min <= max, 'min must not exceed max');
    return Schema._(<String, Object?>{
      'type': 'number',
      'description': description,
      'minimum': min,
      'maximum': max,
    });
  }

  /// A boolean.
  factory Schema.boolean({String? description}) => Schema._(<String, Object?>{
    'type': 'boolean',
    'description': description,
  });

  /// One of a fixed set of strings.
  ///
  /// Stronger than a described string: the model cannot invent a value outside
  /// [values], which is what makes it reliable for classification.
  /// Pass [name] when a schema has more than one enum field. The native side
  /// mints a type per enum, and every unnamed one used to be called `Choice` —
  /// so a schema with two enum fields declared the same type twice and was
  /// rejected at runtime, which is exactly the shape a classification schema
  /// tends to have.
  factory Schema.oneOf(
    List<String> values, {
    String? description,
    String? name,
  }) {
    assert(values.isNotEmpty, 'Schema.oneOf needs at least one value');
    return Schema._(<String, Object?>{
      'type': 'enum',
      'values': List<String>.unmodifiable(values),
      'description': description,
      'name': ?name,
    });
  }

  /// A list of [items].
  ///
  /// Pass [exactItems] to demand a precise length, or [minItems] and
  /// [maxItems] for a range. Bounds are enforced during generation.
  factory Schema.array(
    Schema items, {
    int? minItems,
    int? maxItems,
    int? exactItems,
    String? description,
  }) {
    assert(
      exactItems == null || (minItems == null && maxItems == null),
      'exactItems cannot be combined with minItems or maxItems',
    );
    if (exactItems != null) {
      minItems = exactItems;
      maxItems = exactItems;
    }
    assert(
      minItems == null || maxItems == null || minItems <= maxItems,
      'minItems must not exceed maxItems',
    );
    return Schema._(<String, Object?>{
      'type': 'array',
      'items': items.toJson(),
      'minItems': minItems,
      'maxItems': maxItems,
      'description': description,
    });
  }

  /// An object with named [properties].
  ///
  /// Names in [optional] may be omitted by the model; everything else is
  /// required. [name] is shown to the model and is worth setting — it is a
  /// meaningful hint about what is being produced.
  factory Schema.object(
    Map<String, Schema> properties, {
    String name = 'Result',
    String? description,
    Set<String> optional = const <String>{},
  }) {
    assert(properties.isNotEmpty, 'Schema.object needs at least one property');
    assert(
      optional.every(properties.containsKey),
      'optional names must all appear in properties',
    );
    return Schema._(<String, Object?>{
      'type': 'object',
      'name': name,
      'description': description,
      'properties': <Map<String, Object?>>[
        for (final MapEntry<String, Schema> e in properties.entries)
          <String, Object?>{
            'name': e.key,
            'schema': e.value.toJson(),
            'isOptional': optional.contains(e.key),
          },
      ],
    });
  }

  final Map<String, Object?> _json;

  /// Wire representation, with nulls stripped and generated type names made
  /// unique.
  Map<String, Object?> toJson() =>
      _uniquify(_strip(_json), <String>{}) as Map<String, Object?>;

  static Map<String, Object?> _strip(Map<String, Object?> json) =>
      <String, Object?>{
        for (final MapEntry<String, Object?> e in json.entries)
          if (e.value != null)
            e.key: e.value is Schema ? (e.value! as Schema).toJson() : e.value,
      };

  /// Gives every enum and object node a name unique within one schema.
  ///
  /// The native side mints one Swift type per node, defaulting every unnamed
  /// enum to `Choice` and every unnamed object to `Result`. A schema with two
  /// enum fields therefore declared `Choice` twice and was rejected at
  /// runtime — and a classification schema, which is what enums are for,
  /// usually has more than one. Names are minted here so a caller only passes
  /// `name:` when they want a particular one.
  static Object? _uniquify(Object? node, Set<String> taken) {
    if (node is List<Object?>) {
      return <Object?>[for (final Object? e in node) _uniquify(e, taken)];
    }
    if (node is! Map<String, Object?>) return node;

    final Map<String, Object?> out = Map<String, Object?>.of(node);
    final String? type = out['type'] as String?;

    // Named before descending, so the outermost node keeps the plain name and
    // a nested one takes the suffix.
    if (type == 'enum' || type == 'object') {
      final String base =
          (out['name'] as String?) ?? (type == 'enum' ? 'Choice' : 'Result');
      String candidate = base;
      int n = 2;
      while (!taken.add(candidate)) {
        candidate = '$base$n';
        n++;
      }
      out['name'] = candidate;
    }

    for (final MapEntry<String, Object?> e in node.entries) {
      // A property's own 'name' is a field name, not a type name, so only the
      // nested 'schema' is descended into.
      if (e.key == 'name') continue;
      out[e.key] = _uniquify(e.value, taken);
    }
    return out;
  }

  @override
  String toString() => 'Schema(${_json['type']})';
}
