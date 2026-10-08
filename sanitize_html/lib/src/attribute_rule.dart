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

/// # TRUSTED: how the value of an allowed attribute is filtered.
///
/// An [AttributeRule] decides whether an attribute value is kept or dropped;
/// it never rewrites a value. Rewriting belongs in an `HtmlRewriter` that runs
/// before the sanitizer, see `rewriters.dart`. Because rules only keep or
/// drop, combining them is set algebra: a union keeps what either rule
/// keeps, an intersection what both keep, and a URL check can never be
/// followed by something that changes the URL.
library;

import 'url_policy.dart';

/// Decides whether the value of an allowed attribute is kept.
///
/// Used as the values of `ElementRule.attributes`:
///
/// ```dart
/// ElementRule(attributes: {
///   'href': AttributeRule.url(),
///   'title': AttributeRule.any(),
///   'class': AttributeRule.where((c) => c == 'hljs'),
/// })
/// ```
sealed class AttributeRule {
  const AttributeRule._();

  /// Keeps any value.
  const factory AttributeRule.any() = _Any;

  /// Keeps `http:`, `https:`, `mailto:` and relative URLs; with [where],
  /// only those for which it returns `true`.
  ///
  /// Required (in a checked `RuleSet`) for every URL-valued attribute such as
  /// `href`, `src` and `cite`; see `RuleSet` for the list.
  ///
  /// [where] receives the URL as the browser will parse it; values [Uri]
  /// cannot parse are dropped. The policy refuses the forms where [Uri] and
  /// browsers disagree about the host, so an allowlist on `uri.host` is
  /// sound. The host is not normalized (no IDNA mapping, no IPv4
  /// canonicalization), so a denylist is not.
  ///
  /// ```dart
  /// AttributeRule.url((uri) => uri.host == 'example.com')
  /// ```
  const factory AttributeRule.url([bool Function(Uri url)? where]) = _Url;

  /// Keeps a well-formed `srcset` whose every candidate URL passes [url];
  /// with [where], only if it returns `true` for the list of candidates.
  const factory AttributeRule.srcset([bool Function(List<Uri> urls)? where]) =
      _Srcset;

  /// Keeps values for which [allow] returns `true`.
  const factory AttributeRule.where(bool Function(String value) allow) = _Where;
}

final class _Any extends AttributeRule {
  const _Any() : super._();
}

final class _Url extends AttributeRule {
  final bool Function(Uri url)? where;
  const _Url([this.where]) : super._();
}

final class _Srcset extends AttributeRule {
  final bool Function(List<Uri> urls)? where;
  const _Srcset([this.where]) : super._();
}

final class _Where extends AttributeRule {
  final bool Function(String value) allow;
  const _Where(this.allow) : super._();
}

/// Keeps what either rule keeps; see [AttributeRuleExtension.union].
final class _Union extends AttributeRule {
  final AttributeRule a, b;
  const _Union(this.a, this.b) : super._();
}

/// Keeps what both rules keep; see [AttributeRuleExtension.intersection].
final class _Intersection extends AttributeRule {
  final AttributeRule a, b;
  const _Intersection(this.a, this.b) : super._();
}

/// Package-private operations on [AttributeRule]; not exported.
extension AttributeRuleExtension on AttributeRule {
  /// Whether an attribute with [value] is kept.
  bool keeps(String value) => switch (this) {
        _Any() => true,
        _Url(:final where) => switch (cleanUrl(value)) {
            null => false,
            final url => where == null || _parsed(url, where),
          },
        _Srcset(:final where) => switch (cleanSrcset(value)) {
            null => false,
            final urls => where == null || _allParsed(urls, where),
          },
        _Where(:final allow) => allow(value),
        _Union(:final a, :final b) => a.keeps(value) || b.keeps(value),
        _Intersection(:final a, :final b) => a.keeps(value) && b.keeps(value),
      };

  /// Whether every value this rule keeps is a URL accepted by the URL policy.
  bool get isUrlRestricted => switch (this) {
        _Url() => true,
        _Union(:final a, :final b) => a.isUrlRestricted && b.isUrlRestricted,
        _Intersection(:final a, :final b) =>
          a.isUrlRestricted || b.isUrlRestricted,
        _ => false,
      };

  /// Whether every value this rule keeps is a `srcset` accepted by the URL
  /// policy.
  bool get isSrcsetRestricted => switch (this) {
        _Srcset() => true,
        _Union(:final a, :final b) =>
          a.isSrcsetRestricted && b.isSrcsetRestricted,
        _Intersection(:final a, :final b) =>
          a.isSrcsetRestricted || b.isSrcsetRestricted,
        _ => false,
      };

  /// A rule keeping a value if this rule or [other] keeps it.
  AttributeRule union(AttributeRule other) => switch ((this, other)) {
        (_Any(), _) || (_, _Any()) => const AttributeRule.any(),
        _ when identical(this, other) => this,
        _ => _Union(this, other),
      };

  /// A rule keeping a value only if both this rule and [other] keep it.
  AttributeRule intersection(AttributeRule other) => switch ((this, other)) {
        (_Any(), final rule) || (final rule, _Any()) => rule,
        _ when identical(this, other) => this,
        _ => _Intersection(this, other),
      };
}

bool _parsed(String url, bool Function(Uri) where) {
  final uri = Uri.tryParse(url);
  return uri != null && where(uri);
}

bool _allParsed(List<String> urls, bool Function(List<Uri>) where) {
  final uris = <Uri>[];
  for (final url in urls) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }
    uris.add(uri);
  }
  return where(uris);
}
