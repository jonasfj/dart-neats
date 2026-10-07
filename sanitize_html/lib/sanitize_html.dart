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

/// Sanitizes HTML so it can be embedded in a page without allowing script
/// execution or interference with the rest of the page.
///
/// ```dart
/// import 'package:sanitize_html/sanitize_html.dart';
///
/// final sanitize = htmlSanitizer(
///   rules: RuleSet.gfm(allowClassName: (c) => c.startsWith('hljs-')),
///   rewriters: [addLinkRel((href) => ['ugc', 'nofollow'])],
/// );
/// final safe = sanitize(untrusted);
/// ```
///
/// See [htmlSanitizer], [RuleSet] and the package README for how safety is
/// achieved and what the guarantee covers. The building blocks (tokenizers,
/// token sink, transformers and writer) are in
/// `package:sanitize_html/tokens.dart`.
library;

export 'src/attribute_rule.dart' show AttributeRule;
export 'src/html_sanitizer.dart' show htmlSanitizer, sanitizeHtml;
export 'src/rewriters.dart' show addLinkRel, rewriteAttributes;
export 'src/rule_set.dart' show RuleSet;
export 'src/tag_rule.dart' show TagRule;
