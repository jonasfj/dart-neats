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
/// An [AttributeRule] decides whether an attribute value is kept or dropped.
/// Rules never rewrite values ([AttributeRule.tokens] is the one exception:
/// it drops individual tokens); rewriting belongs in a transformer that runs
/// before the sanitizer, see `rewriters.dart`.
library;

import 'url_policy.dart';

/// Decides whether the value of an allowed attribute is kept.
///
/// Used as the values of `TagRule.attributes`:
///
/// ```dart
/// TagRule(attributes: {
///   'href': AttributeRule.url,
///   'title': AttributeRule.any,
///   'class': AttributeRule.tokens((c) => c.startsWith('hljs-')),
/// })
/// ```
sealed class AttributeRule {
  const AttributeRule._();

  /// Keeps any value.
  static const AttributeRule any = _Any();

  /// Keeps `http:`, `https:`, `mailto:` and relative URLs.
  ///
  /// Required (in a checked `RuleSet`) for every URL-valued attribute such as
  /// `href`, `src` and `cite`; see `RuleSet` for the list.
  static const AttributeRule url = _Url();

  /// Keeps a well-formed `srcset` whose every candidate URL passes [url].
  static const AttributeRule srcset = _Srcset();

  /// Keeps values that pass [url] and for which [allow] returns `true`.
  ///
  /// [allow] receives the result of [Uri.tryParse]; values it cannot parse
  /// are dropped. Because [url] refuses URLs where RFC 3986 and the WHATWG
  /// URL Standard disagree, `uri.scheme` and `uri.host` are what the browser
  /// will use.
  ///
  /// ```dart
  /// AttributeRule.urlWhere((uri) => uri.host == 'example.com')
  /// ```
  const factory AttributeRule.urlWhere(bool Function(Uri url) allow) =
      _UrlWhere;

  /// Keeps values for which [allow] returns `true`.
  const factory AttributeRule.where(bool Function(String value) allow) = _Where;

  /// Keeps the ASCII-whitespace separated tokens for which [allow] returns
  /// `true`; drops the attribute when none remain.
  ///
  /// For `class`, `rel` and similar token lists.
  const factory AttributeRule.tokens(bool Function(String token) allow) =
      _Tokens;
}

final class _Any extends AttributeRule {
  const _Any() : super._();
}

final class _Url extends AttributeRule {
  const _Url() : super._();
}

final class _Srcset extends AttributeRule {
  const _Srcset() : super._();
}

final class _UrlWhere extends AttributeRule {
  final bool Function(Uri url) allow;
  const _UrlWhere(this.allow) : super._();
}

final class _Where extends AttributeRule {
  final bool Function(String value) allow;
  const _Where(this.allow) : super._();
}

final class _Tokens extends AttributeRule {
  final bool Function(String token) allow;
  const _Tokens(this.allow) : super._();
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
  /// The value to emit for an attribute with [value], or `null` to drop the
  /// attribute.
  ///
  /// Returns [value] itself whenever nothing is removed.
  String? apply(String value) => switch (this) {
        _Any() => value,
        _Url() => isSafeUrl(value) ? value : null,
        _Srcset() => isSafeSrcset(value) ? value : null,
        _UrlWhere(:final allow) => _isAllowedUrl(value, allow) ? value : null,
        _Where(:final allow) => allow(value) ? value : null,
        _Tokens(:final allow) => _filterTokens(value, allow),
        _Union(:final a, :final b) => switch ((a, b)) {
            (_Tokens(allow: final x), _Tokens(allow: final y)) =>
              _filterTokens(value, (t) => x(t) || y(t)),
            _ => a.apply(value) ?? b.apply(value),
          },
        _Intersection(:final a, :final b) => switch (a.apply(value)) {
            null => null,
            final v => b.apply(v),
          },
      };

  /// Whether every value this rule keeps is a URL accepted by the URL policy.
  bool get isUrlRestricted => switch (this) {
        _Url() || _UrlWhere() => true,
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
  ///
  /// Two [AttributeRule.tokens] rules combine per token; otherwise the value
  /// is that of this rule if it keeps it, else that of [other].
  AttributeRule union(AttributeRule other) =>
      identical(this, other) ? this : _Union(this, other);

  /// A rule keeping a value only if this rule keeps it and [other] keeps
  /// what this rule kept.
  AttributeRule intersection(AttributeRule other) =>
      identical(this, other) ? this : _Intersection(this, other);
}

/// Whether [value] passes the URL policy, parses, and [allow] accepts it.
bool _isAllowedUrl(String value, bool Function(Uri) allow) {
  if (!isSafeUrl(value)) {
    return false;
  }
  final uri = Uri.tryParse(value);
  return uri != null && allow(uri);
}

/// `value` with the tokens [allow] rejects removed, `value` itself if none
/// is rejected, or `null` if no token remains.
String? _filterTokens(String value, bool Function(String) allow) {
  List<String>? kept;
  var removed = false;
  var start = 0;
  final n = value.length;
  while (start < n) {
    while (start < n && _isAsciiWhitespace(value.codeUnitAt(start))) {
      start++;
    }
    var end = start;
    while (end < n && !_isAsciiWhitespace(value.codeUnitAt(end))) {
      end++;
    }
    if (end > start) {
      final token = value.substring(start, end);
      if (allow(token)) {
        (kept ??= []).add(token);
      } else {
        removed = true;
      }
    }
    start = end;
  }
  if (kept == null) {
    return null;
  }
  // Leading, trailing or repeated whitespace is also normalized away when
  // something was removed; otherwise the value is kept verbatim.
  return removed ? kept.join(' ') : value;
}

bool _isAsciiWhitespace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D;
