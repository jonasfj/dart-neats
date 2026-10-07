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

/// Assembles tokenizer, transformers and writer into a sanitizer function.
library;

import 'html_token_sink.dart';
import 'html_tokenizer.dart';
import 'implied_end_tags.dart';
import 'rule_set.dart';
import 'sane_html_writer.dart';
import 'sanitizer.dart';

/// Creates a function that sanitizes HTML with [rules].
///
/// The returned function takes untrusted HTML and returns HTML containing
/// only the elements and attributes [rules] allow (by default [RuleSet.gfm],
/// modelled on how GitHub sanitizes rendered Markdown), with text and
/// attribute values escaped. Elements that are not allowed are removed
/// together with their content.
///
/// ```dart
/// final sanitize = htmlSanitizer(
///   rules: RuleSet.gfm(allowClassName: (c) => c.startsWith('hljs-')),
///   rewriters: [addLinkRel((href) => ['ugc', 'nofollow'])],
/// );
/// final safe = sanitize(untrusted);
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
/// interfere with the host page (no `id` or `class` unless allowed, no CSS,
/// no forms, no `name` except on `<a>`). It does not protect against content
/// that is merely misleading, such as links to malicious sites.
String Function(String html) htmlSanitizer({
  RuleSet? rules,
  List<HtmlTransformer> rewriters = const [],
  HtmlTokenizer tokenizer = HtmlTokenizer.streaming,
}) {
  final transformers = [
    impliedEndTags(),
    ...rewriters,
    sanitizer(rules ?? RuleSet.gfm()),
  ].reversed.toList();
  return (html) {
    final writer = SaneHtmlWriter();
    HtmlTokenSink sink = writer;
    for (final transformer in transformers) {
      sink = transformer(sink);
    }
    tokenizer.tokenize(html, sink);
    return writer.finish();
  };
}

/// Sanitizes [html] with [rules]; see [htmlSanitizer].
///
/// ```dart
/// print(sanitizeHtml('<a href="javascript:alert();">evil link</a>'));
/// // Prints: <a>evil link</a>
/// ```
///
/// For repeated use, or to add rewriters, build a sanitizer once with
/// [htmlSanitizer].
String sanitizeHtml(String html, {RuleSet? rules}) =>
    (rules == null ? _defaultSanitizer : htmlSanitizer(rules: rules))(html);

final _defaultSanitizer = htmlSanitizer();
