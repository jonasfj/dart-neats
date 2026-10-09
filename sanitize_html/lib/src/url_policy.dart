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
/// `HtmlWriter` escapes attribute values exactly, so the string a browser
/// decodes from the output is the string these functions accepted, up to the
/// parser's [input preprocessing][1] (CR and CRLF become LF, U+0000 becomes
/// U+FFFD). That cannot change a verdict: [cleanUrl] removes CR and LF and
/// refuses U+0000 before deciding.
///
/// ## Why not `Uri.parse`
///
/// `dart:core`'s [Uri] implements RFC 3986, browsers implement the WHATWG URL
/// Standard. They disagree exactly where attackers look: browsers strip tab
/// and newline anywhere and leading/trailing C0 controls before parsing, so
/// `jav\tascript:alert(1)` is a `javascript:` URL to a browser but a relative
/// path to [Uri]. This file mirrors the browser's preprocessing and then
/// applies a scheme rule that is strictly more conservative than the
/// browser's.
///
/// ## Why `Uri` then agrees with the browser about the host
///
/// `AttributeRule.url(where)` hands a [Uri] to user code, typically to check
/// `uri.host`. The forms where a WHATWG parser and [Uri] would find different
/// hosts are refused, so the host is the one the browser will use: `\` in
/// place of `/`, fewer or more than two slashes after `http:`/`https:`,
/// userinfo (`good.com@evil.com`) and percent-encoding in the authority.
/// None has a legitimate use in sanitized content. The host is otherwise
/// taken literally: it is not IDNA-mapped and IPv4 forms are not
/// canonicalized, so comparing it to an _allowlist_ is sound while a denylist
/// is not.
///
/// [1]: https://html.spec.whatwg.org/multipage/parsing.html#preprocessing-the-input-stream
library;

import 'space_separated_tokens.dart';

const _specialSchemes = {'https', 'http'};
const _otherSchemes = {'mailto'};

/// [url] as the browser will parse it, or `null` if it may not be used as
/// the value of a URL attribute.
///
/// Allows `http:`, `https:`, `mailto:` and relative URLs.
String? cleanUrl(String url) {
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
      return null;
    }
    cleaned?.writeCharCode(c);
  }
  final candidate = _stripSpaces(cleaned?.toString() ?? url);

  // Browsers treat `\` as `/` in special schemes, RFC 3986 parsers do not, so
  // `\\evil.com` is `//evil.com` to the browser and a relative path to `Uri`.
  // Refusing `\` anywhere keeps both readings identical.
  // https://url.spec.whatwg.org/#special-scheme
  if (candidate.contains(r'\')) {
    return null;
  }

  // A browser scheme is `[a-zA-Z][a-zA-Z0-9+.-]*` followed by `:`:
  // https://url.spec.whatwg.org/#scheme-start-state
  // https://url.spec.whatwg.org/#scheme-state
  // None of those characters is `/`, `?` or `#`, so every browser scheme is
  // terminated by the first `:` that precedes the first `/`, `?` or `#`.
  // Treating any such prefix as a scheme (RFC 3986 section 4.2) accepts
  // exactly the allowed browser schemes and rejects everything else,
  // including strings a browser would parse as relative URLs.
  // https://www.rfc-editor.org/rfc/rfc3986#section-4.2
  var rest = 0;
  var special = false;
  for (var i = 0; i < candidate.length; i++) {
    final c = candidate.codeUnitAt(i);
    if (c == 0x2F /* / */ || c == 0x3F /* ? */ || c == 0x23 /* # */) {
      break;
    }
    if (c == 0x3A /* : */) {
      final scheme = _asciiLowerCase(candidate, 0, i);
      special = _specialSchemes.contains(scheme);
      if (!special && !_otherSchemes.contains(scheme)) {
        return null;
      }
      rest = i + 1;
      break;
    }
  }

  // After `http:`/`https:` a browser skips any number of slashes and takes
  // the host from there, so `https:evil.com` and `https:///evil.com` reach
  // evil.com; RFC 3986 reads them as a path. Require exactly `//` followed by
  // a host character so both readings agree.
  // https://url.spec.whatwg.org/#special-authority-ignore-slashes-state
  if (special) {
    if (!candidate.startsWith('//', rest) || rest + 2 >= candidate.length) {
      return null;
    }
    if (_endsAuthority(candidate.codeUnitAt(rest + 2))) {
      return null;
    }
  }

  // In an authority (`//...`) refuse userinfo and percent-encoding. The host
  // starts after the last `@`, so `https://good.com@evil.com` goes to
  // evil.com, and browsers percent-decode the host (`e%76il.com` is
  // evil.com) while `Uri` does not. Neither has a legitimate use.
  // https://url.spec.whatwg.org/#authority-state
  // https://url.spec.whatwg.org/#concept-host-parser
  if (candidate.startsWith('//', rest)) {
    for (var i = rest + 2; i < candidate.length; i++) {
      final c = candidate.codeUnitAt(i);
      if (_endsAuthority(c)) {
        break;
      }
      if (c == 0x40 /* @ */ || c == 0x25 /* % */) {
        return null;
      }
    }
  }
  return candidate;
}

/// The candidate URLs of [srcset] as the browser will parse them, or `null`
/// if [srcset] is not a well-formed `srcset` whose every URL is safe.
///
/// [Candidates][1] are comma separated; each is a URL optionally followed by
/// a width (`100w`) or density (`1.5x`) descriptor. Anything else is refused.
///
/// [1]: https://html.spec.whatwg.org/multipage/images.html#parse-a-srcset-attribute
List<String>? cleanSrcset(String srcset) {
  final urls = <String>[];
  for (final candidate in srcset.split(',')) {
    final parts = candidate.trim().split(asciiWhitespace);
    if (parts.length > 2 || parts.first.isEmpty) {
      return null;
    }
    if (parts.length == 2 && !_srcsetDescriptor.hasMatch(parts[1])) {
      return null;
    }
    final url = cleanUrl(parts.first);
    if (url == null) {
      return null;
    }
    urls.add(url);
  }
  return urls;
}

final _srcsetDescriptor = RegExp(r'^(?:[0-9]+w|[0-9]*\.?[0-9]+x)$');

bool _endsAuthority(int c) =>
    c == 0x2F /* / */ || c == 0x3F /* ? */ || c == 0x23 /* # */;

/// [s] without leading and trailing spaces.
///
/// The browser strips leading and trailing C0 controls and spaces; the
/// controls were refused above, and `String.trim` would also strip Unicode
/// whitespace the browser keeps.
String _stripSpaces(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && s.codeUnitAt(start) == 0x20) {
    start++;
  }
  while (end > start && s.codeUnitAt(end - 1) == 0x20) {
    end--;
  }
  return start == 0 && end == s.length ? s : s.substring(start, end);
}

/// `s[start..end)` with only `A`-`Z` lowercased, like the URL parser does
/// for schemes.
///
/// Unicode case folding (`String.toLowerCase`) would map other characters to
/// ASCII letters (e.g. U+212A KELVIN SIGN to `k`), which the
/// [URL parser][1] does not.
///
/// [1]: https://url.spec.whatwg.org/#scheme-state
String _asciiLowerCase(String s, int start, int end) {
  final codeUnits = List<int>.generate(end - start, (i) {
    final c = s.codeUnitAt(start + i);
    return c >= 0x41 /* A */ && c <= 0x5A /* Z */ ? c | 0x20 : c;
  });
  return String.fromCharCodes(codeUnits);
}
