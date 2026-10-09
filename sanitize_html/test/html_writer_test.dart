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

void main() {
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
}
