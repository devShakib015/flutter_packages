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
  factory Schema.string({String? description}) =>
      Schema._(<String, Object?>{'type': 'string', 'description': description});

  /// A whole number.
  factory Schema.integer({String? description}) => Schema._(<String, Object?>{
    'type': 'integer',
    'description': description,
  });

  /// A decimal number.
  factory Schema.number({String? description}) =>
      Schema._(<String, Object?>{'type': 'number', 'description': description});

  /// A boolean.
  factory Schema.boolean({String? description}) => Schema._(<String, Object?>{
    'type': 'boolean',
    'description': description,
  });

  /// One of a fixed set of strings.
  ///
  /// Stronger than a described string: the model cannot invent a value outside
  /// [values], which is what makes it reliable for classification.
  factory Schema.oneOf(List<String> values, {String? description}) {
    assert(values.isNotEmpty, 'Schema.oneOf needs at least one value');
    return Schema._(<String, Object?>{
      'type': 'enum',
      'values': List<String>.unmodifiable(values),
      'description': description,
    });
  }

  /// A list of [items].
  factory Schema.array(
    Schema items, {
    int? minItems,
    int? maxItems,
    String? description,
  }) {
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

  /// Wire representation, with nulls stripped.
  Map<String, Object?> toJson() => <String, Object?>{
    for (final MapEntry<String, Object?> e in _json.entries)
      if (e.value != null) e.key: e.value,
  };

  @override
  String toString() => 'Schema(${_json['type']})';
}
