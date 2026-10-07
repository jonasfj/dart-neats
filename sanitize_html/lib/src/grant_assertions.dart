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

/// # TRUSTED: grants a checked `RuleSet` refuses.
///
/// `SaneHtmlWriter` guarantees the browser sees exactly the elements and
/// attributes a rule set lets through. These assertions make sure a rule set
/// built with `RuleSet()` does not let through things that defeat the purpose
/// of sanitizing: script execution, control over the host document, or URLs
/// the URL policy never saw. They run once, when the rule set is built, and
/// cost nothing per document. `RuleSet.unsafe()` skips them.
///
/// They are deliberately not a list of everything that can look wrong:
/// `plaintext`, `xmp`, `template`, `title`, `textarea` and `iframe` are
/// allowed because they only make content disappear or render as text.
library;

import 'attribute_rule.dart';
import 'tag_rule.dart';

/// Elements a checked rule set may not allow.
///
///  * `script`: executes. `noscript`, `noembed`, `noframes`: RAWTEXT only
///    when scripting / plugins / frames are enabled, so the same output is
///    parsed two different ways.
///  * `style`, `link`, `base`, `meta`, `html`, `head`, `body`: alter the host
///    document rather than the fragment (`base` rebases every relative URL on
///    the page, `meta` refreshes, the parser copies `html`/`body` attributes
///    onto the host's elements).
///  * `frameset`, `frame`, `form`: hijack the host's frames and form
///    controls. `object`, `embed`, `applet`: plugin content with unauditable
///    attribute semantics.
///  * `isindex`: expanded into a `<form>` with controls by parsers following
///    older versions of the spec, including `package:html`.
///  * `svg`, `math`: foreign content has case-sensitive attributes such as
///    `xlink:href`, `<animate>` that retargets an `href` at runtime,
///    `<foreignObject>` to get back into HTML, and a long history of
///    mutation XSS.
const forbiddenElements = <String>{
  'applet',
  'base',
  'body',
  'embed',
  'form',
  'frame',
  'frameset',
  'head',
  'html',
  'isindex',
  'link',
  'math',
  'meta',
  'noembed',
  'noframes',
  'noscript',
  'object',
  'script',
  'style',
  'svg',
};

/// Attributes a checked rule set may not allow on any element.
///
///  * `style`: inline CSS can reposition content over the host page (and has
///    executed script in older engines).
///  * `srcdoc`: an entire inline document for `<iframe>`.
///    https://html.spec.whatwg.org/multipage/iframe-embed-object.html#attr-iframe-srcdoc
///  * `is`: upgrades the element to a host-defined customized built-in.
///    https://html.spec.whatwg.org/multipage/custom-elements.html#attr-is
///  * `form`, `formaction`, `formtarget`, `formmethod`, `formenctype`:
///    associate a control with, or override the submission of, one of the
///    host page's forms.
///    https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#attr-fae-form
///  * `ping`, `attributionsrc`: requests to arbitrary URLs on activation.
///    https://html.spec.whatwg.org/multipage/links.html#ping
///
/// Event handler attributes (`on*`) are refused by name prefix.
/// https://html.spec.whatwg.org/multipage/webappapis.html#event-handler-content-attributes
const forbiddenAttributes = <String>{
  'attributionsrc',
  'form',
  'formaction',
  'formenctype',
  'formmethod',
  'formtarget',
  'is',
  'ping',
  'srcdoc',
  'style',
};

/// Attributes whose value a browser interprets as a URL; a checked rule set
/// must bind them to [AttributeRule.url] or [AttributeRule.urlWhere]
/// (`srcset` to [AttributeRule.srcset]).
///
/// The list is deliberately broad and includes attributes of elements that
/// can never be allowed, so it holds without knowing the element.
/// https://html.spec.whatwg.org/multipage/indices.html#attributes-3
const urlAttributes = <String>{
  'action',
  'background',
  'cite',
  'codebase',
  'data',
  'dynsrc',
  'formaction',
  'href',
  'icon',
  'longdesc',
  'lowsrc',
  'manifest',
  'poster',
  'src',
  'srcset',
  'xlink:href',
};

/// Throws [UnsupportedError] if [rule] for [tagName] grants something a
/// checked rule set refuses.
void checkGrants(String tagName, TagRule rule) {
  if (forbiddenElements.contains(tagName)) {
    throw UnsupportedError(
      '<$tagName> cannot be allowed by RuleSet(); '
      'use RuleSet.unsafe() if you really mean it',
    );
  }
  for (final MapEntry(key: name, value: rule) in rule.attributes.entries) {
    if (forbiddenAttributes.contains(name) || name.startsWith('on')) {
      throw UnsupportedError(
        '<$tagName $name=""> cannot be allowed by RuleSet(); '
        'use RuleSet.unsafe() if you really mean it',
      );
    }
    if (!urlAttributes.contains(name)) {
      continue;
    }
    if (name == 'srcset' ? !rule.isSrcsetRestricted : !rule.isUrlRestricted) {
      throw UnsupportedError(
        '<$tagName $name=""> must use AttributeRule.'
        '${name == 'srcset' ? 'srcset' : 'url or AttributeRule.urlWhere'} '
        'in RuleSet(); use RuleSet.unsafe() if you really mean it',
      );
    }
  }
}
