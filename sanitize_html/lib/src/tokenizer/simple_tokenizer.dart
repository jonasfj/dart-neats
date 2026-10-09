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

/// # UNTRUSTED: a deliberately small tokenizer for well-formed HTML.
///
/// Every construct is handled by scanning for a delimiter with `indexOf`:
///
///  * `<!--` ... `-->`, `<!` ... `>`, `<?` ... `>` are skipped
///  * `</name` ... `>` is an end tag
///  * `<name` attributes `>` is a start tag
///  * the content of `script`, `style`, `iframe` and friends is skipped up
///    to `</name`
///  * everything else is text
///
/// It does not implement the script data escaping rules, `--!>`, or the
/// finer points of attribute name states, so unusual markup may tokenize
/// differently than in a browser. Since tokenizers are not security
/// relevant (see `html_tokenizer.dart`), such differences only ever affect
/// how the output looks.
library;

import '../html_token_sink.dart';
import 'ascii.dart';
import 'entities.dart';

const _rawTextElements = <String>{
  'iframe',
  'noembed',
  'noframes',
  'noscript',
  'script',
  'style',
  'template',
  'textarea',
  'title',
  'xmp',
};

/// See `HtmlTokenizer.simple`.
void tokenizeSimple(String html, HtmlTokenSink sink) {
  final len = html.length;
  var pos = 0;
  var textStart = 0;

  // Advances [pos] past the next occurrence of [s], or to EOF.
  void skipPast(String s) {
    final index = html.indexOf(s, pos);
    pos = index < 0 ? len : index + s.length;
  }

  // Reads a tag or attribute name at [pos].
  String name() {
    final start = pos;
    while (pos < len) {
      final c = html.codeUnitAt(pos);
      if (c <= 0x20 || c == 0x2F /* / */ || c == 0x3E /* > */ || c == 0x3D) {
        break;
      }
      pos++;
    }
    return asciiLowerSubstring(html, start, pos);
  }

  while (true) {
    final lt = html.indexOf('<', pos);
    if (lt < 0 || lt + 1 >= len) {
      break;
    }
    pos = lt + 1;
    final next = html.codeUnitAt(pos);

    if (next == 0x21 /* ! */ || next == 0x3F /* ? */) {
      if (lt > textStart) {
        sink.text(html, textStart, lt);
      }
      if (html.startsWith('!--', pos)) {
        pos += 3;
        skipPast('-->');
      } else {
        skipPast('>');
      }
    } else if (next == 0x2F /* / */) {
      if (lt > textStart) {
        sink.text(html, textStart, lt);
      }
      pos++;
      if (pos < len && isAsciiAlpha(html.codeUnitAt(pos))) {
        sink.endTag(name());
      }
      skipPast('>');
    } else if (isAsciiAlpha(next)) {
      if (lt > textStart) {
        sink.text(html, textStart, lt);
      }
      final tagName = name();
      var attributes = const <String, String>{};
      var selfClosing = false;
      while (pos < len) {
        final c = html.codeUnitAt(pos);
        if (c == 0x3E /* > */) {
          pos++;
          break;
        }
        if (c <= 0x20 || c == 0x2F /* / */ || c == 0x3D /* = */) {
          selfClosing = c == 0x2F && html.startsWith('>', pos + 1);
          pos++;
          continue;
        }
        final attributeName = name();
        var value = '';
        while (pos < len && html.codeUnitAt(pos) <= 0x20) {
          pos++;
        }
        if (html.startsWith('=', pos)) {
          pos++;
          while (pos < len && html.codeUnitAt(pos) <= 0x20) {
            pos++;
          }
          final start = pos;
          final quote = pos < len ? html.codeUnitAt(pos) : 0;
          if (quote == 0x22 /* " */ || quote == 0x27 /* ' */) {
            pos++;
            final close = html.indexOf(String.fromCharCode(quote), pos);
            final end = close < 0 ? len : close;
            value = decodeCharacterReferences(html, pos, end);
            pos = close < 0 ? len : close + 1;
          } else {
            while (pos < len &&
                html.codeUnitAt(pos) > 0x20 &&
                html.codeUnitAt(pos) != 0x3E /* > */) {
              pos++;
            }
            value = decodeCharacterReferences(html, start, pos);
          }
        }
        if (attributes.isEmpty) {
          attributes = <String, String>{};
        }
        attributes.putIfAbsent(attributeName, () => value);
      }
      sink.startTag(tagName, attributes);
      if (selfClosing && foreignContentElements.contains(tagName)) {
        sink.endTag(tagName);
      } else if (_rawTextElements.contains(tagName)) {
        pos = _indexOfEndTag(html, tagName, pos);
        skipPast('>');
        sink.endTag(tagName);
      } else if (tagName == 'plaintext') {
        pos = len;
      }
    } else {
      continue; // `<` followed by anything else is text.
    }
    textStart = pos;
  }
  if (len > textStart) {
    sink.text(html, textStart, len);
  }
}

/// Index just after `</name` (ASCII case-insensitive) at or after [pos], or
/// `html.length` if there is none.
int _indexOfEndTag(String html, String name, int pos) {
  while (true) {
    final lt = html.indexOf('</', pos);
    if (lt < 0 || lt + 2 + name.length > html.length) {
      return html.length;
    }
    pos = lt + 2;
    if (asciiLowerSubstring(html, pos, pos + name.length) == name) {
      return pos + name.length;
    }
  }
}
