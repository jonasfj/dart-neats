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

import 'dart:math';

import 'package:collection/collection.dart';
import 'package:jsv/jsonpointer.dart';

import 'equality.dart';
import 'formats.dart';

///
sealed class Issue {}

base class CustomIssue extends Issue {}

// TODO: Remove all usages of [UnknownIssue]
final class UnknownIssue extends Issue {}

/// Types of JSON values.
enum JsonType {
  array,
  boolean,
  integer,
  nullValue,
  number,
  object,
  string,
}

/// Validator for a JSON value / structure.
///
/// When implementing a custom [Vocabulary] the `apply` function must create
/// a custom [Validator] instance.
///
/// Subclasses of [Validator] should **NEVER** have other public methods than
/// those specified in [Validator]. This may cause conflicts with future
/// iterations of this APIs.
abstract base class Validator {
  Iterable<Issue> validate(Object? value);
  bool isValid(Object? value) => validate(value).isEmpty;
}

final class JsonSchema extends Validator {
  final Uri _id;
  Map<String, Object?> _annotations = {};
  Set<Validator> _validators = {};
  bool _isTrue = false;
  bool _isFalse = false;
  JsonSchema? _ref;
  Set<JsonSchema>? _allOf;
  Set<JsonSchema>? _anyOf;
  Set<JsonSchema>? _oneOf;
  JsonSchema? _ifSchema;
  JsonSchema? _thenSchema;
  JsonSchema? _elseSchema;
  JsonSchema? _not;
  Map<String, JsonSchema> _properties = {};
  Map<RegExp, JsonSchema> _patternProperties = {};
  JsonSchema? _additionalProperties;
  Map<String, JsonSchema> _dependentSchemas = {};
  JsonSchema? _propertyNames;
  JsonSchema? _items;
  List<JsonSchema> _prefixItems = [];
  JsonSchema? _contains;
  Set<JsonType> _type = {...JsonType.values};

  /// Set of allowed values, must always be an [EqualitySet] using
  /// [deepJsonEquality] as equality.
  EqualitySet<Object?>? _enumValues;
  RegExp? _pattern;
  int? _minLength;
  int? _maxLength;
  String? _format;
  FormatValidator? _formatValidator;
  double? _exclusiveMaximum;
  double? _multipleOf;
  double? _exclusiveMinimum;
  double? _maximum;
  double? _minimum;
  Map<String, Set<String>> _dependentRequired = {};
  int? _maxProperties;
  int? _minProperties;
  Set<String> _required = {};
  int? _maxItems;
  int? _minItems;
  int? _maxContains;
  int? _minContains;
  bool _uniqueItems = false;

  JsonSchema._(this._id);

  // --- getters --- //

  Uri get id => _id;
  Map<String, Object?> get annotations => UnmodifiableMapView(_annotations);
  Set<Validator> get validators => UnmodifiableSetView(_validators);
  bool get isTrue => _isTrue;
  bool get isFalse => _isFalse;
  JsonSchema? get ref => _ref;
  Set<JsonSchema>? get allOf {
    final allOf = _allOf;
    return allOf != null ? UnmodifiableSetView(allOf) : null;
  }

  Set<JsonSchema>? get anyOf {
    final anyOf = _anyOf;
    return anyOf != null ? UnmodifiableSetView(anyOf) : null;
  }

  Set<JsonSchema>? get oneOf {
    final oneOf = _oneOf;
    return oneOf != null ? UnmodifiableSetView(oneOf) : null;
  }

  JsonSchema? get ifSchema => _ifSchema;
  JsonSchema? get thenSchema => _thenSchema;
  JsonSchema? get elseSchema => _elseSchema;
  JsonSchema? get not => _not;
  Map<String, JsonSchema> get properties => UnmodifiableMapView(_properties);
  Map<RegExp, JsonSchema> get patternProperties =>
      UnmodifiableMapView(_patternProperties);
  JsonSchema? get additionalProperties => _additionalProperties;
  Map<String, JsonSchema> get dependentSchemas =>
      UnmodifiableMapView(_dependentSchemas);
  JsonSchema? get propertyNames => _propertyNames;
  JsonSchema? get items => _items;
  List<JsonSchema> get prefixItems => UnmodifiableListView(_prefixItems);
  JsonSchema? get contains => _contains;
  Set<JsonType> get type => UnmodifiableSetView(_type);
  Set<Object?>? get enumValues {
    final ev = _enumValues;
    return ev != null ? UnmodifiableSetView(ev) : null;
  }

