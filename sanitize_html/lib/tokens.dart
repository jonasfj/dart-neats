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

/// The building blocks of `package:sanitize_html`, for custom pipelines.
///
/// ```
/// untrusted String
///   -> HtmlTokenizer
///   -> HtmlTokenSink: impliedEndTags() -> rewriters -> sanitizer(rules)
///   -> SaneHtmlWriter
///   -> trusted String
/// ```
///
/// Everything between tokenizer and writer is an [HtmlTransformer]. The
/// sanitizer must be the last transformer: everything before it is filtered
/// by the rules, everything after it is trusted.
///
/// Most users only need `package:sanitize_html/sanitize_html.dart`.
library;

export 'src/html_token_sink.dart' show HtmlTokenSink, HtmlTransformer;
export 'src/html_tokenizer.dart' show HtmlTokenizer;
export 'src/implied_end_tags.dart' show impliedEndTags;
export 'src/sane_html_writer.dart' show SaneHtmlWriter;
export 'src/sanitizer.dart' show sanitizer;
