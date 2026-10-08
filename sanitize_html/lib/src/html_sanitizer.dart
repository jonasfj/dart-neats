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
/// allowed are removed together with their content.
///
/// ```dart
/// print(sanitizeHtml('<a href="javascript:alert();">evil link</a>'));
/// // Prints: <a>evil link</a>
///
/// final safe = sanitizeHtml(
///   untrusted,
///   rules: RuleSet.gfm(allowElementId: true),
///   rewriters: [HtmlRewriter.addLinkRel((href) => ['ugc', 'nofollow'])],
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
/// interfere with the host page (no `id` or `class` unless allowed, no CSS,
/// no forms, no `name` except on `<a>`). It does not protect against content
/// that is merely misleading, such as links to malicious sites.
String sanitizeHtml(
  String html, {
  RuleSet? rules,
  List<HtmlRewriter> rewriters = const [],
  HtmlTokenizer tokenizer = HtmlTokenizer.streaming,
}) {
  final writer = HtmlWriter();
  HtmlTokenSink sink =
      HtmlRewriter.sanitizer(rules ?? RuleSet.gfm()).bind(writer);
  for (final rewriter in rewriters.reversed) {
    sink = rewriter.bind(sink);
  }
  tokenizer.tokenize(html, HtmlRewriter.impliedEndTags().bind(sink));
  return writer.finish();
}