  RegExp? get pattern => _pattern;
  int? get minLength => _minLength;
  int? get maxLength => _maxLength;
  String? get format => _format;
  double? get exclusiveMaximum => _exclusiveMaximum;
  double? get multipleOf => _multipleOf;
  double? get exclusiveMinimum => _exclusiveMinimum;
  double? get maximum => _maximum;
  double? get minimum => _minimum;
  Map<String, Set<String>> get dependentRequired =>
      UnmodifiableMapView(_dependentRequired);
  int? get maxProperties => _maxProperties;
  int? get minProperties => _minProperties;
  Set<String> get required => UnmodifiableSetView(_required);
  int? get maxItems => _maxItems;
  int? get minItems => _minItems;
  int? get maxContains => _maxContains;
  int? get minContains => _minContains;
  bool get uniqueItems => _uniqueItems;

  @override
  Iterable<Issue> validate(Object? value) sync* {
    if (isTrue) {
      // pass
    }
    if (isFalse) {
      yield UnknownIssue();
    }

    // allOf, anyOf, oneOf
    if (_allOf case Set<JsonSchema> allOf) {
      for (final s in allOf) {
        yield* s.validate(value);
      }
    }
    if (_anyOf case Set<JsonSchema> anyOf) {
      if (anyOf.none((s) => s.isValid(value))) {
        yield UnknownIssue();
      }
    }
    if (_oneOf case Set<JsonSchema> oneOf) {
      if (oneOf.where((s) => s.isValid(value)).length != 1) {
        yield UnknownIssue();
      }
    }

    // if, then, else
    if (_ifSchema case JsonSchema ifSchema) {
      if (ifSchema.isValid(value)) {
        if (_thenSchema case JsonSchema thenSchema) {
          yield* thenSchema.validate(value);
        }
      } else {
        if (_elseSchema case JsonSchema elseSchema) {
          yield* elseSchema.validate(value);
        }
      }
    }

    // not
    if (_not case JsonSchema not) {
      if (not.isValid(value)) {
        yield UnknownIssue();
      }
    }

    // enumValues
    if (_enumValues case EqualitySet<Object?> enumValues) {
      if (!enumValues.contains(value)) {
        yield UnknownIssue();
      }
    }

    // Validate object
    if (value is Map<String, Object?>) {
      // type
      if (!_type.contains(JsonType.object)) {
        yield UnknownIssue();
      }

      for (final MapEntry(key: property, value: val) in value.entries) {
        var evaluated = false;
        // properties
        if (_properties[property] case JsonSchema s) {
          evaluated = true;
          yield* s.validate(val);
        }
        // patternProperties
        for (final MapEntry(key: p, value: s) in _patternProperties.entries) {
          if (p.hasMatch(property)) {
            evaluated = true;
            yield* s.validate(val);
          }
        }

        // additionalProperties
        if (!evaluated) {
          if (_additionalProperties case JsonSchema s) {
            yield* s.validate(val);
          }
        }
      }

      // dependentSchemas
      for (final MapEntry(key: p, value: s) in _dependentSchemas.entries) {
        if (value.containsKey(p)) {
          yield* s.validate(value);
        }
      }

      // propertyNames
      if (_propertyNames case JsonSchema propertyNames) {
        for (final property in value.keys) {
          yield* propertyNames.validate(property);
        }
      }

      // dependentRequired
      for (final MapEntry(:key, value: required) in dependentRequired.entries) {
        if (value.containsKey(key)) {
          if (required.any((k) => !value.containsKey(k))) {
            yield UnknownIssue();
          }
        }
      }

      // minProperties
      if (_minProperties case int minProperties) {
        if (value.length < minProperties) {
          yield UnknownIssue();
        }
      }

      // maxProperties
      if (_maxProperties case int maxProperties) {
        if (value.length > maxProperties) {
          yield UnknownIssue();
        }
      }

      // required
      if (required.any((k) => !value.containsKey(k))) {
        yield UnknownIssue();
      }
    }

    // array
    if (value is List<Object?>) {
      // type
      if (!_type.contains(JsonType.array)) {
        yield UnknownIssue();
      }

      // prefixItems
      final length = value.length;
      final evaluatedPrefixItems = min(_prefixItems.length, length);
      for (var i = 0; i < evaluatedPrefixItems; i++) {
        yield* _prefixItems[i].validate(value[i]);
      }

      // items
      if (_items case JsonSchema items) {
        for (final val in value.skip(evaluatedPrefixItems)) {
          yield* items.validate(val);
        }
      }

      // minItems
      if (_minItems case int minItems) {
        if (length < minItems) {
          yield UnknownIssue();
        }
      }

      // maxItems
      if (_maxItems case int maxItems) {
        if (length > maxItems) {
          yield UnknownIssue();
        }
      }

      // contains
      if (_contains case JsonSchema contains) {
        final count = value.where((val) => contains.isValid(val)).length;
        // minContains
        if (_minContains case int minContains) {
          if (count < minContains) {
            yield UnknownIssue();
          }
        } else if (count == 0) {
          // contains
          yield UnknownIssue();
        }
        // maxContains
        if (_maxContains case int maxContains) {
          if (count > maxContains) {
            yield UnknownIssue();
          }
        }
      }

      // uniqueItems
      if (_uniqueItems) {
        final set = EqualitySet(deepJsonEquality);
        for (final val in value) {
          if (!set.add(val)) {
            yield UnknownIssue();
          }
        }
      }
    }

    // boolean
    if (value is bool) {
      // type
      if (!_type.contains(JsonType.boolean)) {
        yield UnknownIssue();
      }
    }

    // number
    if (value is num) {
      // type
      if (!_type.contains(JsonType.number)) {
        if (!_type.contains(JsonType.integer)) {
          yield UnknownIssue(); // value cannot be a number
        } else if (value.toInt() != value) {
          yield UnknownIssue(); // value must be an integer
        }
      }

      // multipleOf
      if (_multipleOf case double multipleOf) {
        // TODO: Consider doing something smarter, see:
        //       https://github.com/ajv-validator/ajv/issues/84
        final div = value / multipleOf;
        if (div.truncate() != div) {
          yield UnknownIssue();
        }
      }

      // exclusiveMinimum
      if (_exclusiveMinimum case double exclusiveMinimum) {
        if (value <= exclusiveMinimum) {
          yield UnknownIssue();
        }
      }

      // exclusiveMaximum
      if (_exclusiveMaximum case double exclusiveMaximum) {
        if (value >= exclusiveMaximum) {
          yield UnknownIssue();
        }
      }

      // minimum
      if (_minimum case double minimum) {
        if (value < minimum) {
          yield UnknownIssue();
        }
      }

      // maximum
      if (_maximum case double maximum) {
        if (value > maximum) {
          yield UnknownIssue();
        }
      }
    }

    // string
    if (value is String) {
      // type
      if (!_type.contains(JsonType.string)) {
        yield UnknownIssue();
      }

      // pattern
      if (_pattern case RegExp pattern) {
        if (!pattern.hasMatch(value)) {
          yield UnknownIssue();
        }
      }

      // minLength
      int? length;
      if (_minLength case int minLength) {
        length ??= value.runes.length;
        if (length < minLength) {
          yield UnknownIssue();
        }
      }

      // maxLength
      if (_maxLength case int maxLength) {
        length ??= value.runes.length;
        if (length > maxLength) {
          yield UnknownIssue();
        }
      }

      // format
      if (_formatValidator case FormatValidator v) {
        if (!v(value)) {
          yield UnknownIssue(); // format
        }
      }
    }

    // null
    if (value == null) {
      // type
      if (!_type.contains(JsonType.nullValue)) {
        yield UnknownIssue();
      }
    }

    // $ref
    if (_ref case JsonSchema ref) {
      yield* ref.validate(value);
    }

    // Custom validators
    for (final v in _validators) {
      yield* v.validate(value);
    }
  }
}

