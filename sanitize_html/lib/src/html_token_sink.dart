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

/// The token interface everything in this package speaks.
///
/// A tokenizer pushes tokens into an [HtmlTokenSink]; rewriters are sinks
/// that push into the next sink; `HtmlWriter` is the sink that produces
/// output.
library;

/// Receives HTML tokens.
///
/// There are exactly three kinds of token, matching what `HtmlWriter` can
/// write: comments, doctypes and CDATA sections are not tokens.
abstract base class HtmlTokenSink {
  /// Text `source[start..end)` as written in HTML source, _undecoded_: it is
  /// the text as the HTML data state would see it, so `&amp;` is five
  /// characters here, not one.
  void text(String source, int start, int end);

  /// A start tag.
  ///
  /// [name] and the keys of [attributes] are lowercase; values are decoded.
  /// The sink takes ownership of [attributes]: it may mutate the map, must
  /// consume it synchronously and must not retain it. A tag without
  /// attributes may be passed a shared `const` map.
  void startTag(String name, Map<String, String> attributes);

  /// An end tag.
  void endTag(String name);
}
