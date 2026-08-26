import 'dart:async';

import 'package:flutter/foundation.dart';

import 'schema.dart';

/// Runs a tool the model asked for and returns text to feed back to it.
///
/// [arguments] arrive already conforming to the tool's declared schema, so
/// they can be read without defensive checks on shape.
typedef ToolHandler = FutureOr<String> Function(Map<String, Object?> arguments);

/// A Dart function the model may call mid-generation.
///
/// The model decides when to call it, generation suspends while your handler
/// runs, and the returned text is fed back so the model can continue. That
/// round trip is what lets an on-device model reach live data it was never
/// trained on:
///
/// ```dart
/// LanguageModelTool(
///   name: 'getWeather',
///   description: 'Current weather for a city. Call this rather than guessing.',
///   parameters: Schema.object({'city': Schema.string()}),
///   handler: (args) async => await weatherApi.summary(args['city']! as String),
/// )
/// ```
///
/// Write [description] for the model, not for other developers: it is the only
/// thing deciding whether the tool gets called at the right moment. Saying
/// when *not* to call it helps as much as saying when to.
@immutable
class LanguageModelTool {
  /// Defines a tool.
  const LanguageModelTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.handler,
  });

  /// Identifier the model uses to call it. Keep it short and verb-like.
  final String name;

  /// What it does and when to use it, written for the model to read.
  final String description;

  /// Shape of the arguments. The model cannot pass anything that does not fit.
  final Schema parameters;

  /// Invoked when the model calls the tool.
  ///
  /// Throwing surfaces as a `ToolCallException` on the awaiting request, and
  /// the model is told the tool failed.
  final ToolHandler handler;

  /// Wire representation. The handler stays on the Dart side.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'description': description,
    'parameters': parameters.toJson(),
  };

  @override
  String toString() => 'LanguageModelTool($name)';
}
