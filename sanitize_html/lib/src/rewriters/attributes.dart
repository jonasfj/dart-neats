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

/// # UNTRUSTED: `HtmlRewriter.attributes` and `HtmlRewriter.addLinkRel`.
library;

import '../html_rewriter.dart';
import '../html_token_sink.dart';

/// See `HtmlRewriter.attributes`.
HtmlRewriter rewriteAttributes(
  String tagName,
  void Function(Map<String, String> attributes) rewrite,
) =>
    HtmlRewriter((next) => _RewriteAttributes(tagName, rewrite, next));

/// See `HtmlRewriter.addLinkRel`.
HtmlRewriter addLinkRel(List<String> Function(String href) rel) =>
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