bool _containsDirectApplicator(JsonSchema subtree, JsonSchema needle) {
  bool containsNeedle(JsonSchema s) {
    if (s == needle) return true;

    final ref = s.ref;
    if (ref != null && containsNeedle(ref)) return true;

    if (s._anyOf?.any(containsNeedle) ?? false) return true;
    if (s._allOf?.any(containsNeedle) ?? false) return true;
    if (s._oneOf?.any(containsNeedle) ?? false) return true;

    final ifSchema = s._ifSchema;
    if (ifSchema != null && containsNeedle(ifSchema)) return true;

    final thenSchema = s._thenSchema;
    if (thenSchema != null && containsNeedle(thenSchema)) return true;

    final elseSchema = s._elseSchema;
    if (elseSchema != null && containsNeedle(elseSchema)) return true;

    final not = s._not;
    if (not != null && containsNeedle(not)) return true;

    return false;
  }

  return containsNeedle(subtree);
}

final class SchemaContext {
  /// [Uri] for the root-schema that contains [schema].
  final Uri baseUri;

  /// Path to [schema] within the root-schema referenced by [baseUri].
  final JsonPointer path;

  /// Schema a validator should be created for.
  final Map<String, Object?> schema;

  final JsonSchema Function(Iterable<String>) _subschema;

