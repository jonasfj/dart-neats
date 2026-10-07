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

import 'gfm_rules.dart' show gfmRuleSet;
import 'grant_assertions.dart';
import 'sane_html_writer.dart' show isWritableAttributeName, isWritableTagName;
import 'tag_rule.dart';

/// The elements a sanitizer keeps, and how their attributes are filtered.
///
/// Elements without a rule are removed together with their content.
///
/// ```dart
/// final rules = RuleSet.gfm().union(RuleSet({
///   'iframe': TagRule(attributes: {
///     'src': AttributeRule.urlWhere((u) => u.host == 'www.youtube.com'),
///     'width': AttributeRule.any,
///     'height': AttributeRule.any,
///   }),
/// }));
/// ```
final class RuleSet {
  final Map<String, TagRule> _rules;

  /// Creates a rule set allowing exactly the elements in [rules].
  ///
  /// Throws [ArgumentError] for names `SaneHtmlWriter` cannot write (tag
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
  ///    `formtarget`, `formmethod`, `formenctype`, `ping`, `attributionsrc`;
  ///  * URL-valued attributes (`href`, `src`, `cite`, `action`, `poster`,
  ///    `data`, ... and `srcset`) bound to anything but [AttributeRule.url],
  ///    [AttributeRule.urlWhere] (or [AttributeRule.srcset]).
  ///
  /// Use [RuleSet.unsafe] to waive these checks.
  RuleSet(Map<String, TagRule> rules) : this._(rules, checked: true);

  /// Creates a rule set allowing exactly the elements in [rules], without
  /// the grant checks of [RuleSet.new].
  ///
  /// The output is still well-formed and contains only these elements and
  /// attributes, but nothing stops the rules from allowing `<script>` or
  /// `onclick`. Only for callers who have reviewed what they allow.
  RuleSet.unsafe(Map<String, TagRule> rules) : this._(rules, checked: false);

  RuleSet._(Map<String, TagRule> rules, {required bool checked})
      : _rules = Map.unmodifiable(rules) {
    for (final MapEntry(key: name, value: rule) in rules.entries) {
      if (!isWritableTagName(name)) {
        throw ArgumentError.value(name, 'rules', 'not a writable tag name');
      }
      for (final attribute in rule.attributes.keys) {
        if (!isWritableAttributeName(attribute)) {
          throw ArgumentError.value(
            attribute,
            'rules',
            'not a writable attribute name on <$name>',
          );
        }
      }
      if (checked) {
        checkGrants(name, rule);
      }
    }
  }

  RuleSet._combined(this._rules);

  /// Rules modelled on the [sanitization GitHub applies to Markdown][1].
  ///
  /// `id` attributes are kept only if [allowElementId] accepts them, and
  /// `class` attributes only keep the class names [allowClassName] accepts.
  ///
  /// [1]: https://github.com/jch/html-pipeline/blob/master/lib/html/pipeline/sanitization_filter.rb
  factory RuleSet.gfm({
    bool Function(String id)? allowElementId,
    bool Function(String className)? allowClassName,
  }) =>
      gfmRuleSet(
        allowElementId: allowElementId,
        allowClassName: allowClassName,
      );

  /// A rule set allowing elements allowed by either rule set.
  ///
  /// For an element in both, an attribute is kept if either rule keeps it;
  /// two [AttributeRule.tokens] rules combine per token, otherwise the value
  /// is that of this rule set's rule if it keeps it, else the other's.
  ///
  /// A union with a [RuleSet.unsafe] is as unsafe as that rule set.
  RuleSet union(RuleSet other) => RuleSet._combined(Map.unmodifiable({
        ..._rules,
        for (final MapEntry(key: name, value: rule) in other._rules.entries)
          name: switch (_rules[name]) {
            null => rule,
            final mine => mine.union(rule),
          },
      }));

  /// A rule set allowing only elements allowed by both rule sets, keeping
  /// only attributes kept by both rules.
  RuleSet intersection(RuleSet other) => RuleSet._combined(Map.unmodifiable({
        for (final MapEntry(key: name, value: rule) in _rules.entries)
          if (other._rules[name] case final theirs?)
            name: rule.intersection(theirs),
      }));
}

/// Package-private operations on [RuleSet]; not exported.
extension RuleSetExtension on RuleSet {
  /// The rule for an element called [name], or `null` if it must be dropped.
  TagRule? lookup(String name) => _rules[name];
}
