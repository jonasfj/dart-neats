HTML Sanitizer for Dart
=======================

When embedding HTML from an untrusted source in a website it is important to
sanitize the HTML to prevent injection of untrusted JavaScript (XSS exploits).
This package provides a simple function sanitizing HTML to prevent XSS exploits
and limit interference with other elements on the page.

**Disclaimer:** This is not an officially supported Google product.

```dart
import 'package:sanitize_html/sanitize_html.dart' show sanitizeHtml;

void main() {
  print(sanitizeHtml('<a href="javascript:alert();">evil link</a>'));
  // Prints: <a>evil link</a>
  // Which is a lot less evil :)
}
```

By default elements and attributes are filtered in-line with the
[rules employed by GitHub][1] when sanitizing GFM (GitHub Flavored Markdown).
This removes all inline JavaScript, CSS, `<form>`, and other elements that
could be used for XSS. The default rules are stricter than necessary to
guard against XSS, as they also attempt to prevent the sanitized HTML from
interfering with the page it is injected into: no `id` or `class` attributes
unless explicitly allowed, no CSS, no `name` except on `<a>`.

Rules and rewriters are optional parameters:

```dart
final safe = sanitizeHtml(
  untrusted,
  rules: RuleSet.gfm(allowElementId: true),
  rewriters: [HtmlRewriter.addLinkRel((href) => ['ugc', 'nofollow'])],
);
```

## Rules

A `RuleSet` declares which elements are allowed and, for each, which
attributes and how their values are filtered. Elements without a rule are
removed together with their content; attributes without a rule are removed.

```dart
final rules = RuleSet.gfm().union(RuleSet({
  'video': ElementRule(attributes: {
    'src': AttributeRule.url(),
    'controls': AttributeRule.any(),
  }),
  'iframe': ElementRule(attributes: {
    'src': AttributeRule.url((u) => u.host == 'www.youtube.com'),
    'width': AttributeRule.where((v) => int.tryParse(v) != null),
  }),
}));
```

An `AttributeRule` only ever keeps or drops a value; it never rewrites. So
`union` keeps what either rule set keeps and `intersection` what both keep,
with no surprises. Rewriting, such as adding `rel="ugc"` to links, ids to
headings, or removing all but a few class names, is done by _rewriters_
(`addLinkRel`, `rewriteAttributes`) which run before the rules and therefore
cannot add anything the rules would not allow.

`RuleSet(...)` refuses grants that defeat the purpose of sanitizing and throws
`UnsupportedError`: `script`, `style`, `base`, `meta`, `link`, `form`, `svg`,
`math`, ... as elements; `on*`, `style`, `srcdoc`, `is`, `form*`, `ping`, ...
as attributes; and URL attributes (`href`, `src`, `cite`, ...) bound to
anything but `AttributeRule.url` (`srcset` to `AttributeRule.srcset`). `RuleSet.unsafe(...)` waives these checks for callers
who have reviewed what they allow.

## The guarantee

Whatever the input, the output of a sanitizer:

 * contains only elements and attributes its `RuleSet` allows, with values
   its `AttributeRule`s kept,
 * never contains comments, doctypes, CDATA sections, or any text that an
   HTML parser can interpret as markup,
 * is balanced: every start tag is closed, at most 128 levels deep.

A browser parsing the output creates **no element and no attribute that is
not in it**. The tree builder may still re-nest misnested formatting elements
and insert implied `tbody`, `tr`, `colgroup` or `p` elements, and a rule set
that allows `plaintext` or `xmp` will see the browser turn later markup into
text; but nothing new appears. With a `RuleSet()` built with the default
checks, no script executes and no URL has a scheme other than `http`, `https`
or `mailto`.

The output is safe when inserted where the HTML parser is in its _data
state_: as content of `<body>`, `<div>`, etc. in an HTML document. It is
**not** safe inside an attribute value, `<script>`, `<style>`, `<textarea>`,
`<title>`, `<svg>`, `<math>`, or an XML document.

The guarantee is about script execution and markup injection. It does not
make content trustworthy: links can still point to malicious sites, images
can still track viewers, and text can still deceive. And it says nothing
about scripts the host page runs over the output: client-side template
frameworks that evaluate attributes (`x-on:click`, `v-on:click`, `ng-click`,
`hx-get`, ...) must not be mounted on a container holding sanitized HTML
unless the rules are known not to allow such attributes (the GFM rules do
not).

## How it works, and what is trusted

Most sanitizers try to recognize dangerous input, which means they must
model every quirk of every HTML parser. This package instead only ever
_produces_ output from a small, closed grammar in which text cannot become
markup. The HTML tokenizer only creates tags from a raw `<` in its data state;
the writer never emits a raw `<`, always double-quotes attribute values with
`"` escaped, and restricts tag and attribute names to a safe alphabet. That
is the whole argument; it does not depend on how the input was parsed.

```
input ─► HtmlTokenizer ─► HtmlRewriter.impliedEndTags() ─► rewriters ─► HtmlRewriter.sanitizer(rules) ─► HtmlWriter ─► output
         (untrusted)      (untrusted)                    (untrusted)   (trusted)                       (trusted)
```

Everything between tokenizer and writer is an `HtmlRewriter`; `HtmlTokenizer`,
`HtmlTokenSink` and `HtmlWriter` are exported too, for custom pipelines.

The **trusted base** is small and reviewable:

 * [`lib/src/html_writer.dart`](lib/src/html_writer.dart): the only
   code that writes output. Documents the tokenizer-state argument with
   references to the HTML specification.
 * [`lib/src/url_policy.dart`](lib/src/url_policy.dart): which URLs may appear
   in URL attributes, and why `Uri.parse` is not used.
 * [`lib/src/attribute_rule.dart`](lib/src/attribute_rule.dart),
   [`lib/src/element_rule.dart`](lib/src/element_rule.dart),
   [`lib/src/rule_set.dart`](lib/src/rule_set.dart): how rules are applied.
 * [`lib/src/grant_assertions.dart`](lib/src/grant_assertions.dart): what a
   checked `RuleSet` refuses, and why.
 * [`lib/src/gfm_rules.dart`](lib/src/gfm_rules.dart): the default allowlists
   (policy data, no logic that affects escaping).

Everything else is **untrusted** in the sense that a bug there can make
output uglier (markup shown as text, content dropped) but never unsafe:

 * `lib/src/tokenizer/`: three interchangeable tokenizers.
   `HtmlTokenizer.streaming` (default) follows the WHATWG tokenizer states
   without building a tree; `HtmlTokenizer.simple` is about 120 lines for
   well-formed input; `HtmlTokenizer.dom` parses a full tree with
   `package:html` and handles misnested markup like a browser, at several
   times the cost (and `package:html`'s tree builder is superlinear on deeply
   nested input, so prefer the streaming tokenizers for input of unbounded
   size).
 * `lib/src/sanitizer.dart`: applies the rule set; its only state is a
   counter for the element being dropped.
 * `lib/src/implied_end_tags.dart`: the tree builder's implied end tags, so
   sloppy input gives tidy output.
 * `lib/src/rewriters.dart`: `rewriteAttributes` and `addLinkRel`.

Because the writer escapes attribute values exactly, the URL policy and the
browser's URL parser see identical strings (up to the HTML parser's
CR/LF/NUL input preprocessing, which cannot change a verdict); the
tokenizers' character reference decoding therefore is not security relevant
either.

[1]: https://github.com/jch/html-pipeline/blob/master/lib/html/pipeline/sanitization_filter.rb