  /// [id] if [schema].
  ///
  /// This is [baseUri] with [path] as a JSON pointer in the fragment.
  Uri get id => baseUri.replace(fragment: path.toFragment());

  /// Get validator for subschema at [path] under [schema].
  JsonSchema subschema(Iterable<String> path) => _subschema(path);

  SchemaContext._(this.baseUri, this.path, this.schema, this._subschema);
}

/// A custom [Vocabulary] enables [JSV] to validate custom keywords.
final class Vocabulary {
  final Set<String> _keywords;
  final Validator Function(SchemaContext ctx) _apply;

  /// Create a custom [Vocabulary] for validation of custom [keywords].
  ///
  /// The custom keywords understood by this [Vocabulary] must be given as
  /// [keywords]. [JSV] will use the list of keywords to forbid unknown
  /// keywords.
  ///
  /// The [apply] function must produce a [Validator] for a given schema.
  /// The schema given to [apply] is represented by an instance of
  /// [SchemaContext] allowing additional parameters to be passed along.
  Vocabulary({
    required Iterable<String> keywords,
    required Validator Function(SchemaContext ctx) apply,
  })  : _keywords = UnmodifiableSetView({...keywords}),
        _apply = apply;
}

/// A function that can validate a `format`.
typedef FormatValidator = bool Function(String value);

// TODO: Rename this SchemaCollection
final class JSV {
  static const _coreKeywords = {
    r'$schema',
    r'$id',
    r'$ref',
    r'$defs',
    r'$comment',
    r'$vocabulary',
    // Unsupported at this point:
    //r'$dynamicRef',
    //r'$dynamicAnchor',
    //r'$anchor',
  };

  static const _applicatorKeywords = {
    'allOf',
    'anyOf',
    'oneOf',
    'then',
    'if',
    'else',
    'not',
    'properties',
    'additionalProperties',
    'patternProperties',
    'dependentSchemas',
    'propertyNames',
    'items',
    'prefixItems',
    'contains',
  };

  static const _validatorKeywords = {
    'type',
    'enum',
    'const',
    'pattern',
    'minLength',
    'maxLength',
    'exclusiveMaximum',
    'multipleOf',
    'exclusiveMinimum',
    'maximum',
    'minimum',
    'dependentRequired',
    'maxProperties',
    'minProperties',
    'required',
    'maxItems',
    'minItems',
    'maxContains',
    'minContains',
    'uniqueItems',
  };

  // TODO: Consider allowing basic meta-data annotations:
  //       default, title, descriptions, readOnly, writeOnly, examples, deprecated
  //       https://json-schema.org/draft/2020-12/json-schema-validation#name-a-vocabulary-for-basic-meta

  static const _formatValidators = {
    'date-time': validateDateTime,
    'date': validateDate,
    'time': validateTime,
    'duration': validateDuration,
    'email': validateEmail,
    'idn-email': validateIdnEmail,
    'hostname': validateHostname,
    'idn-hostname': validateIdnHostname,
    'ipv4': validateIpv4,
    'ipv6': validateIpv6,
    'uri': validateUri,
    'uri-reference': validateUriReference,
    'iri': validateIri,
    'iri-reference': validateIriReference,
    'uuid': validateUuid,
    'uri-template': validateUriTemplate,
    'json-pointer': validateJsonPointer,
    'relative-json-pointer': validateRelativeJsonPointer,
    'regex': validateRegex,
  };

