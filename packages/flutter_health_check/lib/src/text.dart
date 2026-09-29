/// Reading config files without a parser for each language: strip comments
/// (keeping every offset, so line numbers still point at the right place),
/// find `{ }` blocks, and read Info.plist.
library;

/// Blanks `//` and `/* */` comments in Gradle, Kotlin, Swift and Dart source.
/// Strings are skipped, so `"https://…"` survives. Newlines are kept.
String stripComments(String code) {
  final out = StringBuffer();
  var i = 0;
  void blank(int end) {
    for (; i < end && i < code.length; i++) {
      out.write(code[i] == '\n' ? '\n' : ' ');
    }
  }

  while (i < code.length) {
    final c = code[i];
    final next = i + 1 < code.length ? code[i + 1] : '';
    if (c == '/' && next == '/') {
      final end = code.indexOf('\n', i);
      blank(end == -1 ? code.length : end);
    } else if (c == '/' && next == '*') {
      final end = code.indexOf('*/', i + 2);
      blank(end == -1 ? code.length : end + 2);
    } else if (c == '"' || c == "'") {
      final triple = code.startsWith(c * 3, i);
      final quote = triple ? c * 3 : c;
      var j = i + quote.length;
      while (j < code.length) {
        if (!triple && code[j] == '\\') {
          j += 2;
          continue;
        }
        if (code.startsWith(quote, j)) {
          j += quote.length;
          break;
        }
        if (!triple && code[j] == '\n') break; // unterminated: stop at the line
        j++;
      }
      out.write(code.substring(i, j.clamp(0, code.length)));
      i = j;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

/// Blanks `<!-- -->` comments, keeping newlines.
String stripXmlComments(String xml) => xml.replaceAllMapped(
  RegExp(r'<!--[\s\S]*?-->'),
  (m) => m[0]!.replaceAll(RegExp(r'[^\n]'), ' '),
);

/// The body of the first `{ … }` block whose opening matches [opener]
/// (the pattern must end just before the `{`), as (start, end) offsets of
/// the body, or null.
(int, int)? block(String text, RegExp opener, [int from = 0, int? to]) {
  final limit = to ?? text.length;
  for (final m in opener.allMatches(text.substring(0, limit), from)) {
    var i = m.end;
    while (i < limit &&
        (text[i] == ' ' ||
            text[i] == '\t' ||
            text[i] == '\n' ||
            text[i] == '\r')) {
      i++;
    }
    if (i >= limit || text[i] != '{') continue;
    var depth = 0;
    for (var j = i; j < limit; j++) {
      if (text[j] == '{') depth++;
      if (text[j] == '}' && --depth == 0) return (i + 1, j);
    }
    return null;
  }
  return null;
}

/// A property list as Dart values: Map, List, String, bool, num.
/// Enough of the format for Info.plist; `<data>` and `<date>` come back as
/// their text.
Object? parsePlist(String xml) {
  final clean = stripXmlComments(xml)
      .replaceAll(RegExp(r'<\?xml[^>]*\?>'), '')
      .replaceAll(RegExp(r'<!DOCTYPE[^>]*>'), '');
  final tokens = RegExp(
    r'<(/?)([A-Za-z]+)(?:\s+[^>]*?)?\s*(/?)>|([^<]+)',
  ).allMatches(clean).toList();
  var pos = 0;

  String text() {
    final buf = StringBuffer();
    while (pos < tokens.length && tokens[pos][4] != null) {
      buf.write(tokens[pos++][4]);
    }
    return _unescape(buf.toString());
  }

  Object? value() {
    while (pos < tokens.length &&
        tokens[pos][4] != null &&
        tokens[pos][4]!.trim().isEmpty) {
      pos++;
    }
    if (pos >= tokens.length) return null;
    final t = tokens[pos++];
    final name = t[2];
    if (t[1] == '/' || name == null) return null;
    final selfClosing = t[3] == '/';
    switch (name) {
      case 'plist':
        final v = value();
        return v;
      case 'true':
        if (!selfClosing) pos++;
        return true;
      case 'false':
        if (!selfClosing) pos++;
        return false;
      case 'dict':
        final map = <String, Object?>{};
        if (selfClosing) return map;
        while (pos < tokens.length) {
          while (pos < tokens.length && tokens[pos][4] != null) {
            pos++;
          }
          if (pos >= tokens.length) break;
          final k = tokens[pos];
          if (k[1] == '/' && k[2] == 'dict') {
            pos++;
            break;
          }
          if (k[2] != 'key') return map; // malformed: keep what was read
          pos++;
          final key = text();
          pos++; // </key>
          map[key] = value();
        }
        return map;
      case 'array':
        final list = <Object?>[];
        if (selfClosing) return list;
        while (pos < tokens.length) {
          while (pos < tokens.length &&
              tokens[pos][4] != null &&
              tokens[pos][4]!.trim().isEmpty) {
            pos++;
          }
          if (pos < tokens.length &&
              tokens[pos][1] == '/' &&
              tokens[pos][2] == 'array') {
            pos++;
            break;
          }
          if (pos >= tokens.length) break;
          list.add(value());
        }
        return list;
      default: // string, integer, real, date, data
        if (selfClosing) return '';
        final s = text();
        pos++; // closing tag
        if (name == 'integer') return int.tryParse(s.trim()) ?? s;
        if (name == 'real') return double.tryParse(s.trim()) ?? s;
        return s;
    }
  }

  return value();
}

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
