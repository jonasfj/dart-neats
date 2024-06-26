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

import 'dart:collection';
import 'fragment.dart';

// https://datatracker.ietf.org/doc/html/rfc6901
final class JsonPointer {
  final List<String> segments;

  static String escapeSegment(String escapedSegment) =>
      escapedSegment.replaceAll('~', '~0').replaceAll('/', '~1');

  static String unescapeSegment(String segment) =>
      segment.replaceAll('~1', '/').replaceAll('~0', '~');

  JsonPointer._(List<String> segments)
      : segments = UnmodifiableListView(segments);

  factory JsonPointer(Iterable<String> segments) {
    return JsonPointer._(List.from(segments, growable: false));
  }

  factory JsonPointer.fromString(String pointer) {
    if (pointer.isNotEmpty && !pointer.startsWith('/')) {
      throw FormatException('JSON pointers segments must start with slash /');
    }
    return JsonPointer._(
      pointer
          .split('/')
          .map(unescapeSegment)
          .skip(1) // starts with slash, so skip first segment
          .toList(growable: false),
    );
  }

  factory JsonPointer.fromFragment(String fragment) {
    return JsonPointer.fromString(decodeFragment(fragment));
  }

  JsonPointer get parent => JsonPointer._(
        List.from(segments.take(segments.length - 1), growable: false),
      );

  JsonPointer extend(Iterable<String> segments) => JsonPointer._(
        List.from(this.segments.followedBy(segments), growable: false),
      );

  @override
  bool operator ==(Object other) {
    if (other is! JsonPointer) {
      return false;
    }
    if (other.segments.length != segments.length) {
      return false;
    }
    for (var i = 0; i < segments.length; i++) {
      if (segments[i] != other.segments[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(segments);

  @override
  String toString() =>
      segments.isEmpty ? '' : '/' + segments.map(escapeSegment).join('/');

  String toFragment() => encodeFragment(toString());

  Object? resolveValue(Object? json) {
    var value = json;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (value is Map && value.containsKey(segment)) {
        value = value[segment];
        continue;
      }

      if (value is List && (segment == '0' || !segment.startsWith('0'))) {
        final index = int.tryParse(segment);
        if (index != null && index >= 0 && index < value.length) {
          value = value[index];
          continue;
        }
      }

      throw JsonPointerResolutionException._(this, i, json);
    }
    return value;
  }
}

final class JsonPointerResolutionException implements Exception {
  final Object? json;
  final int offset;
  final JsonPointer pointer;

  JsonPointerResolutionException._(this.pointer, this.offset, this.json);
}
