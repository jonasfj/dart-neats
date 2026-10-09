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

/// # TRUSTED: whether an allowed element is kept, and with which attributes.
///
/// Like `AttributeRule`, an [ElementRule] only keeps or drops; combining
/// rules is set algebra. Unlike attribute rules, [ElementRule.requires]
/// makes keeping the element depend on its attributes, so a union cannot be
/// flattened into one rule: `A` requiring `src` and `sandbox` and `B`
/// requiring `src` would flatten to "requires `src`", keeping an element
/// neither accepts. Unions and intersections are therefore kept as nodes
/// and evaluated against both rules.
library;

import 'attribute_rule.dart';

/// The attributes an allowed element keeps, and how each is filtered.
///
/// Attributes not in [attributes] are dropped. An element is kept only if
/// every attribute in [requires] is present and kept by its rule; otherwise
/// the element is unwrapped like an element without a rule.
///
/// ```dart
/// const ElementRule(attributes: {
///   'href': AttributeRule.url(),
///   'title': AttributeRule.any(),
/// })
///
/// ElementRule(
///   requires: {'src', 'sandbox'},
///   attributes: {
///     'src': AttributeRule.url((u) => u.host == 'www.youtube.com'),
///     'sandbox': AttributeRule.where((v) => v == 'allow-scripts'),
///   },
/// )
/// ```
sealed class ElementRule {
  const ElementRule._();

  /// A rule keeping the attributes in [attributes], if those in [requires]
  /// are present and kept.
  ///
  /// Every name in [requires] must be a key of [attributes].
  const factory ElementRule({
    Map<String, AttributeRule> attributes,
    Set<String> requires,
  }) = _Rule;
}

final class _Rule extends ElementRule {
  final Map<String, AttributeRule> attributes;
  final Set<String> requires;

  const _Rule({this.attributes = const {}, this.requires = const {}})
      : super._();
}

/// Keeps what either rule keeps; see [ElementRuleExtension.union].
final class _Union extends ElementRule {
  final ElementRule a, b;

  const _Union(this.a, this.b) : super._();
}

/// Applies [a], then [b]; see [ElementRuleExtension.intersection].
final class _Intersection extends ElementRule {
  final ElementRule a, b;

  const _Intersection(this.a, this.b) : super._();
}

/// Package-private operations on [ElementRule]; not exported.
extension ElementRuleExtension on ElementRule {
  /// The attribute rules and requirements of every rule this rule is built
  /// from, for validation.
  Iterable<({Map<String, AttributeRule> attributes, Set<String> requires})>
      get leaves sync* {
    switch (this) {
      case _Rule(:final attributes, :final requires):
        yield (attributes: attributes, requires: requires);
      case _Union(:final a, :final b) || _Intersection(:final a, :final b):
        yield* a.leaves;
        yield* b.leaves;
    }
  }

  /// The attributes the element keeps, or `null` if the element is not kept.
  ///
  /// [attributes] may be modified and returned.
  Map<String, String>? apply(Map<String, String> attributes) {
    switch (this) {
      case _Rule(attributes: final rules, :final requires):
        if (attributes.isNotEmpty) {
          attributes.removeWhere(
            (name, value) => !(rules[name]?.keeps(value) ?? false),
          );
        }
        for (final name in requires) {
          if (!attributes.containsKey(name)) {
            return null;
          }
        }
        return attributes;
      case _Union(:final a, :final b):
        final byA = a.apply(Map.of(attributes));
        final byB = b.apply(attributes);
        if (byA == null) {
          return byB;
        }
        if (byB == null) {
          return byA;
        }
        return byA..addAll(byB);
      case _Intersection(:final a, :final b):
        final byA = a.apply(attributes);
        return byA == null ? null : b.apply(byA);
    }
  }

  /// A rule keeping the element if this rule or [other] keeps it, with the
  /// attributes kept by either.
  ElementRule union(ElementRule other) => switch ((this, other)) {
        (
          _Rule(attributes: final mine, requires: const {}),
          _Rule(attributes: final theirs, requires: const {}),
        ) =>
          ElementRule(attributes: {
            ...mine,
            for (final MapEntry(key: name, value: rule) in theirs.entries)
              name: switch (mine[name]) {
                null => rule,
                final rule_ => rule_.union(rule),
              },
          }),
        _ => _Union(this, other),
      };

  /// A rule keeping what is left after applying this rule and then [other].
  ElementRule intersection(ElementRule other) => switch ((this, other)) {
        (
          _Rule(attributes: final mine, requires: const {}),
          _Rule(attributes: final theirs, requires: const {}),
        ) =>
          ElementRule(attributes: {
            for (final MapEntry(key: name, value: rule) in mine.entries)
              if (theirs[name] case final rule_?)
                name: rule.intersection(rule_),
          }),
        _ => _Intersection(this, other),
      };
}