  final bool _allowUnknownKeywords;
  final Set<String> _annotationKeywords;
  final List<Vocabulary> _vocabularies;
  final Set<String> _keywords;
  final Map<String, FormatValidator> _formats;
  final Map<Uri, Map<String, Object?>> _store = {};
  final Map<Uri, JsonSchema> _schemas = {};

  /// Throws [FormatException] when loading schemas containing properties with
  /// no effect.
  ///
  /// A property that has no effect should generally not be included in a
  /// schema. This is indicative of a bug in the schema. However, it can be
  /// necessary for compatibility with schemas that contain unsupported
  /// features, or simply poorly written schemas.
  ///
  /// Examples of properties with no effect includes:
  ///  * Unknown properties,
  ///  * `then` or `else` when `if` is not specified.
  ///  * `multipleOf` if `type` doesn't allow `'number'`.
  final bool _strict;

  JSV({
    Iterable<Vocabulary> vocabularies = const [],
    Iterable<String> annotationKeywords = const [],
    bool allowUnknownKeywords = false,
    Map<String, FormatValidator> formats = const {},
    bool strict = true,
  })  : _strict = strict,
        _vocabularies = UnmodifiableListView([...vocabularies]),
        _keywords = UnmodifiableSetView({
          ..._coreKeywords,
          ..._applicatorKeywords,
          ..._validatorKeywords,
          ...annotationKeywords,
          ...vocabularies.expand((v) => v._keywords),
        }),
        _allowUnknownKeywords = allowUnknownKeywords,
        _annotationKeywords = UnmodifiableSetView({...annotationKeywords}),
        _formats = UnmodifiableMapView({
          ..._formatValidators,
          ...formats,
        });

  Uri addSchema(Object? schema) {
    if (schema is! Map<String, Object?>) {
      throw FormatException('schema must be a map');
    }
    final id_ = schema['\$id'];
    if (id_ is! String) {
      throw FormatException('\$id must be a string');
    }
    var id = Uri.tryParse(id_);
    if (id == null) {
      throw FormatException('\$id must be a valid URI');
    }
    if (id.fragment.isNotEmpty) {
      throw FormatException('\$id must not have fragment');
    }
    // Normalize by removing any empty fragment!
    id = id.removeFragment().normalizePath();
    if (_store.containsKey(id)) {
      throw StateError('\$id property must be unique');
    }
    _store[id] = schema;

    return id;
  }

  JsonSchema getSchema(Uri id) {
    // Normalize the id
    if (id.fragment.isEmpty) {
      id = id.removeFragment();
    }
    id = id.normalizePath();

    // Fast path lookup, if validator already exist
    final v = _schemas[id];
    if (v != null) {
      return v;
    }

    return _buildSchema(id, id.removeFragment(), id.pointer);
  }

  /// Create a validator for [id], with [baseUri] and [p] parsed from [id].
  JsonSchema _buildSchema(Uri id, Uri baseUri, JsonPointer p) {
    // Never create a validator that already exists in cache.
    {
      final schema = _schemas[id];
      if (schema != null) {
        return schema;
      }
    }

    final root = _store[baseUri];
    if (root == null) {
      throw FormatException('Root schema for "$id" could not be found');
    }
    final Object? schema;
    try {
      schema = p.resolveValue(root);
    } on JsonPointerResolutionException {
      throw FormatException(
        'Fragment reference for "$id" could not be resolved',
      );
    }
    if (schema == true) {
      return _schemas[id] = JsonSchema._(id).._isTrue = true;
    }
    if (schema == false) {
      return _schemas[id] = JsonSchema._(id).._isFalse = true;
    }
    if (schema is! Map<String, Object?>) {
      throw FormatException('Schema must be Map<String,Object?> or boolean');
    }

    if (!_allowUnknownKeywords && !_keywords.containsAll(schema.keys)) {
      final unsupported = schema.keys.whereNot(_keywords.contains).join(', ');
      throw FormatException('Unsupported keywords: $unsupported');
    }

    // INVARIANT: We always assign to _schemas[id] before we allow any
    //            recursive calls to _buildSchema. Otherwise, cycles could
    //            cause infinitely recursion.
    final s = _schemas[id] = JsonSchema._(id);
    try {
      final ctx = SchemaContext._(baseUri, p, schema, (path) {
        final sp = p.extend(path);
        final sid = baseUri.replace(fragment: sp.toFragment());
        return _buildSchema(sid, baseUri, sp);
      });

      _populateSchemaFromJson(s, ctx);
      s._validators = _vocabularies.map((v) => v._apply(ctx)).toSet();
      s._annotations = Map.fromEntries(
        schema.entries.where((e) => _annotationKeywords.contains(e.key)),
      );

      final ref = schema['\$ref'];
      if (ref != null) {
        if (ref is! String) {
          throw FormatException('\$ref must be a string');
        }
        var rid = baseUri.resolve(ref);
        if (rid.fragment.isEmpty) {
          rid = rid.removeFragment();
        }
        final rs = _buildSchema(rid, rid.removeFragment(), rid.pointer);
        if (_containsDirectApplicator(rs, s)) {
          throw FormatException(
            'Direct applicators may not have cycles',
          );
        }
        s._ref = rs;
      }
      return s;
    } catch (e) {
      _schemas.remove(id);
      rethrow;
    }
  }

