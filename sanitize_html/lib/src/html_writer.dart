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

/// # TRUSTED: the only component that writes output.
///
/// [HtmlWriter] owns the output grammar, and nothing else: it has no
/// opinion on which elements or attributes are acceptable (that is the
/// `RuleSet`), it only guarantees that whatever it is handed is written in a
/// way the browser cannot read as anything _more_.
///
/// ## Output grammar
///
///  * Start tags: `<` _name_ (` ` _attr_ `="` _value_ `"`)* `>`
///  * End tags: `</` _name_ `>`
///  * Text: characters with `<`, `>` and (most) `&` escaped
///
/// where _name_ matches `[a-z][a-z0-9._-]*`, _attr_ matches
/// `[a-z][a-z0-9_:.-]*`, and _value_ has `&`, `"`, `<` and `>` escaped.
/// Nothing else is escaped: newlines, tabs and other controls are plain
/// character data both in the [data state][1] and in a
/// [double-quoted attribute value][5]; the parser's input preprocessing
/// turns U+0000 into U+FFFD and CR into LF, and that is all.
///
/// ## The promise
///
/// For output inserted where an HTML parser is in the _data state_ (as
/// content of `<body>`, `<div>`, ...), the browser creates **no element and
/// no attribute that was not pushed into the writer**. It may create fewer:
/// after a `<plaintext>` or inside `<xmp>` the browser sees text where we
/// wrote tags. That is a rendering problem for whoever allowed such an
/// element, not a safety problem.
///
/// ## Why
///
/// 1. The tokenizer creates tags, comments and doctypes only from the
///    [data state][1] on a `<` (the [tag open state][2]). Text never
///    contains a raw `<` (it is written as `&lt;`), so text can never open
///    anything. A `&` in text enters the [character reference state][3],
///    which only ever produces character tokens.
/// 2. Attribute values are double-quoted with `"` and `&` escaped, so a value
///    cannot end the [double-quoted value][5] it is in, let alone the tag.
/// 3. Tag and attribute names use only characters that the
///    [tag name state][6] and [attribute name state][7] consume as part of
///    the name, so a name cannot end the tag or start another attribute.
/// 4. Elements that switch the tokenizer out of the data state (`script`,
///    `style`, `title`, `textarea`, `xmp`, `iframe`, `noembed`, `noframes`,
///    `noscript`, `plaintext`) or into foreign content (`svg`, `math`) make
///    the browser create _fewer_ nodes, never more: [RAWTEXT, RCDATA][8] and
///    PLAINTEXT content is text until the matching end tag, and the output
///    contains `</name` only where this writer wrote an end tag.
/// 5. The one start tag the tree builder renames is refused: an `image`
///    start tag becomes an `img` element, which nobody pushed. From the
///    [stack of open elements][9]:
///    > An image start tag token is handled by the tree builder, but it is
///    > not in this list because it is not an element; it gets turned into an
///    > img element.
/// 6. Every element the writer opens is closed by the writer. Nesting is
///    capped at [maxDepth] the way Blink caps the document at 512: a start
///    tag at the cap closes the innermost open element and becomes its
///    sibling, so the stack stays bounded and the output balanced. (Blink's
///    cap counts the host document's depth too; it only flattens, it never
///    creates elements, so where it applies is irrelevant here.)
///
/// The tree builder may still re-nest elements or insert implied `tbody`,
/// `tr`, `colgroup` and `p` elements; those carry no attributes and are not
/// attacker-controlled.
///
/// [1]: https://html.spec.whatwg.org/multipage/parsing.html#data-state
/// [2]: https://html.spec.whatwg.org/multipage/parsing.html#tag-open-state
/// [3]: https://html.spec.whatwg.org/multipage/parsing.html#character-reference-state
/// [5]: https://html.spec.whatwg.org/multipage/parsing.html#attribute-value-(double-quoted)-state
/// [6]: https://html.spec.whatwg.org/multipage/parsing.html#tag-name-state
/// [7]: https://html.spec.whatwg.org/multipage/parsing.html#attribute-name-state
/// [8]: https://html.spec.whatwg.org/multipage/parsing.html#generic-raw-text-element-parsing-algorithm
/// [9]: https://html.spec.whatwg.org/multipage/parsing.html#the-stack-of-open-elements
library;

import 'html_token_sink.dart';

/// Maximum number of simultaneously open elements in the output.
///
/// Blink flattens at 512 (`kMaximumHTMLParserDOMTreeDepth`), counting the
/// host document's own depth, which this package cannot know. A quarter of
/// that leaves any plausible host enough room that the browser never
/// flattens sanitized output itself. Package-private; the sanitizer uses the
/// same bound so its view of the open elements matches the writer's.
const maxDepth = 128;

