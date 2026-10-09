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

/// # UNTRUSTED: `HtmlRewriter.prefixIds`.
library;

import '../html_rewriter.dart';
import '../html_token_sink.dart';

/// See `HtmlRewriter.prefixIds`.
HtmlRewriter prefixIds(String prefix) =>
    HtmlRewriter((next) => _PrefixIds(prefix, next));

final class _PrefixIds extends HtmlTokenSink {
  final String _prefix;
  final HtmlTokenSink _next;

  _PrefixIds(this._prefix, this._next);

  @override
  void text(String source, int start, int end) =>
      _next.text(source, start, end);

  @override
  void startTag(String name, Map<String, String> attributes) {
    if (attributes.isEmpty) {
      _next.startTag(name, attributes);
      return;
    }
    final id = attributes['id'];
    if (id != null && !id.startsWith(_prefix)) {
      attributes['id'] = '$_prefix$id';
    }
    final href = attributes['href'];
    if (href != null &&
        href.length > 1 &&
        href.startsWith('#') &&
        !href.startsWith(_prefix, 1)) {
      attributes['href'] = '#$_prefix${href.substring(1)}';
    }
    _next.startTag(name, attributes);
  }

  @override
  void endTag(String name) => _next.endTag(name);
}