  void _populateSchemaFromJson(JsonSchema s, SchemaContext ctx) {
    final schema = ctx.schema;

    // Applicators
    s._allOf = ctx.optionalSchemaArray('allOf')?.toSet();
    s._anyOf = ctx.optionalSchemaArray('anyOf')?.toSet();
    s._oneOf = ctx.optionalSchemaArray('oneOf')?.toSet();

    // Conditional applicators
    s._ifSchema = ctx.optionalSchema('if');
    if (s._ifSchema != null) {
      s._thenSchema = ctx.optionalSchema('then');
      s._elseSchema = ctx.optionalSchema('else');
    } else if (_strict) {
      if (schema.containsKey('then')) {
        throw FormatException(
            '"then" without "if" is not allowed in strict-mode');
      }
      if (schema.containsKey('else')) {
        throw FormatException(
            '"else" without "if" is not allowed in strict-mode');
      }
    }

    // Not applicator
    s._not = ctx.optionalSchema('not');

    // Type validator
    if (schema.containsKey('type')) {
      var typ = schema['type'];
      if (typ is String) {
        typ = <Object?>[typ];
      }
      if (typ is! List<Object?>) {
        throw FormatException('"type" must be a String or List<Object?>');
      }
      s._type = {
        ...typ.map((t) => switch (t) {
              'array' => JsonType.array,
              'boolean' => JsonType.boolean,
              'integer' => JsonType.integer,
              'null' => JsonType.nullValue,
              'number' => JsonType.number,
              'object' => JsonType.object,
              'string' => JsonType.string,
              _ => throw FormatException('"type" does not support "$t"')
            }),
      };
    }
    // TODO: Sanity check that validators are allowed for given type
    //       Example: patternProperties make no sense if type doesn't allow for
    //                object, we should forbid these in strict mode.

    // Object applicators
    s._properties = ctx.schemaMapOptionallyEmpty('properties', (k) => k);
    s._patternProperties = ctx.schemaMapOptionallyEmpty(
      'patternProperties',
      RegExp.new,
    );
    s._additionalProperties = ctx.optionalSchema('additionalProperties');
    s._dependentSchemas = ctx.schemaMapOptionallyEmpty(
      'dependentSchemas',
      (k) => k,
    );
    s._propertyNames = ctx.optionalSchema('propertyNames');

    // Array applicators
    s._items = ctx.optionalSchema('items');
    s._prefixItems =
        (ctx.optionalSchemaArray('prefixItems') ?? []).toList(growable: false);
    s._contains = ctx.optionalSchema('contains');

    // Enum and const
    if (schema.containsKey('enum')) {
      final ev = schema['enum'];
      if (ev is! List<Object?>) {
        throw FormatException('"enum" must be List<Object?>');
      }
      final enumValues = s._enumValues = EqualitySet.from(deepJsonEquality, ev);

      if (schema.containsKey('const')) {
        final c = schema['const'];
        if (!enumValues.contains(c)) {
          s._isFalse = true;
          s._enumValues = EqualitySet.from(deepJsonEquality, []);
        } else {
          s._enumValues = EqualitySet.from(deepJsonEquality, [c]);
        }
      }
    } else if (schema.containsKey('const')) {
      final c = schema['const'];
      s._enumValues = EqualitySet.from(deepJsonEquality, [c]);
    }

    // String validators
    if (schema.containsKey('pattern')) {
      final p = schema['pattern'];
      if (p is! String) {
        throw FormatException('"pattern" must be a String');
      }
      s._pattern = RegExp(p);
    }
    s._minLength = ctx.optionalInteger('minLength');
    s._maxLength = ctx.optionalInteger('maxLength');
    if (ctx.optionalString('format') case String format) {
      s._format = format;
      s._formatValidator = _formats[format];
      if (s._formatValidator == null) {
        throw FormatException('Unknown format "$format"');
      }
    }

    // Number validators
    s._exclusiveMaximum = ctx.optionalNumber('exclusiveMaximum');
    s._multipleOf = ctx.optionalNumber('multipleOf');
    s._exclusiveMinimum = ctx.optionalNumber('exclusiveMinimum');
    s._maximum = ctx.optionalNumber('maximum');
    s._minimum = ctx.optionalNumber('minimum');

    // Object validators
    if (schema.containsKey('dependentRequired')) {
      final dr = schema['dependentRequired'];
      if (dr is! Map<String, Object?>) {
        throw FormatException(
          '"dependentRequired" must be Map<String,Object?>',
        );
      }
      s._dependentRequired = dr.map((key, value) {
        if (value is! List<Object?>) {
          throw FormatException(
            'values in "dependentRequired" must be List<Object?>',
          );
        }
        if (value.any((o) => o is! String)) {
          throw FormatException(
            'entries in values in "dependentRequired" must be String',
          );
        }
        return MapEntry(key, {...value.whereType<String>()});
      });
    }
    s._maxProperties = ctx.optionalInteger('maxProperties');
    s._minProperties = ctx.optionalInteger('minProperties');
    if (schema.containsKey('required')) {
      final r = schema['required'];
      if (r is! List<Object?>) {
        throw FormatException('"required" must be a List<Object?>');
      }
      if (r.any((e) => e is! String)) {
        throw FormatException('entries in "required" must be String');
      }
      s._required = {...r.whereType<String>()};
    }

    // Array validators
    s._maxItems = ctx.optionalInteger('maxItems');
    s._minItems = ctx.optionalInteger('minItems');
    s._maxContains = ctx.optionalInteger('maxContains');
    s._minContains = ctx.optionalInteger('minContains');
    if (schema.containsKey('uniqueItems')) {
      final ui = schema['uniqueItems'];
      if (ui is! bool) {
        throw FormatException('"uniqueItems" must be a boolean');
      }
      s._uniqueItems = ui;
    }
  }
}

