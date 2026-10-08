// Copyright 2019 Google LLC
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

/// # TRUSTED (policy data): the default rules, modelled on GitHub's.
///
/// Elements and attributes follow the allowlist of [html-pipeline][1], the
/// sanitizer GitHub applies to rendered Markdown, with these deliberate
/// differences:
///
///  * `name` is only allowed on `<a>`. On `img`, `form`, `embed`, `object`
///    and `iframe` a `name` creates a [property on `window`][2] and
///    `document` (DOM clobbering, e.g. `<img name="getElementById">`).
///  * Form related attributes (`action`, `method`, `enctype`, `accept`,
///    `accept-charset`, `for`, `prompt`) are dropped since no form element
///    is allowed, as is `usemap` (no `<map>`) and `accesskey` (hijacks the
///    host page's keyboard shortcuts).
///  * `id` and `class` are only kept when the caller asks for them, because
///    the host page's CSS and scripts select on them.
///  * `rel` must consist of the [link types][3] the HTML specification
///    defines for `<a>` (plus `ugc` and `sponsored`), except `opener`, which
///    re-enables `window.opener` for `target="_blank"` links.
///
/// The rule set is built with `RuleSet()`, so it is subject to the same grant
/// assertions as any user rule set.
///
/// [1]: https://github.com/jch/html-pipeline/blob/master/lib/html/pipeline/sanitization_filter.rb
/// [2]: https://html.spec.whatwg.org/multipage/nav-history-apis.html#named-access-on-the-window-object
/// [3]: https://html.spec.whatwg.org/multipage/links.html#linkTypes
library;

import 'attribute_rule.dart';
import 'rule_set.dart';
import 'element_rule.dart';

const _elements = <String>{
  'a',
  'abbr',
  'b',
  'bdo',
  'blockquote',
  'br',
  'caption',
  'cite',
  'code',
  'dd',
  'del',
  'details',
  'dfn',
  'div',
  'dl',
  'dt',
  'em',
  'figcaption',
  'figure',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'h7',
  'h8',
  'hr',
  'i',
  'img',
  'ins',
  'kbd',
  'li',
  'mark',
  'ol',
  'p',
  'picture',
  'pre',
  'q',
  'rp',
  'rt',
  'ruby',
  's',
  'samp',
  'small',
  'source',
  'span',
  'strike',
  'strong',
  'sub',
  'summary',
  'sup',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'time',
  'tr',
  'tt',
  'ul',
  'var',
  'wbr',
};

/// Attributes allowed on every element.
const _globalAttributes = <String, AttributeRule>{
  'abbr': AttributeRule.any(),
  'align': AttributeRule.any(),
  'alt': AttributeRule.any(),
  'aria-describedby': AttributeRule.any(),
  'aria-hidden': AttributeRule.any(),
  'aria-label': AttributeRule.any(),
  'aria-labelledby': AttributeRule.any(),
  'axis': AttributeRule.any(),
  'border': AttributeRule.any(),
  'cellpadding': AttributeRule.any(),
  'cellspacing': AttributeRule.any(),
  'char': AttributeRule.any(),
  'charoff': AttributeRule.any(),
  'charset': AttributeRule.any(),
  'checked': AttributeRule.any(),
  'clear': AttributeRule.any(),
  'cols': AttributeRule.any(),
  'colspan': AttributeRule.any(),
  'color': AttributeRule.any(),
  'compact': AttributeRule.any(),
  'coords': AttributeRule.any(),
  'datetime': AttributeRule.any(),
  'dir': AttributeRule.any(),
  'disabled': AttributeRule.any(),
  'frame': AttributeRule.any(),
  'headers': AttributeRule.any(),
  'height': AttributeRule.any(),
  'hreflang': AttributeRule.any(),
  'hspace': AttributeRule.any(),
  'ismap': AttributeRule.any(),
  'itemprop': AttributeRule.any(),
  'label': AttributeRule.any(),
  'lang': AttributeRule.any(),
  'maxlength': AttributeRule.any(),
  'media': AttributeRule.any(),
  'multiple': AttributeRule.any(),
  'nohref': AttributeRule.any(),
  'noshade': AttributeRule.any(),
  'nowrap': AttributeRule.any(),
  'open': AttributeRule.any(),
  'readonly': AttributeRule.any(),
  'rel': AttributeRule.where(_isRelList),
  'rev': AttributeRule.any(),
  'role': AttributeRule.any(),
  'rows': AttributeRule.any(),
  'rowspan': AttributeRule.any(),
  'rules': AttributeRule.any(),
  'scope': AttributeRule.any(),
  'selected': AttributeRule.any(),
  'shape': AttributeRule.any(),
  'size': AttributeRule.any(),
  'span': AttributeRule.any(),
  'start': AttributeRule.any(),
  'summary': AttributeRule.any(),
  'tabindex': AttributeRule.any(),
  'target': AttributeRule.any(),
  'title': AttributeRule.any(),
  'type': AttributeRule.any(),
  'valign': AttributeRule.any(),
  'value': AttributeRule.any(),
  'vspace': AttributeRule.any(),
  'width': AttributeRule.any(),
};

/// Attributes allowed on specific elements, in addition to the global ones.
const _elementAttributes = <String, Map<String, AttributeRule>>{
  'a': {'href': AttributeRule.url(), 'name': AttributeRule.any()},
  'blockquote': {'cite': AttributeRule.url()},
  'del': {'cite': AttributeRule.url()},
  'div': {'itemscope': AttributeRule.any(), 'itemtype': AttributeRule.any()},
  'img': {
    'longdesc': AttributeRule.url(),
    'src': AttributeRule.url(),
    'srcset': AttributeRule.srcset(),
  },
  'ins': {'cite': AttributeRule.url()},
  'q': {'cite': AttributeRule.url()},
  'source': {'srcset': AttributeRule.srcset()},
};

/// [Link types][1] for `<a>`, without `opener`.
///
/// [1]: https://html.spec.whatwg.org/multipage/links.html#linkTypes
const _relTokens = <String>{
  'alternate',
  'author',
  'bookmark',
  'external',
  'help',
  'license',
  'me',
  'next',
  'nofollow',
  'noopener',
  'noreferrer',
  'prev',
  'privacy-policy',
  'search',
  'sponsored',
  'tag',
  'terms-of-service',
  'ugc',
};

bool _isRelList(String value) {
  final tokens = value.split(_asciiWhitespace).where((t) => t.isNotEmpty);
  return tokens.isNotEmpty && tokens.every(_relTokens.contains);
}

final _asciiWhitespace = RegExp(r'[ \t\n\f\r]+');

/// The rule set without `id` and `class`, shared by all default callers.
final _defaultRuleSet = _build(const {});

/// See `RuleSet.gfm`.
RuleSet gfmRuleSet({
  required bool allowElementId,
  required bool allowClassName,
}) {
  if (!allowElementId && !allowClassName) {
    return _defaultRuleSet;
  }
  return _build({
    if (allowElementId) 'id': AttributeRule.any(),
    if (allowClassName) 'class': AttributeRule.any(),
  });
}

RuleSet _build(Map<String, AttributeRule> extraGlobals) {
  final global = {..._globalAttributes, ...extraGlobals};
  return RuleSet({
    for (final element in _elements)
      element: ElementRule(
        attributes: switch (_elementAttributes[element]) {
          null => global,
          final specific => {...global, ...specific},
        },
      ),
  });
}
