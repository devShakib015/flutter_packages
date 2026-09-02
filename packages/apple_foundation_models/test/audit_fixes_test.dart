// Each test pins a defect found by the 2026-09-02 audit.
import 'package:apple_foundation_models/apple_foundation_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generated type names are unique within a schema', () {
    test('two enum fields no longer both become "Choice"', () {
      // Shipped in 0.2.1: the native side mints one Swift type per node and
      // defaults every unnamed enum to "Choice", so a schema with two enum
      // fields declared the same type twice and was rejected at runtime —
      // and a classification schema, which is what enums are for, usually has
      // more than one.
      final Schema schema = Schema.object(<String, Schema>{
        'priority': Schema.oneOf(<String>['low', 'high']),
        'category': Schema.oneOf(<String>['bug', 'feature']),
      }, name: 'Ticket');

      final List<String> names = _typeNames(schema.toJson());
      expect(names.toSet().length, names.length, reason: 'no duplicates');
      expect(names, containsAll(<String>['Ticket', 'Choice', 'Choice2']));
    });

    test('an explicit name is honoured', () {
      final Schema schema = Schema.object(<String, Schema>{
        'priority': Schema.oneOf(<String>['low'], name: 'Priority'),
        'category': Schema.oneOf(<String>['bug']),
      }, name: 'Ticket');
      expect(
        _typeNames(schema.toJson()),
        containsAll(<String>['Ticket', 'Priority', 'Choice']),
      );
    });

    test('nested unnamed objects are distinguished too', () {
      final Schema schema = Schema.object(<String, Schema>{
        'billing': Schema.object(<String, Schema>{'city': Schema.string()}),
        'shipping': Schema.object(<String, Schema>{'city': Schema.string()}),
      }, name: 'Order');
      final List<String> names = _typeNames(schema.toJson());
      expect(names.toSet().length, names.length);
      expect(names, containsAll(<String>['Order', 'Result', 'Result2']));
    });

    test('a property called "name" is not mistaken for a type name', () {
      final Schema schema = Schema.object(<String, Schema>{
        'name': Schema.string(),
      }, name: 'Person');
      expect(_typeNames(schema.toJson()), <String>['Person']);
    });

    test('an enum inside an array is named too', () {
      final Schema schema = Schema.object(<String, Schema>{
        'tags': Schema.array(Schema.oneOf(<String>['a', 'b'])),
        'state': Schema.oneOf(<String>['draft', 'live']),
      }, name: 'Post');
      final List<String> names = _typeNames(schema.toJson());
      expect(names.toSet().length, names.length);
    });
  });
}

/// Every type name the wire form declares, in encounter order.
List<String> _typeNames(Object? node) {
  final List<String> out = <String>[];
  void walk(Object? n) {
    if (n is List<Object?>) {
      for (final Object? e in n) {
        walk(e);
      }
      return;
    }
    if (n is! Map<String, Object?>) return;
    final String? type = n['type'] as String?;
    if (type == 'enum' || type == 'object') {
      out.add(n['name']! as String);
    }
    for (final MapEntry<String, Object?> e in n.entries) {
      if (e.key == 'name') continue;
      walk(e.value);
    }
  }

  walk(node);
  return out;
}
