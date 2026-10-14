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

/// # TRUSTED: which elements a sanitizer keeps.
library;

import 'rules/gfm.dart' show gfmRuleSet;
import 'rules/html.dart' show htmlRuleSet;
import 'grant_assertions.dart';
import 'html_writer.dart' show isWritableAttributeName, isWritableTagName;
import 'attribute_rule.dart';
import 'element_pattern.dart';
import 'element_rule.dart';

/// The elements a sanitizer keeps, and how their attributes are filtered.
///
/// For each element, an [ElementRule] filters attributes one by one, and
/// [ElementPattern]s name exact forms kept as exemptions. The first pattern
/// an element matches decides what it keeps; otherwise its rule does; an
/// element with neither is unwrapped: its tags are dropped, its content is
/// kept.
///
/// ```dart
/// final rules = RuleSet.gfm()
///     .union(RuleSet({
///       'video': ElementRule(attributes: {
///         'src': AttributeRule.url(),
///         'controls': AttributeRule.any(),
///       }),
///     }))
///     .withExemptions([
///       ElementPattern.iframe(
///         where: (src) => src.host == 'www.youtube.com',
///         sandbox: 'allow-scripts',
///       ),
///     ]);
/// ```
final class RuleSet {
  final Map<String, ElementRule> _rules;

  /// Exemptions by element name, in order of precedence.
  final Map<String, List<ElementPattern>> _patterns;

  /// Creates a rule set allowing exactly the elements in [rules], and the
  /// forms in [exemptions].
  ///
  /// Exemptions are for narrow forms the rules do not allow, such as an
  /// `<iframe>` from one origin; a matching exemption decides the element
  /// by itself, so it also keeps nothing the rules would have kept beyond
  /// what it lists. Do not use one to be stricter than the rules (a `rel`
  /// that links to other sites must carry, say); that belongs in an
  /// `HtmlRewriter`, which runs before the rules.
  ///
  /// Throws [ArgumentError] for names `HtmlWriter` cannot write (tag
  /// names must match `[a-z][a-z0-9._-]*`, attribute names
  /// `[a-z][a-z0-9_:.-]*`).
  ///
  /// Throws [UnsupportedError] for grants that defeat the purpose of
  /// sanitizing:
  ///
  ///  * elements `script`, `style`, `base`, `meta`, `link`, `html`, `head`,
  ///    `body`, `frameset`, `frame`, `form`, `object`, `embed`, `applet`,
  ///    `isindex`, `noscript`, `noembed`, `noframes`, `svg`, `math`;
  ///  * attributes `on*`, `style`, `srcdoc`, `is`, `form`, `formaction`,
  ///    `formtarget`, `formmethod`, `formenctype`, `ping`, `attributionsrc`,
  ///    `popovertarget`, `popovertargetaction`, `command`, `commandfor`,
  ///    `shadowrootmode`;
  ///  * URL-valued attributes (`href`, `src`, `cite`, `action`, `poster`,
  ///    `data`, ... and `srcset`) bound to anything but [AttributeRule.url]
  ///    (or [AttributeRule.srcset]).
  ///
  /// Use [RuleSet.unsafe] to waive these checks.
  RuleSet(
    Map<String, ElementRule> rules, {
    List<ElementPattern> exemptions = const [],
  }) : this._(rules, exemptions, checked: true);

  /// Creates a rule set allowing exactly the elements in [rules], without
  /// the grant checks of [RuleSet.new].
  ///
  /// The output is still well-formed and contains only these elements and
  /// attributes, but nothing stops the rules from allowing `<script>` or
  /// `onclick`. Only for callers who have reviewed what they allow.
  RuleSet.unsafe(
    Map<String, ElementRule> rules, {
    List<ElementPattern> exemptions = const [],
  }) : this._(rules, exemptions, checked: false);

