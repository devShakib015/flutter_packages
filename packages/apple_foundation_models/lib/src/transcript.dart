import 'package:flutter/foundation.dart';

/// Who produced a transcript entry.
enum TranscriptRole {
  /// The session's standing instructions.
  instructions,

  /// Something the app sent.
  prompt,

  /// Something the model produced.
  response,

  /// The model asking for a tool to run.
  toolCall,

  /// What the tool returned.
  toolOutput,

  /// An entry this version does not recognise.
  unknown,
}

/// One turn in a session's history.
///
/// The transcript is what the model sees on each request, so it is also what
/// consumes the context window — inspect it when diagnosing a
/// `ContextWindowExceededException`.
@immutable
class TranscriptEntry {
  /// Creates an entry.
  const TranscriptEntry({required this.role, required this.text});

  /// Who produced it.
  final TranscriptRole role;

  /// Its text content.
  final String text;

  /// Reads an entry off the platform channel.
  factory TranscriptEntry.fromJson(Map<String, Object?> json) {
    final String raw = json['role'] as String? ?? '';
    return TranscriptEntry(
      role: TranscriptRole.values.firstWhere(
        (TranscriptRole r) => r.name == raw,
        orElse: () => TranscriptRole.unknown,
      ),
      text: json['text'] as String? ?? '',
    );
  }

  @override
  String toString() => 'TranscriptEntry(${role.name}: $text)';
}