extension on SchemaContext {
  Iterable<JsonSchema>? optionalSchemaArray(String key) {
    if (!schema.containsKey(key)) {
      return null;
    }
    final array = schema[key];
    if (array is! List<Object?>) {
      throw FormatException('"$key" must be List<Object?>');
    }
    return array.mapIndexed((index, _) => subschema([key, '$index']));
  }

  JsonSchema? optionalSchema(String key) {
    if (!schema.containsKey(key)) {
      return null;
    }
    return subschema([key]);
  }

  Map<T, JsonSchema> schemaMapOptionallyEmpty<T>(
    String key,
    T Function(String) eachKey,
  ) {
    if (!schema.containsKey(key)) {
      return {};
    }
    final map = schema[key];
    if (map is! Map<String, Object?>) {
      throw FormatException('"$key" must be Map<String,Object?>');
    }
    return map.map((sk, value) => MapEntry(eachKey(sk), subschema([key, sk])));
  }

  String? optionalString(String key) {
    if (!schema.containsKey(key)) {
      return null;
    }
    final s = schema[key];
    if (s is! String) {
      throw FormatException('"$key" must be a string');
    }
    return s;
  }

  int? optionalInteger(String key) {
    if (!schema.containsKey(key)) {
      return null;
    }
    final i = schema[key];
    if (i is! num || i.toInt() != i) {
      throw FormatException('"$key" must be an integer');
    }
    return i.toInt();
  }

  double? optionalNumber(String key) {
    if (!schema.containsKey(key)) {
      return null;
    }
    final d = schema[key];
    if (d is! num || d.toDouble() != d) {
      throw FormatException('"$key" must be a number');
    }
    return d.toDouble();
  }
}

extension on Uri {
  JsonPointer get pointer => JsonPointer.fromFragment(fragment);
}
