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

/// # UNTRUSTED: transformers that rewrite attributes.
///
/// Rewriters run _before_ the sanitizer, so whatever they add is still
/// subject to the rule set; they need no trust and no knowledge of what is
/// allowed.
library;

import 'html_token_sink.dart';

/// A transformer calling [rewrite] with the attributes of every [tagName]
/// element, which it may change in place.
///
/// ```dart
/// rewriteAttributes('h2', (attributes) {
///   attributes['id'] ??= slugify(attributes['title'] ?? '');
/// })
/// ```
HtmlTransformer rewriteAttributes(
  String tagName,
  void Function(Map<String, String> attributes) rewrite,
) =>
    (next) => _RewriteAttributes(tagName, rewrite, next);

/// A transformer adding the `rel` tokens returned by [rel] to every `<a>`
/// with an `href`.
///
/// Typically used to [qualify outbound links][1] in user generated content:
///
/// ```dart
/// addLinkRel((href) => ['ugc', 'nofollow'])
/// ```
///
/// Returning `const []` leaves the link as is. [href] is the attribute value
/// before the rule set has seen it; if the rule set later drops the `href`,
/// the added `rel` stays.
///
/// [1]: https://support.google.com/webmasters/answer/96569
HtmlTransformer addLinkRel(List<String> Function(String href) rel) =>
    rewriteAttributes('a', (attributes) {
      final href = attributes['href'];
      if (href == null) {
        return;
      }
      final added = rel(href);
      if (added.isEmpty) {
        return;
      }
      final tokens = (attributes['rel'] ?? '').split(' ')
        ..removeWhere((t) => t.isEmpty);
      for (final token in added) {
        if (!tokens.contains(token)) {
          tokens.add(token);
        }
      }
      attributes['rel'] = tokens.join(' ');
    });

final class _RewriteAttributes extends HtmlTokenSink {
  final String _tagName;
  final void Function(Map<String, String>) _rewrite;
  final HtmlTokenSink _next;

  _RewriteAttributes(this._tagName, this._rewrite, this._next);

  @override
  void text(String source, int start, int end) =>
      _next.text(source, start, end);

  @override
  void startTag(String name, Map<String, String> attributes) {
    if (name == _tagName) {
      // Tags without attributes may carry a shared const map.
      if (attributes.isEmpty) {
        attributes = {};
      }
      _rewrite(attributes);
    }
    _next.startTag(name, attributes);
  }

  @override
  void endTag(String name) => _next.endTag(name);
}
