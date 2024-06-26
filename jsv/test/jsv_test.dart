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

import 'dart:convert';
import 'dart:io';
import 'package:jsv/jsv.dart';
import 'package:test/test.dart';

const _schemaTestSuite = 'third_party/json-schema-test-suite';
const _schemaTestFiles = '$_schemaTestSuite/tests';
const _schemaSpecifications = [
  'draft2020-12',
];

const _skippedFiles = [
  // Fix issues with id / ref
  'id.json', // TODO: Debug this!
  'ref.json', // TODO: Allow strict=false mode
  'unknownKeyword.json', // Try enabling this when id/ref works

  // Make remotes work
  'refRemote.json', // TODO: See 'additional assumptions' in README
  'defs.json', // TODO: Maybe, when test load from remotes/ folder

  // Figure out annotations / evaluated properties
  'unevaluatedProperties.json',
  'unevaluatedItems.json',

  // Support anchors and dynamicRef
  'anchor.json',
  'dynamicRef.json',

  // Implement support for 'format'
  'format.json', // TODO: Support format!

  // Consider figuring out later
  'vocabulary.json', // TODO: Consider handling meta-schemas
  'content.json', // TODO: Investigate what supporting this entails
  'boolean_schema.json', // TODO: Support true root schema
];

const _skippedCases = [
  // Enable when unevaluatedProperties has been fixed
  'collect annotations inside a \'not\', even if collection is disabled',
];

void main() {
  final cwd = Directory.current.uri;

  for (final spec in _schemaSpecifications) {
    final testFileFolder = cwd.resolve('$_schemaTestFiles/$spec');
    final testFiles = Directory.fromUri(testFileFolder).listSync();

    group(spec, () {
      for (final testFile in testFiles.whereType<File>()) {
        final testFilename = testFile.uri.pathSegments.last;
        group(testFilename, () {
          final testCases = jsonDecode(testFile.readAsStringSync());
          for (final testCase in testCases) {
            final description = testCase['description'];
            group(description + ':', () {
              final jsv = JSV(strict: false, allowUnknownKeywords: true);
              Uri? id;
              test('load schema', () {
                id = jsv.addSchema(<String, Object?>{
                  r'$id': 'http://localhost:0/target#',
                  ...testCase['schema'],
                });
              });

              for (final t in testCase['tests']) {
                test(t['description'], () {
                  if (id == null) {
                    markTestSkipped('failed to load schema');
                    return;
                  }
                  final result = jsv.getSchema(id!).isValid(t['data']);
                  expect(result, t['valid'], reason: '''
schema: ${JsonEncoder.withIndent('  ').convert(testCase['schema'])}
data: ${JsonEncoder.withIndent('  ').convert(t['data'])}
''');
                });
              }
            },
                skip: _skippedCases.contains(description) ||
                    _skippedFiles.contains(testFilename));
          }
        });
      }
    });
  }
}
