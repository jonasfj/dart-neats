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
///    and `iframe` a `name` creates a property on `window` and `document`
///    (DOM clobbering, e.g. `<img name="getElementById">`).
///    https://html.spec.whatwg.org/multipage/nav-history-apis.html#named-access-on-the-window-object
///  * Form related attributes (`action`, `method`, `enctype`, `accept`,
///    `accept-charset`, `for`, `prompt`) are dropped since no form element
///    is allowed, as is `usemap` (no `<map>`) and `accesskey` (hijacks the
///    host page's keyboard shortcuts).
///  * `id` and `class` are only kept when the caller supplies a predicate,
///    because the host page's CSS and scripts select on them.
///  * `rel` is limited to `[a-z0-9_-]` tokens.
///
/// The rule set is built with `RuleSet()`, so it is subject to the same grant
/// assertions as any user rule set.
///
/// [1]: https://github.com/jch/html-pipeline/blob/master/lib/html/pipeline/sanitization_filter.rb
library;

import 'attribute_rule.dart';
import 'rule_set.dart';
import 'tag_rule.dart';

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
  'abbr': AttributeRule.any,
  'align': AttributeRule.any,
  'alt': AttributeRule.any,
  'aria-describedby': AttributeRule.any,
  'aria-hidden': AttributeRule.any,
  'aria-label': AttributeRule.any,
  'aria-labelledby': AttributeRule.any,
  'axis': AttributeRule.any,
  'border': AttributeRule.any,
  'cellpadding': AttributeRule.any,
  'cellspacing': AttributeRule.any,
  'char': AttributeRule.any,
  'charoff': AttributeRule.any,
  'charset': AttributeRule.any,
  'checked': AttributeRule.any,
  'clear': AttributeRule.any,
  'cols': AttributeRule.any,
  'colspan': AttributeRule.any,
  'color': AttributeRule.any,
  'compact': AttributeRule.any,
  'coords': AttributeRule.any,
  'datetime': AttributeRule.any,
  'dir': AttributeRule.any,
  'disabled': AttributeRule.any,
  'frame': AttributeRule.any,
  'headers': AttributeRule.any,
  'height': AttributeRule.any,
  'hreflang': AttributeRule.any,
  'hspace': AttributeRule.any,
  'ismap': AttributeRule.any,
  'itemprop': AttributeRule.any,
  'label': AttributeRule.any,
  'lang': AttributeRule.any,
  'maxlength': AttributeRule.any,
  'media': AttributeRule.any,
  'multiple': AttributeRule.any,
  'nohref': AttributeRule.any,
  'noshade': AttributeRule.any,
  'nowrap': AttributeRule.any,
  'open': AttributeRule.any,
  'readonly': AttributeRule.any,
  'rel': AttributeRule.tokens(_isRelToken),
  'rev': AttributeRule.any,
  'role': AttributeRule.any,
  'rows': AttributeRule.any,
  'rowspan': AttributeRule.any,
  'rules': AttributeRule.any,
  'scope': AttributeRule.any,
  'selected': AttributeRule.any,
  'shape': AttributeRule.any,
  'size': AttributeRule.any,
  'span': AttributeRule.any,
  'start': AttributeRule.any,
  'summary': AttributeRule.any,
  'tabindex': AttributeRule.any,
  'target': AttributeRule.any,
  'title': AttributeRule.any,
  'type': AttributeRule.any,
  'valign': AttributeRule.any,
  'value': AttributeRule.any,
  'vspace': AttributeRule.any,
  'width': AttributeRule.any,
};

/// Attributes allowed on specific elements, in addition to the global ones.
const _elementAttributes = <String, Map<String, AttributeRule>>{
  'a': {'href': AttributeRule.url, 'name': AttributeRule.any},
  'blockquote': {'cite': AttributeRule.url},
  'del': {'cite': AttributeRule.url},
  'div': {'itemscope': AttributeRule.any, 'itemtype': AttributeRule.any},
  'img': {
    'longdesc': AttributeRule.url,
    'src': AttributeRule.url,
    'srcset': AttributeRule.srcset,
  },
  'ins': {'cite': AttributeRule.url},
  'q': {'cite': AttributeRule.url},
  'source': {'srcset': AttributeRule.srcset},
};

bool _isRelToken(String token) {
  for (var i = 0; i < token.length; i++) {
    final c = token.codeUnitAt(i);
    if (!(c >= 0x61 && c <= 0x7A) &&
        !(c >= 0x30 && c <= 0x39) &&
        c != 0x2D &&
        c != 0x5F) {
      return false;
    }
  }
  return token.isNotEmpty;
}

/// The rule set without `id` and `class`, shared by all callers without
/// predicates.
final _defaultRuleSet = _build(const {});

/// See `RuleSet.gfm`.
RuleSet gfmRuleSet({
  bool Function(String id)? allowElementId,
  bool Function(String className)? allowClassName,
}) {
  if (allowElementId == null && allowClassName == null) {
    return _defaultRuleSet;
  }
  return _build({
    if (allowElementId != null) 'id': AttributeRule.where(allowElementId),
    if (allowClassName != null) 'class': AttributeRule.tokens(allowClassName),
  });
}

RuleSet _build(Map<String, AttributeRule> extraGlobals) {
  final global = {..._globalAttributes, ...extraGlobals};
  return RuleSet({
    for (final element in _elements)
      element: TagRule(
        attributes: switch (_elementAttributes[element]) {
          null => global,
          final specific => {...global, ...specific},
        },
      ),
  });
}
