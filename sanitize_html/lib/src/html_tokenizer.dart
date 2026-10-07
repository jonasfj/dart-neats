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

/// # UNTRUSTED: tokenizers split input into tags and text.
///
/// A tokenizer turns HTML source into [HtmlTokenSink] calls. It is _not_
/// part of the trusted base: whatever it reports, the sanitizer drops
/// elements and attributes without a rule and `SaneHtmlWriter` escapes text
/// and values, so a tokenizer bug can only make the output uglier (markup
/// shown as text), never unsafe. Review tokenizers for performance,
/// termination and fidelity, not for security.
library;

import 'html_token_sink.dart';
import 'tokenizer/dom_tokenizer.dart';
import 'tokenizer/simple_tokenizer.dart';
import 'tokenizer/streaming_tokenizer.dart';

/// Splits HTML into tokens.
///
/// The tokenizers differ in speed and in how faithfully they reproduce
/// browser behavior for broken markup, not in safety.
final class HtmlTokenizer {
  final void Function(String html, HtmlTokenSink sink) _tokenize;

  const HtmlTokenizer._(this._tokenize);

  /// Follows the WHATWG tokenizer states closely (comments, bogus comments,
  /// script data escaping, RAWTEXT / RCDATA elements) without building a
  /// tree. The default.
  static const streaming = HtmlTokenizer._(tokenizeStreaming);

  /// A small, easily reviewed tokenizer that handles well-formed HTML and
  /// degrades gracefully on everything else.
  static const simple = HtmlTokenizer._(tokenizeSimple);

  /// Parses a full DOM tree with `package:html` and walks it. Slowest, and
  /// superlinear on deeply nested input, but handles misnested markup the
  /// way browsers do.
  static const dom = HtmlTokenizer._(tokenizeDom);

  /// Feeds the tokens of [html] to [sink].
  void tokenize(String html, HtmlTokenSink sink) => _tokenize(html, sink);
}
