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

/// # TRUSTED: decides which URLs may appear in URL-valued attributes.
///
/// A URL attribute is dangerous when the browser resolves it to a scheme that
/// executes code (`javascript:`), smuggles a document (`data:`), or is handed
/// to an external handler (`vbscript:`, `file:`, custom protocol handlers).
/// The policy is an allowlist of schemes (`http`, `https`, `mailto`) plus
/// relative URLs, applied wherever a rule set declares `AttributeRule.url`.
///
/// ## Why the browser sees what we validated
///
/// `SaneHtmlWriter` escapes attribute values exactly, so the string a browser
/// decodes from the output is the string these functions accepted, up to the
/// parser's input preprocessing (CR and CRLF become LF, U+0000 becomes
/// U+FFFD):
/// https://html.spec.whatwg.org/multipage/parsing.html#preprocessing-the-input-stream
/// That cannot change a verdict: [isSafeUrl] removes CR and LF and refuses
/// U+0000 before deciding.
///
/// ## Why not `Uri.parse`
///
/// `dart:core`'s [Uri] implements RFC 3986, browsers implement the WHATWG URL
/// Standard. They disagree exactly where attackers look: browsers strip tab
/// and newline anywhere and leading/trailing C0 controls before parsing, so
/// `jav\tascript:alert(1)` is a `javascript:` URL to a browser but a relative
/// path to [Uri]. This file mirrors the browser's preprocessing and then
/// applies a scheme rule that is strictly more conservative than the
/// browser's. Where [Uri] would still disagree with the browser about the
/// _host_ (`\` and userinfo, below) the URL is refused, so that a `Uri`
/// handed to `AttributeRule.urlWhere` has the host the browser will use.
library;

const _allowedSchemes = {'https', 'http', 'mailto'};

/// Whether [url] may be used as the value of a URL attribute.
///
/// Allows `http:`, `https:`, `mailto:` and relative URLs.
bool isSafeUrl(String url) {
  // Browsers remove ASCII tab and newline anywhere and strip leading/trailing
  // C0 controls and spaces before parsing. Do the same, except that any other
  // control character is refused outright: it has no legitimate use, and
  // refusing it avoids reasoning about how each parser percent-encodes it.
  // https://url.spec.whatwg.org/#concept-basic-url-parser
  StringBuffer? cleaned; // Only allocated if there is something to remove.
  for (var i = 0; i < url.length; i++) {
    final c = url.codeUnitAt(i);
    if (c == 0x09 || c == 0x0A || c == 0x0D) {
      cleaned ??= StringBuffer(url.substring(0, i));
      continue;
    }
    if (c < 0x20 || c == 0x7F) {
      return false;
    }
    cleaned?.writeCharCode(c);
  }
  final candidate = (cleaned?.toString() ?? url).trim();

  // Browsers treat `\` as `/` in special schemes, RFC 3986 parsers do not, so
  // `\\evil.com` is `//evil.com` to the browser and a relative path to `Uri`.
  // Refusing `\` anywhere keeps both readings identical.
  // https://url.spec.whatwg.org/#special-scheme
  if (candidate.contains(r'\')) {
    return false;
  }

  // A browser scheme is `[a-zA-Z][a-zA-Z0-9+.-]*` followed by `:`:
  // https://url.spec.whatwg.org/#scheme-start-state
  // https://url.spec.whatwg.org/#scheme-state
  // None of those characters is `/`, `?` or `#`, so every browser scheme is
  // terminated by the first `:` that precedes the first `/`, `?` or `#`.
  // Treating any such prefix as a scheme (RFC 3986 section 4.2) accepts
  // exactly the browser schemes in [_allowedSchemes] and rejects everything
  // else, including strings a browser would parse as relative URLs.
  // https://www.rfc-editor.org/rfc/rfc3986#section-4.2
  var rest = 0;
  for (var i = 0; i < candidate.length; i++) {
    final c = candidate.codeUnitAt(i);
    if (c == 0x2F /* / */ || c == 0x3F /* ? */ || c == 0x23 /* # */) {
      break;
    }
    if (c == 0x3A /* : */) {
      if (!_allowedSchemes.contains(_asciiLowerCase(candidate, 0, i))) {
        return false;
      }
      rest = i + 1;
      break;
    }
  }

  // Refuse userinfo. In an authority (`//...`) the host starts after the last
  // `@`, so `https://good.com@evil.com` goes to evil.com; `Uri` agrees, but
  // the combination with other quirks has a long history of parser
  // disagreement, and there is no legitimate use in sanitized content.
  // https://url.spec.whatwg.org/#authority-state
  if (candidate.startsWith('//', rest)) {
    for (var i = rest + 2; i < candidate.length; i++) {
      final c = candidate.codeUnitAt(i);
      if (c == 0x2F /* / */ || c == 0x3F /* ? */ || c == 0x23 /* # */) {
        break;
      }
      if (c == 0x40 /* @ */) {
        return false;
      }
    }
  }
  return true;
}

/// Whether [srcset] is a well-formed `srcset` whose every URL is safe.
///
/// Candidates are comma separated; each is a URL optionally followed by a
/// width (`100w`) or density (`1.5x`) descriptor. Anything else is refused.
/// https://html.spec.whatwg.org/multipage/images.html#parse-a-srcset-attribute
bool isSafeSrcset(String srcset) {
  for (final candidate in srcset.split(',')) {
    final parts = candidate.trim().split(_asciiWhitespace);
    if (parts.length > 2 || parts.first.isEmpty || !isSafeUrl(parts.first)) {
      return false;
    }
    if (parts.length == 2 && !_srcsetDescriptor.hasMatch(parts[1])) {
      return false;
    }
  }
  return true;
}

final _asciiWhitespace = RegExp(r'[ \t\n\f\r]+');
final _srcsetDescriptor = RegExp(r'^(?:[0-9]+w|[0-9]*\.?[0-9]+x)$');

/// `s[start..end)` with only `A`-`Z` lowercased, like the URL parser does
/// for schemes.
///
/// Unicode case folding (`String.toLowerCase`) would map other characters to
/// ASCII letters (e.g. U+212A KELVIN SIGN to `k`), which the browser does not.
/// https://url.spec.whatwg.org/#scheme-state
String _asciiLowerCase(String s, int start, int end) {
  final codeUnits = List<int>.generate(end - start, (i) {
    final c = s.codeUnitAt(start + i);
    return c >= 0x41 /* A */ && c <= 0x5A /* Z */ ? c | 0x20 : c;
  });
  return String.fromCharCodes(codeUnits);
}
