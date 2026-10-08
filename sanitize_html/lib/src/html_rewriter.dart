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

/// A step in the pipeline between tokenizer and writer.
library;

import 'html_token_sink.dart';
import 'implied_end_tags.dart' as implied_end_tags;
import 'rewriters.dart' as rewriters;
import 'rule_set.dart';
import 'sanitizer.dart' as sanitizer;

/// Rewrites the token stream on its way from the tokenizer to the writer.
///
/// A rewriter wraps the next [HtmlTokenSink] in a sink of its own. Rewriters
/// compose right to left: `a.bind(b.bind(c.bind(writer)))` feeds `a` first
/// and `c` last.
///
/// Rewriters passed to `sanitizeHtml` run before the rules are applied, so
/// they need no trust and no knowledge of what is allowed: whatever they add
/// is still filtered by the `RuleSet`.
///
/// ```dart
/// sanitizeHtml(html, rewriters: [
///   HtmlRewriter.addLinkRel((href) => ['ugc', 'nofollow']),
///   HtmlRewriter.attributes('h2', (attributes) {
///     attributes['id'] ??= slugify(attributes['title'] ?? '');
///   }),
/// ]);
/// ```
///
/// A custom rewriter is a sink that forwards to the next one:
///
/// ```dart
/// HtmlRewriter(MySink.new) // where MySink(HtmlTokenSink next)
/// ```
final class HtmlRewriter {
  final HtmlTokenSink Function(HtmlTokenSink next) _bind;

  /// A rewriter whose sink for the next sink is given by [bind].
  const HtmlRewriter(this._bind);

  /// Calls [rewrite] with the attributes of every [tagName] element, which
  /// it may change in place.
  factory HtmlRewriter.attributes(
    String tagName,
    void Function(Map<String, String> attributes) rewrite,
  ) =>
      rewriters.rewriteAttributes(tagName, rewrite);

  /// Adds the `rel` tokens returned by [rel] to every `<a>` with an `href`.
  ///
  /// Typically used to [qualify outbound links][1] in user generated content:
  ///
  /// ```dart
  /// HtmlRewriter.addLinkRel((href) => ['ugc', 'nofollow'])
  /// ```
  ///
  /// Returning `const []` leaves the link as is. `href` is the attribute
  /// value before the rule set has seen it; if the rule set later drops the
  /// `href`, the added `rel` stays.
  ///
  /// [1]: https://support.google.com/webmasters/answer/96569
  factory HtmlRewriter.addLinkRel(List<String> Function(String href) rel) =>
      rewriters.addLinkRel(rel);

  /// Closes open elements a start tag implicitly ends, as the browser's
  /// tree builder would: `<p>` by block elements, `<li>` by `<li>`, cells
  /// and rows by the next cell or row, headings by headings, `<option>` by
  /// `<option>`, an open `<a>` by a nested `<a>`.
  ///
  /// `sanitizeHtml` always applies it first. Unnecessary after
  /// `HtmlTokenizer.dom`, which already builds a tree.
  factory HtmlRewriter.impliedEndTags() => implied_end_tags.impliedEndTags();

  /// Keeps the elements [rules] allow, with their attributes filtered, and
  /// drops every other element together with its content.
  ///
  /// Must be the last rewriter before the `HtmlWriter`: everything before it
  /// is filtered by the rules, everything after it would be trusted.
  factory HtmlRewriter.sanitizer(RuleSet rules) => sanitizer.sanitizer(rules);

  /// The sink that applies this rewriter and pushes the result into [next].
  HtmlTokenSink bind(HtmlTokenSink next) => _bind(next);
}
