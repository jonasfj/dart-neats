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

/// # TRUSTED: an exact form of an element that is kept regardless of rules.
///
/// A pattern is judged on the element as written, with the pattern's own
/// attribute rules, and is never merged with other rules: a union keeps the
/// patterns of both sides as they are, an intersection keeps only patterns
/// present in both. Nothing can loosen what a pattern matches once it is
/// written.
library;

import 'attribute_rule.dart';

/// An element kept in one exact form, as an exemption from the rules.
///
/// Matches an element called [tagName] whose attributes include every
/// attribute in [match], each passing its rule, judged on the element as
/// written. A matching element keeps the attributes in [match] and those in
/// [attributes] that pass; everything else is dropped. A pattern is tried
/// before the element's `ElementRule`, and the first matching pattern
/// decides.
///
/// Use a pattern where an element is only acceptable in a particular form,
/// which a per-attribute rule cannot say:
///
/// ```dart
/// // An <input> only as a checkbox.
/// ElementPattern('input', match: {
///   'type': AttributeRule.where((v) => v == 'checkbox'),
/// }, attributes: {
///   'checked': AttributeRule.any(),
///   'disabled': AttributeRule.any(),
/// })
///
/// // An <iframe> only from one origin, and only sandboxed.
/// ElementPattern('iframe', match: {
///   'src': AttributeRule.url((u) => u.host == 'www.youtube.com'),
///   'sandbox': AttributeRule.where((v) => v == 'allow-scripts'),
/// }, attributes: {
///   'width': AttributeRule.any(),
///   'height': AttributeRule.any(),
/// })
/// ```
///
/// Patterns are never merged with other rules, so a `RuleSet.union` with
/// a rule set allowing `src` from another origin cannot make the pattern
/// above match a frame from that origin. Two acceptable forms are two
/// patterns. And exemptions do not compose: `RuleSet.intersection` keeps
/// only exemptions present in *both* rule sets ([==]); any other
/// disappears, whatever the rules say. Add exemptions after intersecting,
/// with `RuleSet.withExemptions`.
final class ElementPattern {
  /// The element this pattern applies to.
  final String tagName;

  /// Attributes that must be present and pass their rule.
  final Map<String, AttributeRule> match;

  /// Attributes kept when present and passing their rule.
  final Map<String, AttributeRule> attributes;

  const ElementPattern(
    this.tagName, {
    required this.match,
    this.attributes = const {},
  });

  /// `<input type="checkbox">`, optionally `checked` and `disabled`: the
  /// one form of `<input>` that cannot be submitted or typed into.
  static const checkbox = ElementPattern(
    'input',
    match: {'type': AttributeRule.where(_isCheckbox)},
    attributes: {
      'checked': AttributeRule.any(),
      'disabled': AttributeRule.any(),
    },
  );

  /// An `<iframe>` embed from an origin [where] accepts, with a `sandbox`
  /// attribute equal to [sandbox]; `width`, `height`, `title`, `loading` and
  /// `allowfullscreen` are kept. Nothing else: `allow` would delegate the
  /// host's permissions, `name` would catch the host's `target`s.
  ///
  /// ```dart
  /// RuleSet.gfm().withExemptions([
  ///   ElementPattern.iframe(
  ///     where: (src) =>
  ///         src.host == 'www.youtube.com' && src.path.startsWith('/embed/'),
  ///     sandbox: 'allow-scripts',
  ///   ),
  /// ])
  /// ```
  ///
  /// Authors rarely write `sandbox`; set it with a rewriter before the
  /// rules: `HtmlRewriter.attributes('iframe', (a) => a['sandbox'] =
  /// 'allow-scripts')`. Never grant `allow-same-origin` together with
  /// `allow-scripts` to a frame from the host's own origin: it could remove
  /// its sandbox.
  factory ElementPattern.iframe({
    required bool Function(Uri src) where,
    String sandbox = '',
  }) =>
      ElementPattern(
        'iframe',
        match: {
          'src': AttributeRule.url(where),
          'sandbox': AttributeRule.where((value) => value == sandbox),
        },
        attributes: {
          'allowfullscreen': const AttributeRule.any(),
          'height': const AttributeRule.any(),
          'loading': AttributeRule.where(const {'eager', 'lazy'}.contains),
          'title': const AttributeRule.any(),
          'width': const AttributeRule.any(),
        },
      );

  /// Whether [other] is the same pattern: the same object, or the same tag
  /// with the same attribute names bound to the same [AttributeRule]
  /// objects.
  ///
  /// Attribute rules are compared by identity, never by what they would
  /// decide, so two patterns built separately with `AttributeRule.where`
  /// are not equal. Keep a pattern in one place and reuse it.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ElementPattern &&
          tagName == other.tagName &&
          _sameRules(match, other.match) &&
          _sameRules(attributes, other.attributes);

  @override
  int get hashCode => Object.hash(
        tagName,
        Object.hashAllUnordered(match.keys),
        Object.hashAllUnordered(attributes.keys),
      );
}

bool _isCheckbox(String value) => value == 'checkbox';

bool _sameRules(Map<String, AttributeRule> a, Map<String, AttributeRule> b) =>
    a.length == b.length &&
    a.entries.every((e) => identical(b[e.key], e.value));

/// Package-private operations on [ElementPattern]; not exported.
extension ElementPatternExtension on ElementPattern {
  /// Whether [attributes] contains every matched attribute, passing its rule.
  bool matches(Map<String, String> attributes) {
    for (final MapEntry(key: name, value: rule) in match.entries) {
      final value = attributes[name];
      if (value == null || !rule.keeps(value)) {
        return false;
      }
    }
    return true;
  }

  /// Removes the attributes this pattern does not keep from [attributes],
  /// which it must [match], and returns it.
  Map<String, String> apply(Map<String, String> attributes) {
    if (attributes.isEmpty) {
      return attributes;
    }
    attributes.removeWhere(
      (name, value) =>
          !match.containsKey(name) &&
          !(this.attributes[name]?.keeps(value) ?? false),
    );
    return attributes;
  }
}
