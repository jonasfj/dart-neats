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

import 'package:html/dom.dart' show Element, Text;
import 'package:html/parser.dart' show parseFragment;
import 'package:markdown/markdown.dart' as md;
import 'package:sanitize_html/sanitize_html.dart';
import 'package:test/test.dart';

const tokenizers = {
  'streaming': HtmlTokenizer.streaming,
  'simple': HtmlTokenizer.simple,
  'dom': HtmlTokenizer.dom,
};

/// A sanitizer with any id / class allowed on `<span>` by the rules and
/// limited by a rewriter, an extra element and a `rel` rewriter, exercising
/// the configuration surface.
String configured(String html) => sanitizeHtml(
      html,
      rules: RuleSet.gfm().union(RuleSet({
        'only-allowed-tag': const ElementRule(),
        'span': ElementRule(attributes: {
          'id': AttributeRule.any(),
          'class': AttributeRule.any(),
        }),
      })),
      rewriters: [
        HtmlRewriter(_LimitIdAndClass.new),
        HtmlRewriter.addLinkRel(
            (href) => href == 'bad-link' ? ['ugc', 'nofollow'] : const []),
      ],
    );

/// Keeps only `id="only-allowed-id"` and the class `only-allowed-class`.
final class _LimitIdAndClass extends HtmlTokenSink {
  final HtmlTokenSink _next;
  _LimitIdAndClass(this._next);

  @override
  void text(String source, int start, int end) =>
      _next.text(source, start, end);

  @override
  void startTag(String name, Map<String, String> attributes) {
    if (attributes.isNotEmpty) {
      if (attributes['id'] != 'only-allowed-id') {
        attributes.remove('id');
      }
      final classes = attributes['class']
          ?.split(' ')
          .where((c) => c == 'only-allowed-class')
          .join(' ');
      if (classes == null || classes.isEmpty) {
        attributes.remove('class');
      } else {
        attributes['class'] = classes;
      }
    }
    _next.startTag(name, attributes);
  }

  @override
  void endTag(String name) => _next.endTag(name);
}

