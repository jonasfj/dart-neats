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

/// The transformer that applies a `RuleSet`.
///
/// Trusted for _completeness_ (every token that reaches the writer went
/// through the rules), not for what it writes: that is `SaneHtmlWriter`.
///
/// The only state is a counter for the element currently being dropped, so
/// that `<x><x></x>still dropped</x>` drops the whole subtree. It never
/// consults a stack of open elements: the browser may close elements where
/// we did not, so any transformation based on nesting would be a guess.
library;

import 'html_token_sink.dart';
import 'rule_set.dart';
import 'sane_html_writer.dart' show isVoidElement;
import 'tag_rule.dart';

/// A transformer that keeps the elements [rules] allow, with their
/// attributes filtered, and drops every other element together with its
/// content.
///
/// Must be the last transformer before the `SaneHtmlWriter`.
HtmlTransformer sanitizer(RuleSet rules) => (next) => _Sanitizer(rules, next);

final class _Sanitizer extends HtmlTokenSink {
  final RuleSet _rules;
  final HtmlTokenSink _next;

  /// While dropping an element's content: its name and the number of
  /// currently open elements with that name.
  String? _droppedName;
  int _droppedDepth = 0;

  _Sanitizer(this._rules, this._next);

  @override
  void text(String source, int start, int end) {
    if (_droppedDepth > 0) {
      return;
    }
    _next.text(source, start, end);
  }

  @override
  void startTag(String name, Map<String, String> attributes) {
    if (_droppedDepth > 0) {
      if (name == _droppedName) {
        _droppedDepth++;
      }
      return;
    }
    final rule = _rules.lookup(name);
    if (rule == null) {
      // A void element has no content to drop.
      if (!isVoidElement(name)) {
        _droppedName = name;
        _droppedDepth = 1;
      }
      return;
    }
    _next.startTag(name, rule.apply(attributes));
  }

  @override
  void endTag(String name) {
    if (_droppedDepth > 0) {
      if (name == _droppedName) {
        _droppedDepth--;
      }
      return;
    }
    _next.endTag(name);
  }
}
