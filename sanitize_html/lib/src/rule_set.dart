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
import 'html_rules.dart' show htmlRuleSet;
import 'grant_assertions.dart';
import 'html_writer.dart' show isWritableAttributeName, isWritableTagName;
import 'attribute_rule.dart';
import 'element_rule.dart';

/// The elements a sanitizer keeps, and how their attributes are filtered.
///
/// An element without a rule, or whose `ElementRule.requires` is not met,
/// is unwrapped: its tags are dropped, its content is kept.
///
/// ```dart
/// final rules = RuleSet.gfm().union(RuleSet({
///   'iframe': ElementRule(attributes: {
///     'src': AttributeRule.url((u) => u.host == 'www.youtube.com'),
///     'width': AttributeRule.any(),
///     'height': AttributeRule.any(),
///   }),
/// }));
/// ```
final class RuleSet {
  final Map<String, ElementRule> _rules;

  /// Creates a rule set allowing exactly the elements in [rules].
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
  RuleSet(Map<String, ElementRule> rules) : this._(rules, checked: true);

  /// Creates a rule set allowing exactly the elements in [rules], without
  /// the grant checks of [RuleSet.new].
  ///
  /// The output is still well-formed and contains only these elements and
  /// attributes, but nothing stops the rules from allowing `<script>` or
  /// `onclick`. Only for callers who have reviewed what they allow.
  RuleSet.unsafe(Map<String, ElementRule> rules)
      : this._(rules, checked: false);

  RuleSet._(Map<String, ElementRule> rules, {required bool checked})
      : _rules = Map.unmodifiable(rules) {
    for (final MapEntry(key: name, value: rule) in rules.entries) {
      if (!isWritableTagName(name)) {
        throw ArgumentError.value(name, 'rules', 'not a writable tag name');
      }
      for (final (:attributes, :requires) in rule.leaves) {
        for (final attribute in attributes.keys) {
          if (!isWritableAttributeName(attribute)) {
            throw ArgumentError.value(
              attribute,
              'rules',
              'not a writable attribute name on <$name>',
            );
          }
        }
        for (final attribute in requires) {
          if (!attributes.containsKey(attribute)) {
            throw ArgumentError.value(
              attribute,
              'rules',
              'required on <$name> but has no attribute rule',
            );
          }
        }
        if (checked) {
          checkGrants(name, attributes);
        }
      }
    }
  }

  RuleSet._combined(this._rules);

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

  /// An `<iframe>` rule for embeds from origins [where] accepts, to [union]
  /// with another rule set.
  ///
  /// The frame is kept only with a `src` for which [where] returns `true`
  /// and a `sandbox` attribute equal to [sandbox]; otherwise it is
  /// unwrapped. `width`, `height`, `title`, `loading` and `allowfullscreen`
  /// are kept. Nothing else: `allow` would delegate the host's permissions,
  /// `name` would catch the host's `target`s.
  ///
  /// ```dart
  /// RuleSet.gfm().union(RuleSet.iframe(
  ///   where: (src) =>
  ///       src.host == 'www.youtube.com' && src.path.startsWith('/embed/'),
  ///   sandbox: 'allow-scripts',
  /// ))
  /// ```
  ///
  /// Authors rarely write `sandbox`; set it with a rewriter before the
  /// rules: `HtmlRewriter.attributes('iframe', (a) => a['sandbox'] =
  /// 'allow-scripts')`. Never grant `allow-same-origin` together with
  /// `allow-scripts` to a frame from the host's own origin: it could remove
  /// its sandbox.
  factory RuleSet.iframe({
    required bool Function(Uri src) where,
    String sandbox = '',
  }) =>
      RuleSet({
        'iframe': ElementRule(
          requires: const {'src', 'sandbox'},
          attributes: {
            'src': AttributeRule.url(where),
            'sandbox': AttributeRule.where((value) => value == sandbox),
            'allowfullscreen': const AttributeRule.any(),
            'height': const AttributeRule.any(),
            'loading': AttributeRule.where(const {'eager', 'lazy'}.contains),
            'title': const AttributeRule.any(),
            'width': const AttributeRule.any(),
          },
        ),
      });

  /// A rule set allowing elements allowed by either rule set.
  ///
  /// For an element in both, an attribute is kept if either rule keeps it,
  /// and the element is kept if either rule's requirements are met.
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
  ///
  /// Sanitizing with it is the same as sanitizing with this rule set and
  /// then with [other]; an element must meet the requirements of both.
  RuleSet intersection(RuleSet other) => RuleSet._combined(Map.unmodifiable({
        for (final MapEntry(key: name, value: rule) in _rules.entries)
          if (other._rules[name] case final theirs?)
            name: rule.intersection(theirs),
      }));
}

/// Package-private operations on [RuleSet]; not exported.
extension RuleSetExtension on RuleSet {
  /// The rule for an element called [name], or `null` if it must be dropped.
  ElementRule? lookup(String name) => _rules[name];
}
