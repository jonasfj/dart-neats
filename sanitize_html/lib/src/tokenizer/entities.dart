// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// # UNTRUSTED: decodes character references in attribute values.
///
/// Used by the streaming tokenizers to produce decoded attribute values, as
/// the `HtmlTokenSink` contract requires. Fidelity to browsers matters for
/// _display_ only: `SaneHtmlWriter` re-escapes every attribute value exactly,
/// so the URL policy validates precisely the string a browser will see. A
/// decoding bug can therefore produce a wrong-looking attribute, never a
/// dangerous one.
///
/// Implements the attribute-value branch of
/// https://html.spec.whatwg.org/multipage/parsing.html#character-reference-state
library;

import 'named_character_references.dart';

/// Decodes the character references in `s[start..end)`.
String decodeCharacterReferences(String s, int start, int end) {
  var amp = _indexOfAmpersand(s, start, end);
  if (amp < 0) {
    return s.substring(start, end);
  }
  final out = StringBuffer();
  var copied = start;
  while (amp >= 0) {
    final decoded = _decodeAt(s, amp, end);
    if (decoded != null) {
      out
        ..write(s.substring(copied, amp))
        ..write(decoded.text);
      copied = decoded.end;
      amp = _indexOfAmpersand(s, copied, end);
    } else {
      amp = _indexOfAmpersand(s, amp + 1, end);
    }
  }
  out.write(s.substring(copied, end));
  return out.toString();
}

/// Index of the first `&` in `s[start..end)`, or -1.
///
/// Deliberately not `String.indexOf`, which has no end bound and would scan
/// past the slice into the rest of the document for every attribute value.
int _indexOfAmpersand(String s, int start, int end) {
  for (var i = start; i < end; i++) {
    if (s.codeUnitAt(i) == 0x26 /* & */) {
      return i;
    }
  }
  return -1;
}

/// Decodes the reference starting with the `&` at `s[amp]`, if there is one.
({String text, int end})? _decodeAt(String s, int amp, int end) {
  var i = amp + 1;
  if (i >= end) {
    return null;
  }
  if (s.codeUnitAt(i) == 0x23 /* # */) {
    return _decodeNumeric(s, i + 1, end);
  }
  final nameStart = i;
  while (i < end && _isAlphanumeric(s.codeUnitAt(i))) {
    i++;
  }
  if (i == nameStart) {
    return null;
  }
  final name = s.substring(nameStart, i);
  if (i < end && s.codeUnitAt(i) == 0x3B /* ; */) {
    final text = namedCharacterReferences[name];
    return text == null ? null : (text: text, end: i + 1);
  }
  // Legacy references without `;` are not decoded in attributes when
  // followed by `=` or an alphanumeric ("for historical reasons"); the
  // alphanumeric case cannot occur here since the name is maximal.
  // https://html.spec.whatwg.org/multipage/parsing.html#named-character-reference-state
  if (i < end && s.codeUnitAt(i) == 0x3D /* = */) {
    return null;
  }
  final text = legacyNamedCharacterReferences[name];
  return text == null ? null : (text: text, end: i);
}

({String text, int end})? _decodeNumeric(String s, int i, int end) {
  var value = 0;
  final int digitsStart;
  if (i < end && (s.codeUnitAt(i) | 0x20) == 0x78 /* x */) {
    digitsStart = ++i;
    while (i < end) {
      final c = s.codeUnitAt(i);
      final digit = switch (c) {
        >= 0x30 && <= 0x39 => c - 0x30,
        >= 0x61 && <= 0x66 => c - 0x61 + 10,
        >= 0x41 && <= 0x46 => c - 0x41 + 10,
        _ => -1,
      };
      if (digit < 0) {
        break;
      }
      if (value <= 0x10FFFF) {
        value = value * 16 + digit;
      }
      i++;
    }
  } else {
    digitsStart = i;
    while (i < end) {
      final c = s.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) {
        break;
      }
      if (value <= 0x10FFFF) {
        value = value * 10 + (c - 0x30);
      }
      i++;
    }
  }
  if (i == digitsStart) {
    return null;
  }
  if (i < end && s.codeUnitAt(i) == 0x3B /* ; */) {
    i++;
  }
  return (text: _numericReferenceText(value), end: i);
}

/// https://html.spec.whatwg.org/multipage/parsing.html#numeric-character-reference-end-state
String _numericReferenceText(int value) {
  if (value == 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF)) {
    return '\uFFFD';
  }
  if (value >= 0x80 && value <= 0x9F) {
    return _windows1252[value - 0x80] ?? String.fromCharCode(value);
  }
  return String.fromCharCode(value);
}

/// Replacements for code points 0x80-0x9F, which browsers interpret as
/// Windows-1252 rather than C1 controls.
const _windows1252 = <int, String>{
  0x00: '\u20AC',
  0x02: '\u201A',
  0x03: '\u0192',
  0x04: '\u201E',
  0x05: '\u2026',
  0x06: '\u2020',
  0x07: '\u2021',
  0x08: '\u02C6',
  0x09: '\u2030',
  0x0A: '\u0160',
  0x0B: '\u2039',
  0x0C: '\u0152',
  0x0E: '\u017D',
  0x11: '\u2018',
  0x12: '\u2019',
  0x13: '\u201C',
  0x14: '\u201D',
  0x15: '\u2022',
  0x16: '\u2013',
  0x17: '\u2014',
  0x18: '\u02DC',
  0x19: '\u2122',
  0x1A: '\u0161',
  0x1B: '\u203A',
  0x1C: '\u0153',
  0x1E: '\u017E',
  0x1F: '\u0178',
};

bool _isAlphanumeric(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A);
