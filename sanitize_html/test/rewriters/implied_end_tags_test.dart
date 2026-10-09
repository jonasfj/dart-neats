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
import 'package:sanitize_html/sanitize_html.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  group('HtmlRewriter.impliedEndTags:', () {
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
}
