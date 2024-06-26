// Copyright 2023 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the 'License');
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:jsv/equality.dart';
import 'package:jsv/jsonpointer.dart';
import 'package:test/test.dart';

/// Test document from the [RFC 6901 section 5][1].
///
/// [1]: https://www.rfc-editor.org/rfc/rfc6901#section-5
final _testDocument = <String, Object?>{
  'foo': <Object?>['bar', 'baz'],
  '': 0,
  'a/b': 1,
  'c%d': 2,
  'e^f': 3,
  'g|h': 4,
  'i\\j': 5,
  'k"l': 6,
  ' ': 7,
  'm~n': 8
};

/// Test cases from the [RFC 6901 section 5][1].
///
/// [1]: https://www.rfc-editor.org/rfc/rfc6901#section-5
final _testCases = <(String, Object?)>[
  ('', _testDocument),
  ('/foo', <Object?>['bar', 'baz']),
  ('/foo/0', 'bar'),
  ('/', 0),
  ('/a~1b', 1),
  ('/c%d', 2),
  ('/e^f', 3),
  ('/g|h', 4),
  ('/i\\j', 5),
  ('/k"l', 6),
  ('/ ', 7),
  ('/m~0n', 8),
];

void main() {
  group('JsonPointer', () {
    for (final (pointer, result) in _testCases) {
      group('"$pointer"', () {
        test('fromString', () {
          JsonPointer.fromString(pointer);
        });

        test('resolveValue', () {
          final p = JsonPointer.fromString(pointer);
          final v = p.resolveValue(_testDocument);
          expect(deepJsonEquality.equals(result, v), isTrue);
        });

        test('operator==', () {
          final p = JsonPointer.fromString(pointer);
          expect(JsonPointer.fromString(pointer), equals(p));
        });

        test('hashCode', () {
          final p = JsonPointer.fromString(pointer);
          expect(JsonPointer.fromString(pointer).hashCode, equals(p.hashCode));
        });

        test('toFragment + fromFragment', () {
          final p1 = JsonPointer.fromString(pointer);
          final p2 = JsonPointer.fromFragment(p1.toFragment());
          expect(p2, equals(p1));
        });
      });
    }
  });
}
