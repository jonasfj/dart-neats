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

/// # UNTRUSTED: tokenizer backed by the `package:html` tree builder.
///
/// Parses the input into a DOM with `package:html` (which implements the
/// WHATWG tree construction algorithm, including adoption agency and foster
/// parenting) and walks the tree, so misnested input is reported the way a
/// browser would structure it. Several times slower than the streaming
/// tokenizers.
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' show parseFragment;

import '../html_token_sink.dart';

/// See `HtmlTokenizer.dom`.
void tokenizeDom(String html, HtmlTokenSink sink) {
  // Iterative walk; each frame is a node and the index of the next child.
  final stack = <(Node, int)>[(parseFragment(html), 0)];
  while (stack.isNotEmpty) {
    final (node, index) = stack.removeLast();
    if (index < node.nodes.length) {
      stack.add((node, index + 1));
      final child = node.nodes[index];
      if (child is Text) {
        // The tree builder has decoded character references; the sink
        // expects text as written in HTML, so re-encode the only character
        // that can begin a reference.
        final text = child.data.replaceAll('&', '&amp;');
        sink.text(text, 0, text.length);
      } else if (child is Element) {
        final name = child.localName!.toLowerCase();
        sink.startTag(
          name,
          {
            for (final MapEntry(:key, :value) in child.attributes.entries)
              key.toString().toLowerCase(): value,
          },
        );
        // The tree builder drops a newline right after these start tags;
        // put it back when the next one would otherwise be dropped too, so
        // that sanitizing the output again does not lose another line.
        // https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inbody
        if (child.nodes case [Text(:final data), ...]
            when (name == 'pre' || name == 'listing') &&
                data.startsWith('\n')) {
          sink.text('\n', 0, 1);
        }
        stack.add((child, 0));
      }
    } else if (node is Element) {
      sink.endTag(node.localName!.toLowerCase());
    }
  }
}