  RuleSet._(
    Map<String, ElementRule> rules,
    List<ElementPattern> exemptions, {
    required bool checked,
  })  : _rules = Map.unmodifiable({
          for (final MapEntry(key: name, value: rule) in rules.entries)
            name: ElementRule(attributes: Map.unmodifiable(rule.attributes)),
        }),
        _patterns = _byTagName([
          for (final pattern in exemptions)
            ElementPattern(
              pattern.tagName,
              match: Map.unmodifiable(pattern.match),
              attributes: Map.unmodifiable(pattern.attributes),
            ),
        ]) {
    for (final MapEntry(key: name, value: rule) in rules.entries) {
      _check(name, rule.attributes, checked: checked);
    }
    for (final pattern in exemptions) {
      _check(pattern.tagName, pattern.match,
          checked: checked, parameter: 'exemptions');
      _check(pattern.tagName, pattern.attributes,
          checked: checked, parameter: 'exemptions');
      for (final attribute in pattern.attributes.keys) {
        if (pattern.match.containsKey(attribute)) {
          throw ArgumentError.value(
            attribute,
            'exemptions',
            'both matched and optional on <${pattern.tagName}>',
          );
        }
      }
    }
  }

  static void _check(
    String name,
    Map<String, AttributeRule> attributes, {
    required bool checked,
    String parameter = 'rules',
  }) {
    if (!isWritableTagName(name)) {
      throw ArgumentError.value(name, parameter, 'not a writable tag name');
    }
    for (final attribute in attributes.keys) {
      if (!isWritableAttributeName(attribute)) {
        throw ArgumentError.value(
          attribute,
          parameter,
          'not a writable attribute name on <$name>',
        );
      }
    }
    if (checked) {
      checkGrants(name, attributes);
    }
  }

  static Map<String, List<ElementPattern>> _byTagName(
    Iterable<ElementPattern> patterns,
  ) {
    final result = <String, List<ElementPattern>>{};
    for (final pattern in patterns) {
      (result[pattern.tagName] ??= []).add(pattern);
    }
    return Map.unmodifiable({
      for (final MapEntry(key: name, value: list) in result.entries)
        name: List<ElementPattern>.unmodifiable(list),
    });
  }

  RuleSet._combined(this._rules, this._patterns);

  /// The rules for Markdown rendered by `package:markdown` with
  /// `ExtensionSet.gitHubWeb` or `gitHubFlavored`, raw HTML included.
  ///
  /// Elements and attributes follow [html-pipeline][1], the open-source
  /// origin of GitHub's Markdown pipeline, plus what `package:markdown`
  /// emits. Attributes that reach outside the content are not kept:
  ///
  ///  * `id` only with the `user-content-` prefix (`HtmlRewriter.prefixIds`
  ///    adds it), `name` never;
  ///  * `class` only with `markdown-*` tokens, and `language-*` on `<code>`;
  ///  * `rel` only with the link types defined for `<a>`, never `opener`;
  ///  * no `accesskey`, `tabindex`, `for`, `usemap`, `aria-describedby`,
  ///    `aria-labelledby` or form attributes;
  ///  * `<input>` only as `type="checkbox"`.
  ///
  /// [1]: https://github.com/gjtorikian/html-pipeline/blob/c99d76dbfe817598387c371af342e25abdccd363/lib/html_pipeline/sanitization_filter.rb
  factory RuleSet.gfm() => gfmRuleSet;

  /// The rules for arbitrary HTML: everything that cannot reach outside the
  /// sanitized content.
  ///
  /// The element and attribute tables of [safevalues][1], Google's HTML
  /// sanitizer, verbatim, with URL attributes checked by this package's
  /// policy, `rel` limited to the link types defined for `<a>`, `target` to
  /// `_self`/`_blank`, and no `<link>`. Like safevalues it keeps no `id`,
  /// `name`, `class` or `style`, and no `<iframe>`, `<form>`, `<input>`,
  /// `<button>`, `<textarea>` or `<label>`; add what the host can afford
  /// with [union].
  ///
  /// [1]: https://github.com/google/safevalues/blob/main/src/builders/html_sanitizer/sanitizer_table/default_sanitizer_table.ts
  factory RuleSet.html() => htmlRuleSet;

