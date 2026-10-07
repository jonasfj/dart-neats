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

/// Character helpers shared by the streaming tokenizers.
library;

/// Elements that switch the tokenizer into foreign content, where `/>` on
/// the element itself closes it.
/// https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inforeign
const foreignContentElements = <String>{'math', 'svg'};

/// Whether [c] is an ASCII letter.
bool isAsciiAlpha(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);

/// Whether [c] is ASCII whitespace as defined by the HTML tokenizer.
bool isHtmlWhitespace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D;

/// Lowercases ASCII letters in `s[start..end)`, returning the substring
/// itself when it has none.
String asciiLowerSubstring(String s, int start, int end) {
  for (var i = start; i < end; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0x41 && c <= 0x5A) {
      final buffer = StringBuffer(s.substring(start, i));
      for (var j = i; j < end; j++) {
        final c = s.codeUnitAt(j);
        buffer.writeCharCode(c >= 0x41 && c <= 0x5A ? c + 0x20 : c);
      }
      return buffer.toString();
    }
  }
  return s.substring(start, end);
}
