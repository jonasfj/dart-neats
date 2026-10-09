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

/// # TRUSTED (policy data): the `rel` values the default rule sets keep.
///
/// The [link types][1] the HTML specification defines for `<a>` and
/// `<area>`, plus `ugc` and `sponsored` (registered extensions search
/// engines act on), without `opener`, which re-enables `window.opener` for
/// `target="_blank"` links. The whole value is kept or dropped: a `rel` with
/// an unknown token is dropped.
///
/// [1]: https://html.spec.whatwg.org/multipage/links.html#linkTypes
library;

import '../space_separated_tokens.dart';

const _anchorLinkTypes = <String>{
  'alternate',
  'author',
  'bookmark',
  'external',
  'help',
  'license',
  'me',
  'next',
  'nofollow',
  'noopener',
  'noreferrer',
  'prev',
  'privacy-policy',
  'search',
  'sponsored',
  'tag',
  'terms-of-service',
  'ugc',
};

/// Whether [value] is a non-empty list of link types for `<a>`.
bool isAnchorRelList(String value) =>
    everyToken(value, _anchorLinkTypes.contains);