void main() {
  void testContains(String template, String needle,
      {bool withConfiguration = true}) {
    test('"$template" does contain "$needle"', () {
      final sanitize = withConfiguration ? configured : sanitizeHtml;
      expect(sanitize(template), contains(needle));
    });
  }

  void testNotContains(String template, String needle,
      {bool withConfiguration = true}) {
    test('"$template" does not contain "$needle"', () {
      final sanitize = withConfiguration ? configured : sanitizeHtml;
      expect(sanitize(template), isNot(contains(needle)));
    });
  }

  testNotContains('test', '<br>');
  testContains('test', 'test');
  testContains('a < b', '&lt;');
  testContains('a < b > c', '&gt;');
  testContains('<p>hello', 'hello');
  testContains('<p>hello', '</p>');
  testContains('<p>hello', '<p>');

  // test id filtering..
  testContains('<span id="only-allowed-id">hello</span>', 'id');
  testContains('<span id="only-allowed-id">hello</span>', 'only-allowed-id');
  testNotContains('<span id="disallowed-id">hello</span>', 'id');
  testNotContains('<span id="disallowed-id">hello</span>', 'only-allowed-id');

  // test class filtering
  testContains('<span class="only-allowed-class">hello</span>', 'class');
  testContains(
      '<span class="only-allowed-class">hello</span>', 'only-allowed-class');
  testContains('<span class="only-allowed-class disallowed-class">hello</span>',
      'class="only-allowed-class"');
  testNotContains('<span class="disallowed-class">hello</span>', 'class');
  testNotContains(
      '<span class="disallowed-class">hello</span>', 'only-allowed-class');

  testContains('<a href="test.html">hello', 'href');
  testContains('<a href="test.html">hello', 'test.html');
  testContains(
      '<a href="//example.com/test.html">hello', '//example.com/test.html');
  testContains('<a href="/test.html">hello', '/test.html');
  testContains('<a href="https://example.com/test.html">hello',
      'https://example.com/test.html');
  testContains('<a href="http://example.com/test.html">hello',
      'http://example.com/test.html');
  testContains(
      '<a href="mailto:test@example.com">hello', 'mailto:test@example.com');

  testContains('<img src="test.jpg"/>', '<img');
  testContains('<img src="test.jpg" alt="say hi"/>', 'say hi');
  testContains('<img src="test.jpg" alt="say hi"/>', 'alt=');
  testContains('<img src="test.jpg" ALt="say hi"/>', 'say hi');
  testContains('<img src="test.jpg" ALT="say hi"/>', 'alt=');
  testContains('<img src="test.jpg"/>', 'src=');
  testContains('<img src="test.jpg"/>', 'test.jpg');
  testContains('<img src="//test.jpg"/>', '//test.jpg');
  testContains('<img src="/test.jpg"/>', '/test.jpg');
  testContains('<img src="https://example.com/test.jpg"/>',
      'https://example.com/test.jpg');
  testContains('<img src="http://example.com/test.jpg"/>',
      'http://example.com/test.jpg');

  testNotContains('<img src="javascript:test.jpg"/>', 'src=');
  testNotContains('<img src="javascript:test.jpg"/>', 'javascript');
  testContains('<img src="javascript:test.jpg"/>', 'img');

  // <picture> and <source> survive sanitization, including the fallback <img>.
  // A bad URL in srcset drops only the attribute, not the element.
  testContains('<picture><img src="banner.webp"/></picture>', '<picture>');
  testContains('<picture><img src="banner.webp"/></picture>', '<img');
  testContains(
      '<picture><source srcset="dark.webp"><img src="light.webp"/></picture>',
      '<source');
  testContains('<source srcset="banner.webp">', 'srcset');
  testContains('<source srcset="banner.webp">', 'banner.webp');
  testContains(
      '<source media="(prefers-color-scheme: dark)" srcset="dark.webp">',
      'media=');
  testContains('<source srcset="a.webp 1x, b.webp 2x">', 'b.webp 2x');
  testContains('<source srcset="/img/banner.webp">', '/img/banner.webp');
  testContains('<source srcset="https://example.com/b.webp">',
      'https://example.com/b.webp');
  testNotContains('<source srcset="javascript:alert()">', 'srcset');
  testNotContains('<source srcset="javascript:alert()">', 'javascript');
  testContains('<source srcset="javascript:alert()">', '<source');
  testNotContains('<source srcset="ok.webp, javascript:alert()">', 'srcset');
  testNotContains(
      '<source srcset="ok.webp, javascript:alert()">', 'javascript');

  // A descriptor must be a width (`640w`) or density (`1.5x`); nothing else.
  testContains('<source srcset="a.webp 640w">', '640w');
  testContains('<source srcset="a.webp 1.5x">', '1.5x');
  testNotContains('<source srcset="a.webp totally-bogus">', 'srcset');
  testNotContains('<source srcset="a.webp totally-bogus">', 'totally-bogus');
  testContains('<source srcset="a.webp totally-bogus">', '<source');
  testNotContains('<source srcset="a.webp 1x 2x">', 'srcset');
  testNotContains('<source srcset="a.webp 1x, b.webp bogus">', 'srcset');

  testNotContains('<script/>', 'script');
  testNotContains('<script src="example.js"/>', 'script');
  testNotContains('<script src="example.js"/>', 'src');
  testContains('<script>alert("bad")</script> hello world', 'hello world');
  testNotContains('<script>alert("bad")</script> hello world', 'bad');
  testContains('<a href="javascript:alert()">evil link</a>', '<a');
  testNotContains('<a href="javascript:alert()">evil link</a>', 'href');
  testNotContains('<a href="javascript:alert()">evil link</a>', 'alert');
  testNotContains('<a href="javascript:alert()">evil link</a>', 'javascript');

  testNotContains('<form><input type="submit"/></form> click here', 'form');
  testNotContains('<form><input type="submit"/></form> click here', 'submit');
  testNotContains('<form><input type="submit"/></form> click here', 'input');
  testContains('<form><input type="submit"/></form> click here', 'click here');

  testContains('<br>', '<br>');
  testNotContains('<br>', '</br>');
  testContains('><', '&gt;&lt;');
  testContains('<div><div id="x">a</div></div>', '<div><div>a</div></div>');
  testContains('<a href="a.html">a</a><a href="b.html">b</a>',
      '<a href="a.html">a</a><a href="b.html">b</a>');

  // test void elements
  testContains('<strong></strong> hello', '<strong>');
  testContains('<strong></strong> hello', '</strong>');
  testNotContains('<strong></strong> hello', '<strong />');
  testContains('<br>hello</br>', '<br>');
  testNotContains('<br>hello</br>', '</br>');

  // test addLinkRel
  testContains('<a href="bad-link">hello', 'bad-link');
  testContains('<a href="bad-link">hello', 'rel="ugc nofollow"');
  testNotContains('<a href="good-link">hello', 'rel="ugc nofollow"');

  // test extra elements via union
  testContains(
      '<only-allowed-tag>hello</only-allowed-tag>', '<only-allowed-tag>');
  testContains('<only-allowed-tag>hello</only-allowed-tag>', 'hello');
  testNotContains('<disallowed-tag>hello</disallowed-tag>', 'disallowed-tag');
  testContains('<disallowed-tag>hello</disallowed-tag>', 'hello');

  // test <picture> and <source>
  testContains('<picture><img src="banner.webp"/></picture>', '<picture>');
  testContains('<picture><img src="banner.webp"/></picture>', '<img');
  testContains(
      '<picture><source srcset="dark.webp"><img src="light.webp"/></picture>',
      '<source');
  testContains('<source srcset="banner.webp">', 'srcset');
  testContains('<source srcset="banner.webp">', 'banner.webp');
  testContains(
      '<source media="(prefers-color-scheme: dark)" srcset="dark.webp">',
      'media=');
  testContains('<source srcset="a.webp 1x, b.webp 2x">', 'b.webp 2x');
  testContains('<source srcset="/img/banner.webp">', '/img/banner.webp');
  testContains('<source srcset="https://example.com/b.webp">',
      'https://example.com/b.webp');
  testNotContains('<source srcset="javascript:alert()">', 'srcset');
  testNotContains('<source srcset="javascript:alert()">', 'javascript');
  testContains('<source srcset="javascript:alert()">', '<source');
  testNotContains('<source srcset="ok.webp, javascript:alert()">', 'srcset');
  testNotContains(
      '<source srcset="ok.webp, javascript:alert()">', 'javascript');
  testContains('<source srcset="a.webp 640w">', '640w');
  testContains('<source srcset="a.webp 1.5x">', '1.5x');
  testNotContains('<source srcset="a.webp totally-bogus">', 'srcset');
  testNotContains('<source srcset="a.webp totally-bogus">', 'totally-bogus');
  testContains('<source srcset="a.webp totally-bogus">', '<source');
  testNotContains('<source srcset="a.webp 1x 2x">', 'srcset');
  testNotContains('<source srcset="a.webp 1x, b.webp bogus">', 'srcset');

  group('URI obfuscation & entity encoding attacks:', () {
    testNotContains('<a href="jav&#x09;ascript:alert(1)">link</a>', 'href');
    testNotContains('<a href="jav&#x0A;ascript:alert(1)">link</a>', 'href');
    testNotContains('<a href="jav&#x0D;ascript:alert(1)">link</a>', 'href');
    testNotContains('<a href="&Tab;javascript:alert(1)">link</a>', 'href');
    testNotContains('<a href="&NewLine;javascript:alert(1)">link</a>', 'href');
    testNotContains('<a href="javascript&#58;alert(1)">link</a>', 'href');
    testNotContains('<a href="javascript&colon;alert(1)">link</a>', 'href');
    testNotContains(
        '<a href="&#106;&#97;&#118;&#97;&#115;&#99;&#114;&#105;&#112;&#116;:alert(1)">link</a>',
        'href');
    testNotContains(
        '<a href="&#x6a;&#x61;&#x76;&#x61;&#x73;&#x63;&#x72;&#x69;&#x70;&#x74;:alert(1)">link</a>',
        'href');
    testNotContains('<a href="&#0000106;avascript:alert(1)">link</a>', 'href');
    testNotContains('<a href="  javascript:alert(1)">link</a>', 'href');
    testNotContains('<a href="\x01javascript:alert(1)">link</a>', 'href');
    testNotContains(
        '<a href="data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==">link</a>',
        'href');
    testNotContains('<a href="vbscript:msgbox(1)">link</a>', 'href');
    testNotContains('<a href="feed:javascript:alert(1)">link</a>', 'href');
    testNotContains(r'<a href="\\evil.com">link</a>', 'href');
    testNotContains(r'<a href="/\evil.com">link</a>', 'href');
    testNotContains(r'<a href="///\evil.com">link</a>', 'href');
    testNotContains(r'<a href="\evil.com">link</a>', 'href');
    testNotContains(r'<a href="https://example.com/foo\bar">link</a>', 'href');
    testNotContains('<a href="https://good.com@evil.com/">link</a>', 'href');
    testNotContains('<a href="//good.com@evil.com/">link</a>', 'href');
    testNotContains('<a href="https://good.com\\@evil.com/">link</a>', 'href');
    testContains('<a href="https://example.com/?u=a@b">link</a>', 'href');
    testContains('<a href="https://example.com/#@x">link</a>', 'href');
  });

  group('Subtree drop attacks:', () {
    testNotContains('<style>body { color: red; }</style>', 'color');
    testNotContains('<textarea><img src=x onerror=alert(1)></textarea>', 'img');
    testNotContains('<title><img src=x onerror=alert(1)></title>', 'img');
    testNotContains('<xmp><img src=x onerror=alert(1)></xmp>', 'img');
    testNotContains('<iframe><script>alert(1)</script></iframe>', 'script');
    testNotContains('<noscript><img src=x onerror=alert(1)></noscript>', 'img');
    testNotContains('<template><img src=x onerror=alert(1)></template>', 'img');
    testNotContains('<svg><script>alert(1)</script></svg>', 'script');
    testNotContains(
        '<svg><style><img src=x onerror=alert(1)></style></svg>', 'img');
    testNotContains(
        '<math><annotation-xml><script>alert(1)</script></annotation-xml></math>',
        'script');
    testContains('<svg/>hello', 'hello');
    testNotContains('<svg/>hello', 'svg');
    testContains('<svg><svg></svg></svg>hello', 'hello');
    testNotContains('<svg><svg></svg></svg>hello', 'svg');
    testNotContains(
        '<plaintext>should be dropped<script>alert(1)</script>', 'dropped');
    testNotContains(
        '<script><!-- <script> alert(1); </script> --> alert(1); </script>',
        'alert');
  });

  group('Comments & declarations:', () {
    testNotContains('<!-- comment -->', 'comment');
    testNotContains('<!-- --!><img src=x onerror=alert(1)>-->', 'onerror');
    testContains('<!-->hello', 'hello');
    testContains('<!--->hello', 'hello');
    testNotContains('<!DOCTYPE html>hello', 'DOCTYPE');
    testContains('<!DOCTYPE html>hello', 'hello');
    testNotContains('<![CDATA[<script>alert(1)</script>]]>hello', 'script');
    testContains('<![CDATA[text]]>hello', 'hello');
    testNotContains('<?xml version="1.0"?>hello', 'xml');
    testContains('<?xml version="1.0"?>hello', 'hello');
  });

  group('Tag balancing, stack, and auto-closing:', () {
    testContains('<p>hello', '</p>');
    testContains('<div><p>Unclosed paragraph at EOF', '</p></div>');
    test('Stray closing tags are dropped', () {
      expect(sanitizeHtml('<div>hello</div></div></div>'), '<div>hello</div>');
    });
    test('Non-void self-closing tags stay open', () {
      expect(sanitizeHtml('<div />hello</div>'), '<div>hello</div>');
    });
    test('<p> is auto-closed by block-level element', () {
      expect(sanitizeHtml('<p>paragraph<div>block</div></p>'),
          '<p>paragraph</p><div>block</div>');
    });
    test('Nested <a> tags are auto-closed', () {
      expect(
          sanitizeHtml(
              '<a href="https://a.com">first<a href="https://b.com">second</a></a>'),
          '<a href="https://a.com">first</a><a href="https://b.com">second</a>');
    });
    test('Nested <li> tags are auto-closed', () {
      expect(sanitizeHtml('<ul><li>one<li>two</ul>'),
          '<ul><li>one</li><li>two</li></ul>');
    });
    test('End tags close everything opened after the matching element', () {
      expect(sanitizeHtml('<div><b>bold</div>after'),
          '<div><b>bold</b></div>after');
    });
    test('Implied end tags follow the tree builder scopes', () {
      expect(sanitizeHtml('<ul><li><p>a<li>b</ul>'),
          '<ul><li><p>a</p></li><li>b</li></ul>');
      expect(sanitizeHtml('<p>a<hr>b'), '<p>a</p><hr>b');
      expect(
          sanitizeHtml('<p><b>a<div>b</div>'), '<p><b>a</b></p><div>b</div>');
      expect(sanitizeHtml('<table><tr><td>a<div>b<td>c</table>'),
          '<table><tr><td>a<div>b</div></td><td>c</td></tr></table>');
      expect(sanitizeHtml('<h1>a<h2>b'), '<h1>a</h1><h2>b</h2>');
      // A <button> is a scope boundary: the <div> does not close the <p>.
      final withButton =
          RuleSet.gfm().union(RuleSet({'button': ElementRule()}));
      expect(
        sanitizeHtml('<p><button>x<div>y', rules: withButton),
        '<p><button>x<div>y</div></button></p>',
      );
      // ... even when the button itself is unwrapped: a browser re-parsing
      // the output would close the <p>, which only changes nesting.
      expect(sanitizeHtml('<p><button>x<div>y'), '<p>x<div>y</div></p>');
    });
  });

  group('Attribute injection & escaping:', () {
    test('Attribute quotes are safely escaped', () {
      final sanitized = sanitizeHtml(
          '<img src="a.jpg" alt="test&quot; onerror=alert(1) x=&quot;">');
      expect(sanitized, isNot(contains('" onerror=')));
      expect(sanitized, contains('alt="test&quot; onerror=alert(1) x=&quot;"'));
    });
    test('Missing whitespace between attributes', () {
      final sanitized =
          sanitizeHtml('<a title="foo"onclick="alert(1)">link</a>');
      expect(sanitized, isNot(contains('onclick')));
      expect(sanitized, contains('title="foo"'));
    });
    test('Quote injection in rel attribute is neutralized', () {
      final sanitized = configured(
          '<a href="bad-link" rel=\'ugc" onmouseover="alert(1)\'>test</a>');
      expect(sanitized, isNot(contains('onmouseover=')));
      // The whole `rel` is dropped: `rel` tokens are all-or-nothing.
      expect(sanitized, '<a href="bad-link">test</a>');
    });
    test('< and > in attribute values are escaped', () {
      expect(
        sanitizeHtml('<a title="</a><script>">x</a>'),
        '<a title="&lt;/a&gt;&lt;script&gt;">x</a>',
      );
    });
  });

  group('Performance & complexity resistance:', () {
    test('Many ampersands without quadratic slowdown', () {
      expect(sanitizeHtml('&' * 5000), '&amp;' * 5000);
    });
    test('Deeply nested tags do not exhaust memory', () {
      final deepTags = '${'<div>' * 200}hello${'</div>' * 200}';
      expect(sanitizeHtml(deepTags), contains('hello'));
    });
    test('Many attributes and escaped script data stay linear', () {
      // Each of these took tens of seconds when the per-tag scan for `&` or
      // for `-->` ran to the end of the input.
      final stopwatch = Stopwatch()..start();
      sanitizeHtml('<b a="x">' * 30000);
      sanitizeHtml('<script><!--${'<' * 200000}');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('Defaults:', () {
    testContains('<a href="any-href">hey', 'href=', withConfiguration: false);
    testNotContains('<a href="any-href">hey', 'rel=', withConfiguration: false);
    testContains('<any-tag>hello</any-tag>', 'hello', withConfiguration: false);
    testNotContains('<any-tag>hello</any-tag>', 'any-tag',
        withConfiguration: false);
    testNotContains('<span id="any-id">hello</span>', 'id=',
        withConfiguration: false);
    testNotContains('<span class="any-class">hello</span>', 'class=',
        withConfiguration: false);
    testContains('<a rel="nofollow me">x</a>', 'rel="nofollow me"',
        withConfiguration: false);
    testNotContains('<a rel="nofollow x-y_1">x</a>', 'rel',
        withConfiguration: false);
    testNotContains('<a rel="noopener opener">x</a>', 'rel',
        withConfiguration: false);
  });

  group('DOMPurify adversarial test cases:', () {
    testNotContains('<a href="javascript   :alert(1)">foo</a>', 'href');
    testNotContains('<a href="javascript :alert(1)">foo</a>', 'href');
    testNotContains('<a href="java\x00script:alert(1)">foo</a>', 'href');
    testNotContains('<a href="java%00script:alert(1)">foo</a>', 'href');
    testNotContains('<a href="&#14;  javascript:alert(1)">foo</a>', 'href');
    testNotContains('<a href="\u2028javascript:alert(1)">foo</a>', 'href');
    testNotContains('<a href="\uFEFFjavascript:alert(1)">foo</a>', 'href');
    testNotContains('<a href="&#x200B;javascript:alert(1)">foo</a>', 'href');
    testNotContains('<a href="&#xA0;javascript:alert(1)">foo</a>', 'href');
    testNotContains('<a href="&#x1680;javascript:alert(1)">foo</a>', 'href');
    testNotContains('<a href="&#x3000;javascript:alert(1)">foo</a>', 'href');
    testNotContains('<a href="data:,evilnastystuff">foo</a>', 'href');
    testNotContains(
        '<a href="data:text/html,<script>alert(1)</script>">foo</a>', 'href');
    testNotContains(
        '<img src="data:image/svg+xml,<svg onload=alert(1)>">', 'data:');
    testNotContains(
        '<form onmouseover="alert(1)"><input name="attributes"><input name="attributes">',
        'onmouseover');
    testNotContains('<img src=x onerror=alert(1)>', 'onerror');
    // `name` is a clobbering surface like `id`; gfm drops it.
    testNotContains('<a name="anchor">top</a>', 'name=');
    testNotContains(
        '<div onclick=alert(0)><form onsubmit=alert(1)><input onfocus=alert(2) name=parentNode>123</form></div>',
        'on');
    testNotContains('<details ontoggle="alert(1)">foo</details>', 'ontoggle');
    testNotContains(
        '<div onanimationstart="alert(1)">foo</div>', 'onanimationstart');
    testContains(
        '<div aria-labelledby="msg--title"><span aria-label="close">close</span></div>',
        'aria-label="close"',
        withConfiguration: false);
    testNotContains(r'''<a href="javascript:alert('XSS');">foo</a>''', 'href');
    testNotContains(
        r'''<a href="javascript    :   alert('XSS');">foo</a>''', 'href');
  });

  group('package:html & html5lib test cases:', () {
    testNotContains(
        '<svg><style>&lt;img src=x onerror=alert(1)&gt;</style></svg>',
        'onerror');
    testNotContains(
        '<math><iframe>&lt;img src=x onerror=alert(1)&gt;</iframe></math>',
        'onerror');
    testNotContains(
        '<svg><xmp>&lt;img src=x onerror=alert(1)&gt;</xmp></svg>', 'onerror');
    testContains('&;', '&amp;;');
    testContains('<a href="http://example.com?a=1&b=2">link</a>',
        'href="http://example.com?a=1&amp;b=2"');
    testContains('<p a="&">link</p>', 'link');
    test('Non-void element self-closing <div/>', () {
      expect(sanitizeHtml('<div/>hello</div>'), '<div>hello</div>');
    });
    test('Void element self-closing <br/>', () {
      expect(sanitizeHtml('<br/>'), '<br>');
      expect(sanitizeHtml('<br foo="bar"/>'), '<br>');
    });
    test('Unescaped </ and stray tags', () {
      expect(sanitizeHtml('</'), '&lt;/');
      expect(sanitizeHtml('</1>'), '');
      expect(sanitizeHtml('</>'), '');
      expect(sanitizeHtml('<>'), '&lt;&gt;');
    });
  });

  group('parse5 & browser tokenizer edge cases:', () {
    testNotContains(
        '<script/xss src="http://xx.com/xss.js"></script>', 'script');
    testNotContains('<script/src="http://xx.com/xss.js"></script>', 'script');
    testNotContains('<b/onclick=alert(1)>bold</b>', 'onclick');
    testContains('<b/onclick=alert(1)>bold</b>', '<b>bold</b>');
    testContains('<A HREF="http://example.com">foo</A>',
        '<a href="http://example.com">foo</a>');
    testContains('<DIV>hello</DIV>', '<div>hello</div>');
    testContains('<img src=http://example.com/pic.png>',
        '<img src="http://example.com/pic.png">');
    // A `/` in an unquoted attribute value is part of the value.
    testContains('<img src=http://example.com/pic.png/>',
        '<img src="http://example.com/pic.png/">');
    testNotContains('<a href=`javascript:alert(1)`>foo</a>', 'href');
    testNotContains('<img src=`javascript:alert(1)`>', 'src');
    testNotContains('<img src="javascript:alert(1)"', 'javascript');
    testNotContains('<script src="http://xss.rocks/xss.js"', 'script');
    testNotContains('<<SCRIPT>alert("XSS");//<</SCRIPT>', 'alert');
    testNotContains('<IMG """><SCRIPT>alert("XSS")</SCRIPT>">', 'alert');
    testNotContains('<SCRIPT SRC=http://xss.rocks/xss.js?<B>', 'script');
    testNotContains('<a href="jav\tascript:alert(1)">foo</a>', 'href');
    testNotContains('<a href="jav\nascript:alert(1)">foo</a>', 'href');
    testNotContains('<a href="jav\rascript:alert(1)">foo</a>', 'href');
    testNotContains(
        '<a href="&#x6A&#x61&#x76&#x61&#x73&#x63&#x72&#x69&#x70&#x74&#x3A&#x61&#x6C&#x65&#x72&#x74&#x28&#x27&#x58&#x53&#x53&#x27&#x29">foo</a>',
        'href');
    test('Unterminated tags at EOF produce no element', () {
      expect(sanitizeHtml('x<y'), 'x');
      expect(sanitizeHtml('<y'), '');
      expect(sanitizeHtml('text<a href="x"'), 'text');
    });
    test('End tags may carry (ignored) quoted attributes', () {
      expect(sanitizeHtml('</div title=">"><p>content</p>'), '<p>content</p>');
    });
  });

  group('Mozilla Bleach test suite cases:', () {
    test('Idempotency: clean(clean(x)) == clean(x)', () {
      final cases = [
        'a < b',
        'link http://link.com',
        'text<em>',
        '<span>text & </span>',
        'jim &current joe',
        '&&nbsp; &nbsp;&',
        'jim &xx; joe',
        '<a href="http://example.com?foo=bar&bar=foo&amp;biz=bash">test</a>',
        '<img src="http://example.com?foo=bar&bar=foo&amp;biz=bash">',
        'an <strong>allowed</strong> tag',
        '<p>One<p>Two',
        '<div><p>Paragraph</p></div>',
        '&amp;lt;b&amp;gt; &#x27; &#39; &bogus; & &# &#; &amp',
        '<a title="&quot;&amp;&lt;">x</a>',
      ];
      for (final MapEntry(key: name, value: tokenizer) in tokenizers.entries) {
        String sanitize(String html) =>
            sanitizeHtml(html, tokenizer: tokenizer);
        for (final c in cases) {
          final once = sanitize(c);
          expect(sanitize(once), once, reason: 'Not idempotent: "$c" ($name)');
        }
      }
    });

    test('Unclosed tags', () {
      expect(sanitizeHtml('a <em>fixed tag'), 'a <em>fixed tag</em>');
      expect(sanitizeHtml('<script src=http://xx.com/xss.js<b>'), '');
      expect(sanitizeHtml('<script src="http://xx.com/xss.js"<b>'), '');
      expect(sanitizeHtml('<script src="http://xx.com/xss.js" <b>'), '');
    });

    test('Nested script tags', () {
      // Script content is never text; what is left is escaped text.
      final result1 = sanitizeHtml('<<script>script>evil()<</script>/script>');
      expect(result1, contains('&lt;'));
      expect(result1, isNot(contains('evil')));

      final result2 = sanitizeHtml('<<x>script>evil()<</x>/script>');
      expect(result2, contains('&lt;'));
      expect(result2, isNot(contains('<script')));

      final result3 = sanitizeHtml('<script<script>>evil()</script</script>>');
      expect(result3, isNot(contains('<script')));
    });

    test('Bare entities get escaped correctly', () {
      expect(sanitizeHtml('an & entity'), 'an &amp; entity');
      expect(sanitizeHtml('an < entity'), 'an &lt; entity');
      expect(sanitizeHtml('tag < <em>and</em> entity'),
          'tag &lt; <em>and</em> entity');
      expect(sanitizeHtml('x < y'), 'x &lt; y');
      expect(sanitizeHtml('< y'), '&lt; y');
    });

    test('Comments with surrounding text', () {
      expect(sanitizeHtml('<!-- comment -->text'), 'text');
      expect(sanitizeHtml('<!--comment-->text'), 'text');
      expect(sanitizeHtml('text<!-- comment -->'), 'text');
      expect(sanitizeHtml('text<!--comment-->'), 'text');
      expect(sanitizeHtml('<!-- open comment'), '');
    });
  });

  group('Text character references:', () {
    test('references are preserved, lone ampersands escaped', () {
      for (final MapEntry(key: name, value: tokenizer) in tokenizers.entries) {
        String sanitize(String html) =>
            sanitizeHtml(html, tokenizer: tokenizer);
        // The DOM tokenizer decodes references; the result renders the same.
        final copy =
            name == 'dom' ? '\u00A9 \u00A9 \u00A9' : '&copy; &#169; &#xA9;';
        expect(sanitize('&amp; &lt;b&gt; &copy; &#169; &#xA9;'),
            '&amp; &lt;b&gt; $copy',
            reason: name);
        expect(sanitize('a & b &; c &&amp; e &'),
            'a &amp; b &amp;; c &amp;&amp; e &amp;',
            reason: name);
        // Double-encoded input stays double-encoded (no double decoding).
        expect(sanitize('&amp;lt;b&amp;gt;'), '&amp;lt;b&amp;gt;',
            reason: name);
      }
    });
    test('unknown and invalid references are left for the browser', () {
      expect(sanitizeHtml('&bogus; &#0000; &#xD800; &#x1010FFFF;'),
          '&bogus; &#0000; &#xD800; &#x1010FFFF;');
    });
  });

  group('Attribute character references:', () {
    test('named and numeric references are decoded', () {
      expect(sanitizeHtml('<a title="&rarr; &#8594; &#x2192; &amp;lt;">x</a>'),
          '<a title="\u2192 \u2192 \u2192 &amp;lt;">x</a>');
    });
    test('legacy references without semicolon follow browser rules', () {
      expect(sanitizeHtml('<a title="&copy 2024 &copy;2024">x</a>'),
          '<a title="\u00A9 2024 \u00A92024">x</a>');
      // Not decoded before `=` or an alphanumeric, so query strings survive.
      expect(sanitizeHtml('<a href="/?a=1&copy=2&notit=3">x</a>'),
          '<a href="/?a=1&amp;copy=2&amp;notit=3">x</a>');
    });
    test('invalid numeric references become U+FFFD', () {
      expect(sanitizeHtml('<a title="&#0;&#xD800;&#x110000;">x</a>'),
          '<a title="\uFFFD\uFFFD\uFFFD">x</a>');
      expect(sanitizeHtml('<a title="&#x80;&#150;">x</a>'),
          '<a title="\u20AC\u2013">x</a>');
    });
  });

  group('Review findings regression tests:', () {
    test('Self-closing script/style does not leak content', () {
      expect(sanitizeHtml('<script />alert("leak")</script>'), '');
      expect(sanitizeHtml('<script/src="evil.js"/>alert("leak")</script>'), '');
      expect(sanitizeHtml('<style />body { color: red; }</style>'), '');
      expect(sanitizeHtml('<textarea />secret text</textarea>'), '');
      expect(sanitizeHtml('<title />hidden title</title>'), '');
    });

    test('Responsive image srcset is preserved', () {
      expect(
        sanitizeHtml(
            '<img src="pic.png" srcset="pic-1x.png 1x, pic-2x.png 2x">'),
        '<img src="pic.png" srcset="pic-1x.png 1x, pic-2x.png 2x">',
      );
      // Commas may appear inside a candidate URL.
      expect(
        sanitizeHtml(
            '<img srcset="https://cdn.example/w_100,h_100/pic.png 1x">'),
        '<img srcset="https://cdn.example/w_100,h_100/pic.png 1x">',
      );
    });

    test('Max depth nesting bounds tags without leaving unclosed output', () {
      final output = sanitizeHtml(
          '${'<div>' * 140}<div><p>deep</p></div>${'</div>' * 140}');
      // Every element is written, balanced, at most 128 deep: like Blink,
      // a start tag at the cap becomes a sibling of the innermost element.
      expect('<div>'.allMatches(output).length, 141);
      expect('</div>'.allMatches(output).length, 141);
      var depth = 0, maxDepth = 0;
      for (final tag in RegExp('</?(div|p)>').allMatches(output)) {
        depth += tag[0]!.startsWith('</') ? -1 : 1;
        maxDepth = depth > maxDepth ? depth : maxDepth;
      }
      expect(depth, 0);
      expect(maxDepth, 128);
      expect(output, contains('<p>deep</p></div>'));
    });

    test('Void elements and end tags at max depth stay consistent', () {
      // `<b>` at the cap becomes a sibling of `<p>`; the later `</p>` finds
      // no open `p` and is not written, so the browser never has to answer a
      // stray `</p>` with an extra `<p>`.
      final output = sanitizeHtml('${'<div>' * 127}<p>x<b>y<hr>z</p>w');
      expect(output, contains('<p>x</p><b>y<hr>zw</b></div>'));
    });

    test('Implied end tags stay linear for deep open stacks', () {
      final stopwatch = Stopwatch()..start();
      sanitizeHtml('${'<b>' * 40000}${'<div>' * 40000}');
      sanitizeHtml('${'<b>' * 40000}${'</i>' * 40000}');
      sanitizeHtml('${'<x>' * 40000}${'</y>' * 40000}');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('xmp and plaintext close an open paragraph', () {
      final rules = RuleSet.gfm().union(RuleSet({
        'xmp': const ElementRule(),
        'plaintext': const ElementRule(),
      }));
      expect(sanitizeHtml('<p>a<xmp>b</xmp>c</p>', rules: rules),
          '<p>a</p><xmp></xmp>c');
      expect(sanitizeHtml('<p>a<plaintext>b', rules: rules),
          '<p>a</p><plaintext></plaintext>');
    });

    test('Multi-dash comments <!-- ---> do not swallow subsequent markup', () {
      expect(sanitizeHtml('<!-- ---><p>Visible</p>'), '<p>Visible</p>');
      expect(sanitizeHtml('<!-- ---------><p>Visible</p>'), '<p>Visible</p>');
      expect(sanitizeHtml('<!-- ---!><p>Visible</p>'), '<p>Visible</p>');
    });

    test('Repeated RAWTEXT start tags do not swallow the document', () {
      expect(sanitizeHtml('<style><style></style><p>Hello World</p>'),
          '<p>Hello World</p>');
      expect(sanitizeHtml('<textarea><textarea></textarea><p>Hello World</p>'),
          '<p>Hello World</p>');
    });

    test('Simple tokenizer handles non-tag < correctly', () {
      String sanitize(String html) =>
          sanitizeHtml(html, tokenizer: HtmlTokenizer.simple);
      expect(sanitize('a < b'), 'a &lt; b');
      expect(sanitize('<3'), '&lt;3');
      expect(sanitize('</>'), '');
      expect(sanitize('<STYLE>x</STYLE><p>y</p>'), '<p>y</p>');
    });

    test('Disallowed void elements do not swallow the rest of the document',
        () {
      expect(sanitizeHtml('<input type="text"> hello'), ' hello');
      expect(
          sanitizeHtml('<link rel="stylesheet" href="x.css">hello'), 'hello');
    });

    test('Disallowed non-void self-closing tags are unwrapped', () {
      expect(sanitizeHtml('<custom-disallowed />secret</custom-disallowed>'),
          'secret');
      expect(sanitizeHtml('<x><x/>a</x>b</x>c'), 'abc');
    });

    test('Attribute name breakout on custom elements is strictly blocked', () {
      final rules = RuleSet({'my-tag': const ElementRule()});
      expect(
        sanitizeHtml('<my-tag foo"onload="alert(1)"=bar>content</my-tag>',
            rules: rules),
        '<my-tag>content</my-tag>',
      );
    });
  });

  group('RuleSet:', () {
    test('rejects names the writer cannot write', () {
      for (final name in ['', 'DIV', 'a b', 'a>', 'image']) {
        expect(() => RuleSet({name: const ElementRule()}), throwsArgumentError,
            reason: name);
        expect(() => RuleSet.unsafe({name: const ElementRule()}),
            throwsArgumentError,
            reason: name);
      }
      for (final name in ['Title', 'a"b', 'on click', '1x']) {
        expect(
            () => RuleSet({
                  'span': ElementRule(attributes: {name: AttributeRule.any()})
                }),
            throwsArgumentError,
            reason: name);
      }
    });

    test('grant assertions refuse dangerous elements', () {
      for (final tag in [
        'script', 'style', 'base', 'meta', 'link', 'html', 'head', 'body', //
        'frameset', 'frame', 'form', 'object', 'embed', 'applet', 'isindex',
        'noscript', 'noembed', 'noframes', 'svg', 'math',
      ]) {
        expect(
            () => RuleSet({tag: const ElementRule()}), throwsUnsupportedError,
            reason: tag);
        RuleSet.unsafe({tag: const ElementRule()}); // Does not throw.
      }
      // Rendering-only oddities are allowed.
      RuleSet({
        for (final t in ['plaintext', 'xmp', 'iframe', 'template'])
          t: ElementRule()
      });
    });

    test('grant assertions refuse dangerous attributes', () {
      for (final attribute in [
        'onclick', 'onerror', 'style', 'srcdoc', 'is', 'form', 'formaction', //
        'formtarget', 'ping', 'attributionsrc',
      ]) {
        final rule = ElementRule(attributes: {attribute: AttributeRule.any()});
        expect(() => RuleSet({'div': rule}), throwsUnsupportedError,
            reason: attribute);
        RuleSet.unsafe({'div': rule});
      }
    });

    test('grant assertions require the URL policy on URL attributes', () {
      for (final attribute in [
        'href', 'src', 'cite', 'action', 'poster', 'data', 'xlink:href', //
        'background', 'longdesc',
      ]) {
        for (final rule in [
          AttributeRule.any(),
          AttributeRule.where((_) => true),
          AttributeRule.srcset(),
        ]) {
          expect(
              () => RuleSet({
                    'x': ElementRule(attributes: {attribute: rule})
                  }),
              throwsUnsupportedError,
              reason: attribute);
        }
        RuleSet({
          'x': ElementRule(attributes: {attribute: AttributeRule.url()})
        });
        RuleSet({
          'x': ElementRule(
              attributes: {attribute: AttributeRule.url((_) => true)})
        });
      }
      expect(
          () => RuleSet({
                'img': ElementRule(attributes: {'srcset': AttributeRule.url()})
              }),
          throwsUnsupportedError);
      RuleSet({
        'img': ElementRule(attributes: {'srcset': AttributeRule.srcset()})
      });
    });

    test('grant assertions survive union and intersection', () {
      final checked = RuleSet({
        'a': ElementRule(attributes: {'href': AttributeRule.url()})
      });
      final unsafe = RuleSet.unsafe({
        'a': ElementRule(attributes: {'href': AttributeRule.any()})
      });
      // Intersection with anything keeps the URL policy; union with an
      // unsafe set is unsafe.
      expect(
          sanitizeHtml('<a href="javascript:alert(1)">x</a>',
              rules: checked.intersection(unsafe)),
          '<a>x</a>');
      expect(
          sanitizeHtml('<a href="javascript:alert(1)">x</a>',
              rules: checked.union(unsafe)),
          '<a href="javascript:alert(1)">x</a>');
    });

    test('unsafe rule sets really are unsafe, but still well-formed', () {
      final rules = RuleSet.unsafe({
        'div': ElementRule(attributes: {'onclick': AttributeRule.any()}),
      });
      expect(sanitizeHtml('<div onclick="x<y">a</div>', rules: rules),
          '<div onclick="x&lt;y">a</div>');
    });

    test('ElementRule allows no attributes by default', () {
      final rules = RuleSet({'b': const ElementRule()});
      expect(sanitizeHtml('<b title="x" class="y">a</b>', rules: rules),
          '<b>a</b>');
    });

    test('attribute rules', () {
      final rules = RuleSet({
        'a': ElementRule(attributes: {
          'href': AttributeRule.url((u) => u.host == 'example.com'),
          'title': AttributeRule.where((v) => v.length < 5),
          'data-x': AttributeRule.any(),
        }),
        'img': ElementRule(attributes: {
          'srcset': AttributeRule.srcset(
              (urls) => urls.every((u) => u.host == 'example.com')),
        }),
      });
      String s(String html) => sanitizeHtml(html, rules: rules);
      expect(s('<a href="https://example.com/x">a</a>'),
          '<a href="https://example.com/x">a</a>');
      expect(s('<a href="https://evil.com/x">a</a>'), '<a>a</a>');
      expect(s('<a href="/relative">a</a>'), '<a>a</a>'); // host is ''.
      expect(s('<a href="javascript:alert(1)">a</a>'), '<a>a</a>');
      expect(s('<a title="1234">a</a>'), '<a title="1234">a</a>');
      expect(s('<a title="12345">a</a>'), '<a>a</a>');
      expect(s('<a data-x="&lt;">a</a>'), '<a data-x="&lt;">a</a>');
      expect(s('<img srcset="https://example.com/a 1x, //example.com/b 2x">'),
          '<img srcset="https://example.com/a 1x, //example.com/b 2x">');
      expect(s('<img srcset="https://example.com/a 1x, //evil.com/b 2x">'),
          '<img>');
    });

    test('url(where) sees the host the browser will use', () {
      final rules = RuleSet({
        'a': ElementRule(attributes: {
          'href': AttributeRule.url((u) => u.host != 'evil.com'),
        }),
      });
      String s(String html) => sanitizeHtml(html, rules: rules);
      // Forms where RFC 3986 and the WHATWG URL parser find different hosts
      // are refused rather than passed to `where` with a misleading `Uri`.
      for (final href in [
        'https:evil.com/x',
        'https:/evil.com/x',
        'https:///evil.com/x',
        'https://e%76il.com/',
        'https://good.com@evil.com/',
        r'https:\\evil.com/',
        'https://',
        'https:',
      ]) {
        expect(s('<a href="$href">a</a>'), '<a>a</a>', reason: href);
      }
      expect(s('<a href="https://good.com/x">a</a>'),
          '<a href="https://good.com/x">a</a>');
      expect(s('<a href="mailto:x@evil.com">a</a>'),
          '<a href="mailto:x@evil.com">a</a>');
      // Only ASCII whitespace is stripped; U+00A0 makes it a relative URL
      // for the browser and an unknown scheme for the policy.
      expect(s('<a href="\u00A0https://good.com/">a</a>'), '<a>a</a>');
      expect(s('<a href="  https://good.com/ ">a</a>'),
          '<a href="  https://good.com/ ">a</a>');
    });

    test('union keeps elements and attributes allowed by either', () {
      final a = RuleSet({
        'b': ElementRule(attributes: {
          'title': AttributeRule.where((v) => v == 'a'),
        }),
        'i': const ElementRule(),
      });
      final b = RuleSet({
        'b': ElementRule(attributes: {
          'title': AttributeRule.where((v) => v == 'b'),
          'lang': AttributeRule.any(),
        }),
        'u': const ElementRule(),
      });
      String s(String html) => sanitizeHtml(html, rules: a.union(b));
      expect(s('<i>x</i><u>y</u>'), '<i>x</i><u>y</u>');
      expect(s('<b title="a">x</b>'), '<b title="a">x</b>');
      expect(s('<b title="b">x</b>'), '<b title="b">x</b>');
      expect(s('<b title="c" lang="en">x</b>'), '<b lang="en">x</b>');
    });

    test('intersection keeps only what both allow', () {
      final a = RuleSet({
        'b': ElementRule(attributes: {
          'title': AttributeRule.where((v) => v.startsWith('a')),
          'lang': AttributeRule.any(),
        }),
        'i': const ElementRule(),
      });
      final b = RuleSet({
        'b': ElementRule(attributes: {
          'title': AttributeRule.where((v) => v.endsWith('b')),
        }),
        'u': const ElementRule(),
      });
      String s(String html) => sanitizeHtml(html, rules: a.intersection(b));
      expect(s('<i>x</i><u>y</u><b>z</b>'), 'xy<b>z</b>');
      expect(s('<b title="ab" lang="en">x</b>'), '<b title="ab">x</b>');
      expect(s('<b title="a">x</b>'), '<b>x</b>');
    });

    test('elements without a rule are unwrapped, not dropped', () {
      expect(sanitizeHtml('<b><x>a<y>b</y>c</x></b>'), '<b>abc</b>');
      // Content the browser never renders as text is not kept either.
      expect(
          sanitizeHtml('<script>a</script><style>b</style><template>c'
              '</template><textarea>d</textarea>'),
          '');
    });

    test('requires unwraps the element when a required attribute is missing',
        () {
      final rules = RuleSet({
        'input': ElementRule(
          requires: {'type'},
          attributes: {
            'type': AttributeRule.where((v) => v == 'checkbox'),
            'checked': AttributeRule.any(),
          },
        ),
        'div': ElementRule(
          requires: {'title'},
          attributes: {'title': AttributeRule.any()},
        ),
      });
      String s(String html) => sanitizeHtml(html, rules: rules);
      expect(s('<input type="checkbox" checked>'),
          '<input type="checkbox" checked="">');
      expect(s('<input type="text">x'), 'x');
      expect(s('<input>x'), 'x');
      // The end tag of an unwrapped element is dropped with it, so the
      // kept outer <div> is closed by its own end tag.
      expect(
          s('<div title="t"><div>x</div>y</div>z'), '<div title="t">xy</div>z');
      expect(
          s('<div><div title="t">x</div>y</div>z'), '<div title="t">x</div>yz');
      expect(
        () => RuleSet({
          'a': ElementRule(requires: {'href'}),
        }),
        throwsArgumentError,
      );
    });

    test('union keeps an element if either rule keeps it', () {
      final a = RuleSet({
        'iframe': ElementRule(
          requires: {'src', 'sandbox'},
          attributes: {
            'src': AttributeRule.url((u) => u.host == 'a.example'),
            'sandbox': AttributeRule.where((v) => v == 'allow-scripts'),
          },
        ),
      });
      final b = RuleSet({
        'iframe': ElementRule(
          requires: {'src'},
          attributes: {
            'src': AttributeRule.url((u) => u.host == 'b.example'),
            'width': AttributeRule.any(),
          },
        ),
      });
      String s(String html) => sanitizeHtml(html, rules: a.union(b));
      expect(s('<iframe src="https://a.example/" sandbox="allow-scripts">'),
          '<iframe src="https://a.example/" sandbox="allow-scripts"></iframe>');
      expect(s('<iframe src="https://b.example/" width="1">'),
          '<iframe src="https://b.example/" width="1"></iframe>');
      // Neither rule keeps this: a requires sandbox, b does not know the
      // host. Flattening the requirements to {src} would have kept it.
      expect(s('<iframe src="https://a.example/"></iframe>x'), 'x');
      // Kept by b only, so only b's attribute grants apply: the result is
      // the union of what each rule would have produced.
      expect(s('<iframe src="https://b.example/" sandbox="allow-scripts">'),
          '<iframe src="https://b.example/"></iframe>');
    });

    test('intersection applies the requirements of both', () {
      final a = RuleSet({
        'a': ElementRule(
          requires: {'href'},
          attributes: {
            'href': AttributeRule.url(),
            'title': AttributeRule.any()
          },
        ),
      });
      final b = RuleSet({
        'a': ElementRule(
          requires: {'title'},
          attributes: {'title': AttributeRule.any()},
        ),
      });
      String s(String html) => sanitizeHtml(html, rules: a.intersection(b));
      expect(s('<a href="/x" title="t">x</a>'), '<a title="t">x</a>');
      expect(s('<a href="/x">x</a>'), 'x');
      expect(s('<a title="t">x</a>'), 'x');
    });

    test('html keeps what safevalues keeps, checked by our policies', () {
      String s(String html) => sanitizeHtml(html, rules: RuleSet.html());
      expect(
          s('<article><select><option selected>x</option></select>'
              '<progress max="2" value="1"></progress></article>'),
          '<article><select><option selected="">x</option></select>'
          '<progress max="2" value="1"></progress></article>');
      expect(
          s('<iframe src="/x"></iframe><input><label for="y">a</label>'
              '<button>b</button><link rel="stylesheet" href="x.css">'),
          'ab');
      expect(s('<div id="x" name="y" class="z" style="a" title="t">a</div>'),
          '<div title="t">a</div>');
      expect(s('<a href="/x" target="_blank" rel="noopener">a</a>'),
          '<a href="/x" target="_blank" rel="noopener">a</a>');
      expect(s('<a href="javascript:x" target="top" rel="opener">a</a>'),
          '<a>a</a>');
      expect(
          s('<video src="https://e.x/v" poster="javascript:x" autoplay>'
              '</video>'),
          '<video src="https://e.x/v" autoplay=""></video>');
      expect(s('<bdo dir="rtl">a</bdo><bdo dir="foo">b</bdo>'),
          '<bdo dir="rtl">a</bdo><bdo>b</bdo>');
      expect(s('<q cite="data:x">a</q>'), '<q>a</q>');
    });

    test('gfm keeps what package:markdown emits', () {
      String s(String html) => sanitizeHtml(html);
      expect(s('<h2 id="user-content-usage">Usage</h2>'),
          '<h2 id="user-content-usage">Usage</h2>');
      expect(s('<h2 id="usage">Usage</h2>'), '<h2>Usage</h2>');
      expect(s('<a name="x" id="getElementById">y</a>'), '<a>y</a>');
      expect(
          s('<pre data-metadata="title=x"><code class="language-dart">'
              'a</code></pre>'),
          '<pre data-metadata="title=x"><code class="language-dart">a</code>'
          '</pre>');
      expect(s('<div class="language-dart">a</div>'), '<div>a</div>');
      expect(s('<div class="markdown-alert markdown-alert-note">a</div>'),
          '<div class="markdown-alert markdown-alert-note">a</div>');
      expect(s('<div class="markdown-alert host">a</div>'), '<div>a</div>');
      expect(
          s('<ul class="contains-task-list"><li class="task-list-item">'
              '<input type="checkbox" checked="true">x</li></ul>'),
          '<ul class="contains-task-list"><li class="task-list-item">'
          '<input type="checkbox" checked="true">x</li></ul>');
      expect(s('<input type="text" value="x">'), '');
      expect(s('<input>'), '');
      expect(
          s('<ol start="3"><li>x</li></ol>'), '<ol start="3"><li>x</li></ol>');
      expect(s('<td align="center">x</td>'), '<td align="center">x</td>');
      expect(
          s('<section class="footnotes"><ol><li id="user-content-fn-1">'
              '<a href="#user-content-fnref-1" class="footnote-backref">↩</a>'
              '</li></ol></section>'),
          '<section class="footnotes"><ol><li id="user-content-fn-1">'
          '<a href="#user-content-fnref-1" class="footnote-backref">↩</a>'
          '</li></ol></section>');
      expect(s('<a href="/x" accesskey="a" tabindex="1" for="y">x</a>'),
          '<a href="/x">x</a>');
      expect(s('<h7>x</h7><a href="/x" target="_blank">y</a>'),
          'x<a href="/x">y</a>');
    });
  });

  group('Rewriters:', () {
    test('HtmlRewriter.attributes runs before the rules', () {
      String sanitize(String html) => sanitizeHtml(html, rewriters: [
            HtmlRewriter.attributes('h2', (attributes) {
              attributes['id'] = 'heading';
              attributes['onclick'] = 'alert(1)';
            }),
          ]);
      // The rules keep only prefixed ids, so the rewrite is filtered out.
      expect(sanitize('<h2>x</h2>'), '<h2>x</h2>');
      String withIds(String html) => sanitizeHtml(
            html,
            rewriters: [
              HtmlRewriter.attributes('h2',
                  (attributes) => attributes['id'] = 'user-content-heading'),
            ],
          );
      expect(withIds('<h2 id="x">x</h2><h3 id="user-content-y">y</h3>'),
          '<h2 id="user-content-heading">x</h2><h3 id="user-content-y">y</h3>');
    });

    test('HtmlRewriter.prefixIds prefixes ids and fragments once', () {
      String s(String html) => sanitizeHtml(
            html,
            rewriters: [HtmlRewriter.prefixIds('user-content-')],
          );
      expect(
          s('<h2 id="a">x</h2><a href="#a">y</a><a href="#">z</a>'),
          '<h2 id="user-content-a">x</h2><a href="#user-content-a">y</a>'
          '<a href="#">z</a>');
      expect(s('<h2 id="user-content-a">x</h2><a href="#user-content-a">y</a>'),
          '<h2 id="user-content-a">x</h2><a href="#user-content-a">y</a>');
      expect(s('<a name="a" href="/p#a">y</a>'), '<a href="/p#a">y</a>');
    });

    test('HtmlRewriter.keepTokens filters a token list', () {
      String s(String html) => sanitizeHtml(
            html,
            rules: RuleSet.gfm().union(RuleSet({
              'span': ElementRule(attributes: {'class': AttributeRule.any()}),
            })),
            rewriters: [
              HtmlRewriter.keepTokens('class', (c) => c.startsWith('ok-')),
            ],
          );
      expect(
          s('<span class="ok-a bad ok-b">x</span><span class="bad">y</span>'),
          '<span class="ok-a ok-b">x</span><span>y</span>');
    });

    test('RuleSet.iframe keeps embeds from the given origin only', () {
      String s(String html) => sanitizeHtml(
            html,
            rules: RuleSet.gfm().union(RuleSet.iframe(
              where: (src) =>
                  src.host == 'www.youtube.com' &&
                  src.path.startsWith('/embed/'),
              sandbox: 'allow-scripts',
            )),
            rewriters: [
              HtmlRewriter.attributes(
                  'iframe', (a) => a['sandbox'] = 'allow-scripts'),
            ],
          );
      expect(
        s('<iframe src="https://www.youtube.com/embed/x" width="560" '
            'allow="camera" name="n" allowfullscreen></iframe>'),
        '<iframe src="https://www.youtube.com/embed/x" width="560" '
        'allowfullscreen="" sandbox="allow-scripts"></iframe>',
      );
      expect(
          s('<iframe src="https://www.youtube.com/watch?v=x"></iframe>a'), 'a');
      expect(s('<iframe src="https://evil.example/embed/x"></iframe>a'), 'a');
    });

    test('package:markdown gitHubWeb output survives gfm', () {
      const source = '''
# Heading *em* `code`

Para with **strong**, ~~del~~, <https://x.y>, [link](http://a.b "t"),
![img](http://i.j/k.png "t"), foo[^1], `#ff0000`.

- [ ] task
- [x] done

3. three

| a | b |
|:--|--:|
| 1 | 2 |

```dart title=x
void main() {}
```

> [!NOTE]
> alert

Line  
break

---

[^1]: note
''';
      final rendered = md.markdownToHtml(
        source,
        extensionSet: md.ExtensionSet.gitHubWeb,
      );
      final sanitized = sanitizeHtml(
        rendered,
        rewriters: [HtmlRewriter.prefixIds('user-content-')],
      );
      // What the renderer wrote, modulo the writer's normalization, the id
      // prefix, and the colour chip's inline style (which no checked rule
      // set can keep).
      final expected = rendered
          .replaceAll(' />', '>')
          .replaceAll('</input>', '')
          .replaceAll(' id="', ' id="user-content-')
          .replaceAll(' href="#', ' href="#user-content-')
          .replaceAll(RegExp(' style="[^"]*"'), '');
      expect(sanitized, expected);
      expect(sanitizeHtml(sanitized), sanitized);
    });

    test('deprecated version 2 parameters still mean the same', () {
      // ignore: deprecated_member_use_from_same_package
      String s(String html) => sanitizeHtml(
            html,
            // ignore: deprecated_member_use_from_same_package
            allowElementId: (id) => id.startsWith('ok-'),
            // ignore: deprecated_member_use_from_same_package
            allowClassName: (c) => c.startsWith('ok-'),
            // ignore: deprecated_member_use_from_same_package
            addLinkRel: (href) => href.startsWith('http') ? ['ugc'] : null,
          );
      expect(s('<h2 id="ok-a" class="ok-b bad">x</h2><p id="bad">y</p>'),
          '<h2 id="ok-a" class="ok-b">x</h2><p>y</p>');
      expect(s('<a href="https://e.x/">a</a><a href="/b">b</a>'),
          '<a href="https://e.x/" rel="ugc">a</a><a href="/b">b</a>');
      expect(
        // ignore: deprecated_member_use_from_same_package
        () => sanitizeHtml('x',
            rules: RuleSet.gfm(), allowClassName: (_) => true),
        throwsArgumentError,
      );
    });

    test('HtmlRewriter.dropElements removes subtrees', () {
      String s(String html) => sanitizeHtml(
            html,
            rewriters: [
              HtmlRewriter.dropElements({'x', 'br'})
            ],
          );
      expect(s('a<x>b<x>c</x>d</x>e<br>f'), 'aef');
    });

    test('HtmlRewriter.addLinkRel merges with existing tokens', () {
      String sanitize(String html) => sanitizeHtml(
            html,
            rewriters: [
              HtmlRewriter.addLinkRel((href) => ['ugc', 'nofollow'])
            ],
          );
      expect(sanitize('<a href="/x" rel="nofollow me">x</a>'),
          '<a href="/x" rel="nofollow me ugc">x</a>');
      expect(sanitize('<a>x</a>'), '<a>x</a>');
    });
  });

  group('HtmlWriter:', () {
    test('throws on names it cannot write', () {
      expect(() => HtmlWriter().startTag('DIV', const {}), throwsArgumentError);
      expect(
          () => HtmlWriter().startTag('image', const {}), throwsArgumentError);
      expect(() => HtmlWriter().startTag('div', {'on click': ''}),
          throwsArgumentError);
    });

    test('balances and escapes', () {
      final writer = HtmlWriter()
        ..startTag('p', {'title': 'a"b<c>&'})
        ..text('x <y> & &amp; &#1; &;', 0, 21)
        ..startTag('br', const {})
        ..startTag('b', const {})
        ..endTag('p')
        ..endTag('nope')
        ..startTag('i', const {});
      expect(writer.finish(),
          '<p title="a&quot;b&lt;c&gt;&amp;">x &lt;y&gt; &amp; &amp; &#1; &amp;;<br><b></b></p><i></i>');
    });
  });

  group('All tokenizers:', () {
    for (final MapEntry(key: name, value: tokenizer) in tokenizers.entries) {
      String sanitize(String html) => sanitizeHtml(html, tokenizer: tokenizer);

      test('$name: basic sanitization', () {
        expect(
          sanitize(
              '<div><p>Hello <a href="https://example.com" onclick="alert(1)">World</a></p></div>'),
          '<div><p>Hello <a href="https://example.com">World</a></p></div>',
        );
        expect(
            sanitize('<a href="javascript:alert(1)">evil</a>'), '<a>evil</a>');
        expect(sanitize('<script>alert("secret")</script>hello'), 'hello');
        expect(sanitize('<div><p>unclosed paragraph'), endsWith('</p></div>'));
        expect(sanitize('<svg/>x<svg>y</svg>z'), 'xyz');
      });

      test('$name: output re-parses to allowed elements only', () {
        // Property check with an independent HTML5 parser: whatever the
        // tokenizer did, the output must only contain allowed elements and
        // attributes with safe URLs, and must be stable under re-sanitizing
        // and under re-parsing (no mutation XSS).
        for (final input in _adversarialInputs) {
          final output = sanitize(input);
          final reason = '$name: "$input" -> "$output"';
          expect(sanitize(output), output, reason: reason);
          final fragment = parseFragment(output);
          final stack = [...fragment.nodes];
          while (stack.isNotEmpty) {
            final node = stack.removeLast();
            if (node is Element) {
              expect(_gfmElements, contains(node.localName), reason: reason);
              for (final MapEntry(:key, :value) in node.attributes.entries) {
                final attribute = key.toString();
                expect(attribute, isNot(startsWith('on')), reason: reason);
                if (_urlAttributes.contains(attribute)) {
                  // Browsers ignore these characters when parsing a scheme.
                  final url =
                      value.replaceAll(_ignoredInUrls, '').toLowerCase();
                  expect(url, isNot(matches(_dangerousScheme)), reason: reason);
                }
              }
            } else {
              expect(node, isA<Text>());
            }
            stack.addAll(node.nodes);
          }
          // Serializing and re-parsing the output's DOM must not change it.
          final serialized = fragment.outerHtml;
          expect(parseFragment(serialized).outerHtml, serialized,
              reason: reason);
        }
      });
    }
  });
}

const _gfmElements = {
  'a', 'abbr', 'b', 'bdo', 'blockquote', 'br', 'caption', 'cite', 'code', //
  'dd', 'del', 'details', 'dfn', 'div', 'dl', 'dt', 'em', 'figcaption',
  'figure', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'h7', 'h8', 'hr', 'i', 'img',
  'ins', 'kbd', 'li', 'mark', 'ol', 'p', 'picture', 'pre', 'q', 'rp', 'rt',
  'ruby', 's', 'samp', 'small', 'source', 'span', 'strike', 'strong', 'sub',
  'summary', 'sup', 'table', 'tbody', 'td', 'tfoot', 'th', 'thead', 'time',
  'tr', 'tt', 'ul', 'var', 'wbr',
};

const _urlAttributes = {'cite', 'href', 'src', 'srcset'};
final _ignoredInUrls = RegExp(r'[\x00-\x20]');
final _dangerousScheme = RegExp(r'^(javascript|data|vbscript):');

const _adversarialInputs = [
  '<img src=x onerror=alert(1)>',
  '<svg><script>alert(1)</script></svg>',
  '<svg></p><style><a id="</style><img src=1 onerror=alert(1)>">',
  '<math><mtext><table><mglyph><style><img src=x onerror=alert(1)>',
  '<noscript><p title="</noscript><img src=x onerror=alert(1)>">',
  '<textarea><p title="</textarea><img src=x onerror=alert(1)>">',
  '<iframe srcdoc="<script>alert(1)</script>"></iframe>',
  '<a href="javascript&colon;alert(1)">x</a>',
  '<a href="&#x6A;avascript:alert(1)">x</a>',
  '<form><input name="attributes"><input name="attributes"></form>',
  '<<script>script>alert(1)<</script>/script>',
  '<script<script>>alert(1)</script</script>>',
  '<!--><script>alert(1)</script>-->',
  '<!-- --!><script>alert(1)</script>-->',
  '<style><img src=x onerror=alert(1)></style>',
  '<p>a &lt;img src=x onerror=alert(1)&gt; b</p>',
  '<p title="&lt;img src=x onerror=alert(1)&gt;">x</p>',
  '<div><p>unclosed <b>bold <i>italic</div>after',
  '<table><tr><td>cell<td>cell2</table>',
  '<a href="x"><a href="y">nested</a></a>',
  '<plaintext><script>alert(1)</script>',
  '<xmp><script>alert(1)</script></xmp>',
  '<template><script>alert(1)</script></template>',
  '<base href="javascript:alert(1)//"><a href="x">x</a>',
  '<body onload=alert(1)><div>x</div>',
  '<p>&amp;lt;script&amp;gt;alert(1)&amp;lt;/script&amp;gt;</p>',
  '<div title="&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;">x</div>',
  '<img src="x" alt="a&quot; onerror=&quot;alert(1)">',
  '<a href="/x" rel="\'><script>alert(1)</script>">x</a>',
  '<my-tag foo"onload="alert(1)"=bar>content</my-tag>',
  '<a title="</a><script>alert(1)</script>">x</a>',
  '</div title="><script>alert(1)</script>"><p>x</p>',
  '<![CDATA[<script>alert(1)</script>]]>',
  '<?xml version="1.0"?><script>alert(1)</script>',
  '<b/onclick=alert(1)>x</b>',
  '<a href=`javascript:alert(1)`>x</a>',
  '<img src="data:image/svg+xml,<svg onload=alert(1)>">',
  '<img name="getElementById" src="x">',
  '<svg/>x<svg>y</svg>z',
  '<math><annotation-xml encoding="text/html"><script>alert(1)</script></annotation-xml></math>',
  '<image src=x onerror=alert(1)>',
  '<a href="https://good.com@evil.com/">x</a>',
];
