## v3.0.0-wip
 * **Breaking:** rewritten to be _safe by construction_: output is produced
   only by a small, audited writer (`HtmlWriter`) that emits balanced
   lower-case tags, always double-quoted and escaped attribute values, and
   escaped text. See the README for the guarantee and what is trusted.
 * **Breaking:** elements the rules do not allow are _unwrapped_ (tags
   removed, content kept) instead of removed with their content, as other
   Markdown sanitizers do. `HtmlRewriter.dropElements({...})` removes
   subtrees. Content of `script`, `style`, `template` and the other
   RAWTEXT/RCDATA elements is still never kept.
 * Added `ElementPattern` and `RuleSet(..., exemptions: [...])`: exact forms
   of an element kept as exemptions from the rules, e.g. an `<input>` only
   with `type="checkbox"` or an `<iframe>` only from one origin and
   sandboxed. Patterns are tried first and never merged.
 * **Breaking:** `sanitizeHtml` takes `rules`, `rewriters` and `tokenizer`.
   The version 2 parameters `allowElementId`, `allowClassName` and
   `addLinkRel` still work but are deprecated and cannot be combined with
   `rules` or `rewriters`; `allowElements` is gone (use
   `RuleSet.gfm().union(RuleSet({...}))`).
 * Added `RuleSet`, `ElementRule` and `AttributeRule` (`any`, `url([where])`,
   `srcset([where])`, `where`) for declaring which elements and attributes are
   kept, with `union`, `without` and `restrict`. Attribute rules only keep
   or drop values, never rewrite them.
 * **Breaking:** `RuleSet.gfm()` takes no parameters and follows html-pipeline
   v3 plus what `package:markdown` emits for `ExtensionSet.gitHubWeb`: `id`
   only with the `user-content-` prefix (GitHub's namespace for author ids;
   `HtmlRewriter.prefixIds` adds it, and `package:markdown` is expected to
   emit it), `class` only with `markdown-*` tokens (plus the names
   `package:markdown` emits today) and `language-*` on `<code>`,
   `data-metadata` on `<pre>`, `<input type="checkbox">`, `<section>`;
   `name`, `target`, `accesskey`, `tabindex`, `aria-describedby`,
   `aria-labelledby`, `color`, `vspace`, `cellpadding`, `cellspacing`,
   `h7` and `h8` are no longer kept; `img[loading]` is.
 * Added `RuleSet.html()`, the element and attribute tables of Google's
   safevalues sanitizer with this package's URL and `rel` checks, and
   `ElementPattern.iframe(where:, sandbox:)` and `ElementPattern.checkbox`
   as ready-made exemptions, and `RuleSet.withExemptions`. `RuleSet.html()`
   drops `autofocus`, `download`, `itemref`, `usemap`, `required`, `slot`
   and `<slot>`, which safevalues keeps, because each binds the content to
   something the host page owns.
 * `RuleSet(...)` throws `UnsupportedError` for grants that defeat the purpose
   of sanitizing (elements `script`, `style`, `base`, `meta`, `link`, `html`,
   `head`, `body`, `frameset`, `frame`, `form`, `object`, `embed`, `applet`,
   `isindex`, `noscript`, `noembed`, `noframes`, `svg`, `math`; attributes
   `on*`, `style`, `srcdoc`, `is`, `form*`, `ping`, `attributionsrc`,
   `popovertarget*`, `command`, `commandfor`, `shadowrootmode`; URL
   attributes not bound to `AttributeRule.url` / `srcset`) and
   `ArgumentError` for names the writer cannot write (`'DIV'`, `'a b'`,
   `'image'`). `RuleSet.unsafe(...)` waives the `UnsupportedError`s.
 * Added `HtmlRewriter` with `attributes`, `addLinkRel`, `prefixIds`,
   `keepTokens` and `dropElements` rewriters, which run before the rules are
   applied, and a constructor for custom rewriters.
 * Added the pipeline building blocks `HtmlTokenSink`, `HtmlTokenizer` and
   `HtmlWriter` (with `HtmlRewriter.sanitizer` and
   `HtmlRewriter.impliedEndTags`) and three interchangeable tokenizers
   (`streaming` (default), `simple`, `dom`); tokenizers are not security
   relevant. `package:html` is only used by `HtmlTokenizer.dom`.
 * **Breaking:** output is normalized rather than re-serialized: tag and
   attribute names are lower-case, attribute values double-quoted, void
   elements written without `/`, unclosed elements closed, and the tree
   builder's implied end tags applied (`<p>` closed by block elements, list
   items, cells, rows, row groups, options and headings closed by siblings,
   `<a>` closed by a nested `<a>`). Sanitizing is idempotent.
 * **Breaking:** comments are no longer preserved, no implied `<tbody>` or
   trailing `<p></p>` is inserted, and non-ASCII text is written as is rather
   than re-encoded as named character references.
 * **Breaking:** character references in text are preserved as written
   (`&copy;` stays `&copy;`, a lone `&` becomes `&amp;`); attribute values are
   decoded and re-escaped.
 * **Breaking:** `name` is only kept on `<a>`; `accesskey`, `usemap`, and form
   related attributes (`action`, `method`, `enctype`, `accept`,
   `accept-charset`, `for`, `prompt`) are no longer kept. `rel` is dropped
   unless every token is a link type the HTML specification defines for
   `<a>` (or `ugc` / `sponsored`), and none is `opener`.
 * URL attributes (`href`, `src`, `cite`, `longdesc`, `srcset`, ...) must be
   relative or use `http:`, `https:` or `mailto:`; URLs containing control
   characters, `\`, userinfo (`https://user@host`), a percent-encoded host,
   or anything but exactly `//` after `http:`/`https:` are rejected.
 * Nesting is capped at 128 levels: like Blink, a deeper start tag closes the
   innermost open element and becomes its sibling.
 * Removed the dependency on `package:meta`.
 * Roughly 4x faster than `v2.1.0` on the included benchmark.

## v2.2.0
 * Allow the `<picture>` and `<source>` elements, with `srcset` on `<source>`,
   matching the [`html-pipeline` allowlist](https://github.com/gjtorikian/html-pipeline/blob/main/lib/html_pipeline/sanitization_filter.rb)
   this package is modeled on. Enables theme-aware images via `<picture>` with
   `prefers-color-scheme`.

## v2.1.0
 * Remove custom HTML rendering logic in favor of logic from `package:html`.
 * Added `topics` to `pubspec.yaml`.
 * `rel` attributes added through `addLinkRel` are appended to existing ones.

## v2.0.0
 * Migrate to null safety.

## v1.4.1
 * Make `addLinkRel` optional. [Issue](https://github.com/google/dart-neats/issues/71).

## v1.4.0
 * Added `addLinkRel` option to `sanitize_html`. This will allow users to
   [qualify outbound links](https://support.google.com/webmasters/answer/96569)
   which may [help prevent comment spam](https://support.google.com/webmasters/answer/81749).

## v1.3.0
 * Only print self-closing tags for
   [void-elements](https://www.w3.org/TR/html5/syntax.html#void-elements).
   This could cause `<strong />` in HTML documents, which is can be interpreted
   as an opening tag by HTML5 parsers, causing the HTML structure to break.

## v1.2.0
 * Does not depend on `universal_html`, uses custom HTML rendering for the output.
 * Allowed classes are kept, even if there are non-allowed classes present on the same element.

## v1.1.0
 * Add options `allowElementId` and `allowClassName` to allow specific element
   ids and class names.

## v1.0.0
 * Initial release.
