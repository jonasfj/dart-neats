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

/// # UNTRUSTED: a rewriter applying the tree builder's implied end tags.
///
/// `<p>` is closed by block elements, `<li>` by `<li>`, cells and rows by the
/// next cell or row, headings by headings, `<option>` by `<option>`, and a
/// nested `<a>` closes the open one. This makes output for common sloppy HTML
/// tidy and sanitizing idempotent. It is cosmetic: `HtmlWriter` balances
/// whatever is left open, and the browser would have applied the same rules
/// to the output anyway.
///
/// It tracks every start tag it sees, including ones the sanitizer will drop,
/// because that is what the browser's tree builder does. Like Blink, it caps
/// the stack at [_maxDepth]: a deeper start tag replaces the innermost open
/// element, which keeps every scan of the stack bounded and so the rewriter
/// linear.
library;

import '../html_rewriter.dart';
import '../html_token_sink.dart';
import '../html_writer.dart' show isVoidElement;

/// See `HtmlRewriter.impliedEndTags`.
HtmlRewriter impliedEndTags() => const HtmlRewriter(_ImpliedEndTags.new);

/// Blink's `kMaximumHTMLParserDOMTreeDepth`: deeper elements are attached as
/// siblings, so modelling deeper nesting would not match a browser anyway.
const _maxDepth = 512;

/// Start tags that close an open `<p>` in button scope; the
/// ["in body" insertion mode][1] does this before inserting any of these
/// elements.
///
/// [1]: https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inbody
const _closesParagraph = <String>{
  'address',
  'article',
  'aside',
  'blockquote',
  'center',
  'dd',
  'details',
  'dialog',
  'dir',
  'div',
  'dl',
  'dt',
  'fieldset',
  'figcaption',
  'figure',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hgroup',
  'hr',
  'li',
  'listing',
  'main',
  'menu',
  'nav',
  'ol',
  'p',
  'plaintext',
  'pre',
  'search',
  'section',
  'summary',
  'table',
  'ul',
  'xmp',
};

/// Start tags that close other open elements: each element in `targets`
/// that is open in `scope` is closed, together with everything opened after
/// it. Approximates the "in body", "in table" and "in select" insertion
/// modes and, for `a`, the adoption agency algorithm.
const _closesOpen = <String, ({Set<String> targets, Set<String> scope})>{
  'a': (targets: {'a'}, scope: _formattingMarkers),
  'dd': (targets: {'dd', 'dt'}, scope: _listItemScope),
  'dt': (targets: {'dd', 'dt'}, scope: _listItemScope),
  'h1': (targets: _headings, scope: _scope),
  'h2': (targets: _headings, scope: _scope),
  'h3': (targets: _headings, scope: _scope),
  'h4': (targets: _headings, scope: _scope),
  'h5': (targets: _headings, scope: _scope),
  'h6': (targets: _headings, scope: _scope),
  'li': (targets: {'li'}, scope: _listItemScope),
  'optgroup': (targets: {'optgroup', 'option'}, scope: _scope),
  'option': (targets: {'option'}, scope: _scope),
  'tbody': (targets: _rowGroups, scope: _tableScope),
  'td': (targets: {'td', 'th'}, scope: _tableScope),
  'tfoot': (targets: _rowGroups, scope: _tableScope),
  'th': (targets: {'td', 'th'}, scope: _tableScope),
  'thead': (targets: _rowGroups, scope: _tableScope),
  'tr': (targets: {'tr'}, scope: _tableScope),
};

const _headings = <String>{'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};
const _rowGroups = <String>{'tbody', 'tfoot', 'thead'};

/// Boundaries of the tree builder's [element scopes][1].
///
/// [1]: https://html.spec.whatwg.org/multipage/parsing.html#has-an-element-in-scope
const _scope = <String>{
  'applet',
  'caption',
  'html',
  'table',
  'td',
  'th',
  'marquee',
  'object',
  'template',
  'mi',
  'mo',
  'mn',
  'ms',
  'mtext',
  'annotation-xml',
  'foreignobject',
  'desc',
  'title',
};
const _buttonScope = <String>{..._scope, 'button'};
const _listItemScope = <String>{..._scope, 'ol', 'ul'};
const _tableScope = <String>{'html', 'table', 'template'};

/// Elements that push a marker onto the
/// [list of active formatting elements][1], beyond which an `<a>` start tag
/// does not close an open `<a>`.
///
/// [1]: https://html.spec.whatwg.org/multipage/parsing.html#list-of-active-formatting-elements
const _formattingMarkers = <String>{
  'applet',
  'caption',
  'marquee',
  'object',
  'td',
  'template',
  'th',
};

final class _ImpliedEndTags extends HtmlTokenSink {
  final HtmlTokenSink _next;

  /// Names of the open elements, outermost first.
  final List<String> _open = [];

  _ImpliedEndTags(this._next);

  @override
  void text(String source, int start, int end) =>
      _next.text(source, start, end);

  @override
  void startTag(String name, Map<String, String> attributes) {
    if (_closesParagraph.contains(name) && _isOpenInScope('p', _buttonScope)) {
      _close('p');
    }
    if (_closesOpen[name] case (:final targets, :final scope)) {
      for (final target in targets) {
        if (_isOpenInScope(target, scope)) {
          _close(target);
        }
      }
    }
    _next.startTag(name, attributes);
    if (isVoidElement(name)) {
      return;
    }
    if (_open.length >= _maxDepth) {
      _open.removeLast();
    }
    _open.add(name);
  }

  @override
  void endTag(String name) {
    final index = _open.lastIndexOf(name);
    if (index >= 0) {
      _open.length = index;
    }
    _next.endTag(name);
  }

  /// Closes the innermost open [name] (the writer closes what was opened
  /// after it).
  void _close(String name) {
    _open.length = _open.lastIndexOf(name);
    _next.endTag(name);
  }

  /// The tree builder's ["has an element in scope"][1]: whether [name] is
  /// open and none of [boundaries] was opened after it.
  ///
  /// [1]: https://html.spec.whatwg.org/multipage/parsing.html#has-an-element-in-the-specific-scope
  bool _isOpenInScope(String name, Set<String> boundaries) {
    for (var i = _open.length - 1; i >= 0; i--) {
      final open = _open[i];
      if (open == name) {
        return true;
      }
      if (boundaries.contains(open)) {
        return false;
      }
    }
    return false;
  }
}
