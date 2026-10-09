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

/// The rewriter that applies a `RuleSet`.
///
/// Trusted for _completeness_ (every token that reaches the writer went
/// through the rules), not for what it writes: that is `HtmlWriter`.
///
/// An element the rules do not keep is _unwrapped_: its tags are dropped
/// and its content passes through, to be judged on its own. Rules are about
/// what is safe to keep, not about what the output should look like; a
/// rewriter can drop whole subtrees beforehand.
///
/// Whether an element is kept can depend on its attributes
/// (`ElementRule.requires`), so the end tag of an unwrapped `<div>` must be
/// dropped while that of a kept `<div>` is forwarded. The sanitizer keeps a
/// stack of the start tags it has seen and matches end tags against it the
/// way `HtmlWriter` does (an end tag closes the nearest open element of its
/// name; without one it is ignored). The stack is capped like the writer's,
/// a start tag at the cap replacing the innermost entry, so memory is
/// bounded and every operation on it is O(cap). A mismatch between this
/// stack and the writer's only makes output uglier, never unsafe.
library;

import 'element_rule.dart';
import 'html_rewriter.dart';
import 'html_token_sink.dart';
import 'html_writer.dart' show isVoidElement;
import 'rule_set.dart';

/// See `HtmlRewriter.sanitizer`.
HtmlRewriter sanitizer(RuleSet rules) =>
    HtmlRewriter((next) => _Sanitizer(rules, next));

const _maxDepth = 512;

final class _Sanitizer extends HtmlTokenSink {
  final RuleSet _rules;
  final HtmlTokenSink _next;

  /// Open non-void start tags, with whether each was forwarded.
  final List<(String, bool)> _open = [];

  _Sanitizer(this._rules, this._next);

  @override
  void text(String source, int start, int end) =>
      _next.text(source, start, end);

  @override
  void startTag(String name, Map<String, String> attributes) {
    final kept = _rules.lookup(name)?.apply(attributes);
    if (!isVoidElement(name)) {
      if (_open.length >= _maxDepth) {
        _open.removeLast();
      }
      _open.add((name, kept != null));
    }
    if (kept != null) {
      _next.startTag(name, kept);
    }
  }

  @override
  void endTag(String name) {
    for (var i = _open.length - 1; i >= 0; i--) {
      final (openName, kept) = _open[i];
      if (openName != name) {
        continue;
      }
      _open.length = i;
      if (kept) {
        _next.endTag(name);
      }
      return;
    }
  }
}
