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

/// # UNTRUSTED: `HtmlRewriter.keepTokens`.
library;

import '../html_rewriter.dart';
import '../html_token_sink.dart';
import '../space_separated_tokens.dart';

/// See `HtmlRewriter.keepTokens`.
HtmlRewriter keepTokens(String attribute, bool Function(String token) where) =>
    HtmlRewriter((next) => _KeepTokens(attribute, where, next));

final class _KeepTokens extends HtmlTokenSink {
  final String _attribute;
  final bool Function(String) _where;
  final HtmlTokenSink _next;

  _KeepTokens(this._attribute, this._where, this._next);

  @override
  void text(String source, int start, int end) =>
      _next.text(source, start, end);

  @override
  void startTag(String name, Map<String, String> attributes) {
    final value = attributes[_attribute];
    if (value != null) {
      final kept = value
          .split(asciiWhitespace)
          .where((t) => t.isNotEmpty && _where(t))
          .join(' ');
      if (kept.isEmpty) {
        attributes.remove(_attribute);
      } else {
        attributes[_attribute] = kept;
      }
    }
    _next.startTag(name, attributes);
  }

  @override
  void endTag(String name) => _next.endTag(name);
}