  /// A rule set allowing what either rule set allows.
  ///
  /// For an element with a rule in both, an attribute is kept if either
  /// rule keeps it. Exemptions of both are kept as they are, this rule
  /// set's first. Narrow with [without] and [restrict].
  ///
  /// A union with a [RuleSet.unsafe] is as unsafe as that rule set.
  RuleSet union(RuleSet other) => RuleSet._combined(
        Map.unmodifiable({
          ..._rules,
          for (final MapEntry(key: name, value: rule) in other._rules.entries)
            name: switch (_rules[name]) {
              null => rule,
              final mine => mine.union(rule),
            },
        }),
        Map.unmodifiable({
          ..._patterns,
          for (final MapEntry(key: name, value: theirs)
              in other._patterns.entries)
            name: List<ElementPattern>.unmodifiable(
              [...?_patterns[name], ...theirs],
            ),
        }),
      );

  /// This rule set without the elements in [elements]: neither their rules
  /// nor their exemptions.
  ///
  /// ```dart
  /// RuleSet.gfm().without({'img', 'picture', 'source'})
  /// ```
  RuleSet without(Set<String> elements) => RuleSet._combined(
        Map.unmodifiable({
          for (final MapEntry(key: name, value: rule) in _rules.entries)
            if (!elements.contains(name)) name: rule,
        }),
        Map.unmodifiable({
          for (final MapEntry(key: name, value: patterns) in _patterns.entries)
            if (!elements.contains(name)) name: patterns,
        }),
      );

  /// This rule set with the rule for [element] narrowed by [rule]: an
  /// attribute [rule] names is kept only if both rules keep it; attributes
  /// it does not name, other elements, and exemptions are unchanged.
  ///
  /// ```dart
  /// RuleSet.gfm().restrict('a', ElementRule(attributes: {
  ///   'href': AttributeRule.url((u) => u.host == 'pub.dev'),
  /// }))
  /// ```
  ///
  /// Throws [ArgumentError] if this rule set has no rule for [element], or
  /// [rule] names an attribute that rule does not have: a restriction can
  /// only narrow.
  RuleSet restrict(String element, ElementRule rule) {
    final mine = _rules[element];
    if (mine == null) {
      throw ArgumentError.value(element, 'element', 'has no rule to restrict');
    }
    for (final name in rule.attributes.keys) {
      if (!mine.attributes.containsKey(name)) {
        throw ArgumentError.value(
          name,
          'rule',
          'not an attribute of <$element> in this rule set',
        );
      }
    }
    return RuleSet._combined(
      Map.unmodifiable({
        ..._rules,
        element: ElementRule(attributes: {
          for (final MapEntry(key: name, value: theirs)
              in mine.attributes.entries)
            name: switch (rule.attributes[name]) {
              null => theirs,
              final narrower => theirs.intersection(narrower),
            },
        }),
      }),
      _patterns,
    );
  }

  /// This rule set with [exemptions] added after its own.
  ///
  /// The same as a [union] with a rule set holding only [exemptions].
  RuleSet withExemptions(List<ElementPattern> exemptions) =>
      union(RuleSet(const {}, exemptions: exemptions));
}

/// Package-private operations on [RuleSet]; not exported.
extension RuleSetExtension on RuleSet {
  /// The attributes an element called [name] keeps, or `null` if it is
  /// unwrapped.
  ///
  /// [attributes] may be modified and returned.
  Map<String, String>? apply(String name, Map<String, String> attributes) {
    for (final pattern in _patterns[name] ?? const <ElementPattern>[]) {
      if (pattern.matches(attributes)) {
        return pattern.apply(attributes);
      }
    }
    return _rules[name]?.apply(attributes);
  }
}
