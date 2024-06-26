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

import 'package:collection/collection.dart';

/// An [Equality] for deep-comparison of JSON values / structures.
///
/// Unlike [DeepCollectionEquality] this [Equality] will throw, if it encounters
/// an unsupported type. This [Equality] supports values of the following types:
///  * `String`,
///  * `num` (`int` or `double`),
///  * `null`,
///  * `bool`,
///  * `List<Object?>`, and,
///  * `Map<String, Object?>`.
const Equality<Object?> deepJsonEquality = _DeepJsonEquality();

class _DeepJsonEquality implements Equality<Object?> {
  const _DeepJsonEquality();

  @override
  bool equals(Object? o1, Object? o2) {
    switch ((o1, o2)) {
      case (final String a, final String b):
        return a == b;
      case (final num a, final num b):
        return a == b;
      case (final bool a, final bool b):
        return a == b;
      case (null, null):
        return true;
      case (List<Object?> a, List<Object?> b):
        if (a.length != b.length) {
          return false;
        }
        final N = a.length;
        for (var i = 0; i < N; i++) {
          if (!equals(a[i], b[i])) {
            return false;
          }
        }
        return true;
      case (Map<String, Object?> a, Map<String, Object?> b):
        if (a.length != b.length) {
          return false;
        }
        for (final MapEntry(:key, :value) in a.entries) {
          if (!b.containsKey(key) || !equals(value, b[key])) {
            return false;
          }
        }
        return true;
      default:
        // Note. we could consider checking if o1 and o2 have valid types.
        return false;
    }
  }

  @override
  int hash(Object? o) => switch (o) {
        (String value) => value.hashCode,
        (num value) => value.toDouble().hashCode,
        (bool value) => value.hashCode,
        null => null.hashCode,
        (List<Object?> array) => Object.hashAll(array.map(hash)),
        (Map<String, Object?> object) =>
          Object.hashAllUnordered(object.entries.map(
            (e) => Object.hash(e.key.hashCode, hash(e.value)),
          )),
        _ => throw ArgumentError.value(
            o, 'o', 'only valid JSON values are allowed'),
      };

  @override
  bool isValidKey(Object? o) => switch (o) {
        String _ => true,
        num _ => true,
        bool _ => true,
        null => true,
        List<Object?> array => array.every(isValidKey),
        Map<String, Object?> object => object.values.every(isValidKey),
        _ => false,
      };
}