/// Elements the parser never gives children or an end tag.
///
/// The ["in body" insertion mode][1] pops these immediately; the list is
/// wider than the syntax section's void elements (`basefont`, `bgsound`,
/// `keygen` and `param` are obsolete but still parsed as void).
///
/// [1]: https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inbody
const _voidElements = <String>{
  'area',
  'base',
  'basefont',
  'bgsound',
  'br',
  'col',
  'embed',
  'frame',
  'hr',
  'img',
  'input',
  'keygen',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

/// Whether [name] is a void element: written as `<br>`, never opened.
bool isVoidElement(String name) => _voidElements.contains(name);

/// Whether [HtmlWriter] accepts [name] as a tag name.
///
/// `[a-z][a-z0-9._-]*`, except `image` (see point 5 above).
bool isWritableTagName(String name) {
  if (name.isEmpty || !_isAsciiLower(name.codeUnitAt(0))) {
    return false;
  }
  for (var i = 1; i < name.length; i++) {
    final c = name.codeUnitAt(i);
    if (!_isAsciiLower(c) &&
        !_isDigit(c) &&
        c != 0x2E &&
        c != 0x2D &&
        c != 0x5F) {
      return false;
    }
  }
  return name != 'image';
}

/// Whether [HtmlWriter] accepts [name] as an attribute name.
///
/// `[a-z][a-z0-9_:.-]*`.
bool isWritableAttributeName(String name) {
  if (name.isEmpty || !_isAsciiLower(name.codeUnitAt(0))) {
    return false;
  }
  for (var i = 1; i < name.length; i++) {
    final c = name.codeUnitAt(i);
    if (!_isAsciiLower(c) &&
        !_isDigit(c) &&
        c != 0x2E &&
        c != 0x2D &&
        c != 0x5F &&
        c != 0x3A) {
      return false;
    }
  }
  return true;
}

/// Serializes tokens into HTML in which text cannot become markup.
///
/// See the library documentation for the grammar and the argument. The
/// writer is the last sink of a pipeline; call [finish] to close any open
/// elements and get the output.
///
/// The writer guarantees that the browser sees exactly the elements and
/// attributes pushed into it, no more. Whether those are safe to show is up
/// to the `RuleSet` in front of it.
final class HtmlWriter extends HtmlTokenSink {
  final StringBuffer _out = StringBuffer();

  /// Names of the currently open (non-void) elements, outermost first.
  final List<String> _open = [];

  /// Writes a start tag for [name] with [attributes].
  ///
  /// Throws [ArgumentError] if [name] is not an [isWritableTagName] or any
  /// attribute name is not an [isWritableAttributeName]. These are contract
  /// violations by whatever feeds the writer: a `RuleSet` only admits names
  /// that pass these checks, so with the sanitizer in front this never
  /// depends on input.
  @override
  void startTag(String name, Map<String, String> attributes) {
    if (!isWritableTagName(name)) {
      throw ArgumentError.value(name, 'name', 'not a writable tag name');
    }
    final isVoid = _voidElements.contains(name);
    if (!isVoid && _open.length >= maxDepth) {
      _writeEndTag(_open.removeLast());
    }
    _out
      ..write('<')
      ..write(name);
    for (final MapEntry(:key, :value) in attributes.entries) {
      if (!isWritableAttributeName(key)) {
        throw ArgumentError.value(key, 'attributes', 'not a writable name');
      }
      _out
        ..write(' ')
        ..write(key)
        ..write('="');
      _writeEscaped(value, 0, value.length, inAttribute: true);
      _out.write('"');
    }
    _out.write('>');
    if (!isVoid) {
      _open.add(name);
    }
  }

  /// Closes the innermost open element called [name] and every element
  /// opened after it. Does nothing if no such element is open.
  @override
  void endTag(String name) {
    final index = _open.lastIndexOf(name);
    if (index < 0) {
      return;
    }
    while (_open.length > index) {
      _writeEndTag(_open.removeLast());
    }
  }

  /// Writes `source[start..end)` as text.
  ///
  /// `<` and `>` are always escaped; `&` is escaped unless followed by `#` or
  /// an ASCII alphanumeric, in which case it is passed through: in the data
  /// state `&...` can only ever yield character tokens (point 1), and it
  /// renders exactly as the input would have (`&copy;` stays `&copy;`,
  /// `&bogus;` is shown literally either way, a lone `&` becomes `&amp;`).
  @override
  void text(String source, int start, int end) {
    _writeEscaped(source, start, end, inAttribute: false);
  }

  /// Closes all open elements and returns the output, leaving the writer
  /// empty and ready for reuse.
  String finish() {
    while (_open.isNotEmpty) {
      _writeEndTag(_open.removeLast());
    }
    final output = _out.toString();
    _out.clear();
    return output;
  }

  void _writeEndTag(String name) {
    _out
      ..write('</')
      ..write(name)
      ..write('>');
  }

  /// Escapes `source[start..end)` into [_out], copying unescaped runs with a
  /// single `substring` each.
  ///
  /// In attribute values every `&` and `"` is escaped so the browser decodes
  /// exactly the value the rules validated: the URL policy and the browser's
  /// URL parser see the same string.
  void _writeEscaped(
    String source,
    int start,
    int end, {
    required bool inAttribute,
  }) {
    var runStart = start;
    for (var i = start; i < end; i++) {
      final String replacement;
      switch (source.codeUnitAt(i)) {
        case 0x3C: // <
          replacement = '&lt;';
        case 0x3E: // >
          replacement = '&gt;';
        case 0x22 when inAttribute: // "
          replacement = '&quot;';
        case 0x26
            when inAttribute || !_startsCharacterReference(source, i, end):
          replacement = '&amp;';
        default:
          continue;
      }
      if (i > runStart) {
        _out.write(source.substring(runStart, i));
      }
      _out.write(replacement);
      runStart = i + 1;
    }
    if (end > runStart) {
      _out.write(source.substring(runStart, end));
    }
  }

  /// Whether the `&` at `source[i]` is followed by `#` or an ASCII
  /// alphanumeric, i.e. could plausibly be a character reference.
  static bool _startsCharacterReference(String source, int i, int end) {
    if (i + 1 >= end) {
      return false;
    }
    final c = source.codeUnitAt(i + 1);
    return c == 0x23 /* # */ ||
        _isDigit(c) ||
        _isAsciiLower(c) ||
        (c >= 0x41 && c <= 0x5A);
  }
}

bool _isAsciiLower(int c) => c >= 0x61 && c <= 0x7A;
bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
