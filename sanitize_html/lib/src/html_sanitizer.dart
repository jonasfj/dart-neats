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

/// Assembles tokenizer, rewriters and writer into [sanitizeHtml].
library;

import 'attribute_rule.dart';
import 'element_rule.dart';
import 'gfm_rules.dart' show gfmElements;
import 'html_rewriter.dart';
import 'html_token_sink.dart';
import 'html_tokenizer.dart';
import 'html_writer.dart';
import 'rule_set.dart';

/// Sanitizes [html] with [rules].
///
/// Returns HTML containing only the elements and attributes [rules] allow
/// (by default [RuleSet.gfm], modelled on how GitHub sanitizes rendered
/// Markdown), with text and attribute values escaped. Elements that are not
/// allowed are unwrapped: their tags are removed, their content is kept.
///
/// ```dart
/// print(sanitizeHtml('<a href="javascript:alert();">evil link</a>'));
/// // Prints: <a>evil link</a>
///
/// final safe = sanitizeHtml(
///   untrusted,
///   rewriters: [
///     HtmlRewriter.prefixIds('user-content-'),
///     HtmlRewriter.addLinkRel((href) => ['ugc', 'nofollow']),
///   ],
/// );
/// ```
///
/// [rewriters] run before the rules are applied, so they cannot introduce
/// anything the rules would not allow. [tokenizer] selects how the input is
/// split into tags and text; the tokenizers differ in speed and in how
/// faithfully they reproduce browser behavior for broken markup, not in
/// safety.
///
/// The output is safe to insert where an HTML parser is in its data state,
/// i.e. as content of elements such as `<div>` or `<body>` in an HTML
/// document. Do not insert it into attribute values, `<script>`, `<style>`,
/// `<textarea>`, `<title>`, `<svg>`, `<math>` or XML documents.
///
/// The sanitizer prevents script execution and limits the ways content can
/// interfere with the host page (no unprefixed `id`, no `name`, no `class`
/// outside `markdown-*`, no CSS, no forms). It does not protect against
/// content that is merely misleading, such as links to malicious sites.
///
/// [allowElementId], [allowClassName] and [addLinkRel] are the parameters
/// of version 2, kept so that existing calls compile and mean the same:
/// `id`s and `class` tokens are kept when the callback returns `true`, and
/// `rel` tokens added to links with an `href`. They cannot be combined with
/// [rules] or [rewriters]. Migrate to `RuleSet.gfm().union(...)`,
/// [HtmlRewriter.keepTokens] and [HtmlRewriter.addLinkRel].
String sanitizeHtml(
  String html, {
  RuleSet? rules,
  List<HtmlRewriter> rewriters = const [],
  HtmlTokenizer tokenizer = HtmlTokenizer.streaming,
  @Deprecated('Use rules: RuleSet.gfm().union(...) and '
      'rewriters: [HtmlRewriter.keepTokens(\'id\', ...)]')
  bool Function(String id)? allowElementId,
  @Deprecated('Use rules: RuleSet.gfm().union(...) and '
      'rewriters: [HtmlRewriter.keepTokens(\'class\', ...)]')
  bool Function(String className)? allowClassName,
  @Deprecated('Use rewriters: [HtmlRewriter.addLinkRel(...)]')
  Iterable<String>? Function(String href)? addLinkRel,
}) {
  if (allowElementId != null || allowClassName != null || addLinkRel != null) {
    if (rules != null || rewriters.isNotEmpty) {
      throw ArgumentError(
        'allowElementId, allowClassName and addLinkRel cannot be combined '
        'with rules or rewriters',
      );
    }
    rules = _legacyRules(
      id: allowElementId != null,
      className: allowClassName != null,
    );
    rewriters = [
      if (allowElementId != null) HtmlRewriter.keepTokens('id', allowElementId),
      if (allowClassName != null)
        HtmlRewriter.keepTokens('class', allowClassName),
      if (addLinkRel != null)
        HtmlRewriter.addLinkRel(
          (href) => addLinkRel(href)?.toList() ?? const [],
        ),
    ];
  }
  final writer = HtmlWriter();
  HtmlTokenSink sink =
      HtmlRewriter.sanitizer(rules ?? RuleSet.gfm()).bind(writer);
  for (final rewriter in rewriters.reversed) {
    sink = rewriter.bind(sink);
  }
  tokenizer.tokenize(html, HtmlRewriter.impliedEndTags().bind(sink));
  return writer.finish();
}

final _legacyRuleSets = <(bool, bool), RuleSet>{};

/// [RuleSet.gfm] with any `id` and/or `class` allowed on every element, as
/// version 2 allowed them before its callbacks filtered the values.
RuleSet _legacyRules({required bool id, required bool className}) =>
    _legacyRuleSets.putIfAbsent(
      (id, className),
      () => RuleSet.gfm().union(RuleSet({
        for (final element in gfmElements)
          element: ElementRule(attributes: {
            if (id) 'id': const AttributeRule.any(),
            if (className) 'class': const AttributeRule.any(),
          }),
      })),
    );
