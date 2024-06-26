// Copyright 2023 Google LLC
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

/*

https://datatracker.ietf.org/doc/html/rfc3986#appendix-A
fragment      = *( pchar / "/" / "?" )
pchar         = unreserved / pct-encoded / sub-delims / ":" / "@"
unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
pct-encoded   = "%" HEXDIG HEXDIG
sub-delims    = "!" / "$" / "&" / "'" / "(" / ")"
              / "*" / "+" / "," / ";" / "="

https://datatracker.ietf.org/doc/html/rfc2234#section-6
ALPHA          =  %x41-5A / %x61-7A   ; A-Z / a-z
DIGIT          =  %x30-39           ; 0-9
HEXDIG         =  DIGIT / "A" / "B" / "C" / "D" / "E" / "F"

test with:
final s = '/𒀒';
𒀖
*/

import 'dart:convert';

final _fragmentEscaped = RegExp(r'''[^a-zA-Z0-9!$&'()*+,;=:@/?~_.-]+''');
String encodeFragment(String string) {
  return string.replaceAllMapped(_fragmentEscaped, (match) {
    return utf8
        .encode(match.group(0)!)
        .map((c) => '%' + c.toRadixString(16).padLeft(2, '0'))
        .join('');
  });
}

String decodeFragment(String fragment) => Uri.decodeComponent(fragment);
