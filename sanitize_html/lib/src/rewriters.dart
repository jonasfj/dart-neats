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

/// # UNTRUSTED: the built-in attribute rewriters, see `HtmlRewriter`.
library;

import 'html_rewriter.dart';
import 'html_token_sink.dart';
import 'html_writer.dart' show isVoidElement;

/// See `HtmlRewriter.attributes`.
HtmlRewriter rewriteAttributes(
  String tagName,
  void Function(Map<String, String> attributes) rewrite,
) =>
    HtmlRewriter((next) => _RewriteAttributes(tagName, rewrite, next));

/// See `HtmlRewriter.addLinkRel`.
HtmlRewriter addLinkRel(List<String> Function(String href) rel) =>
    rewriteAttributes('a', (attributes) {
      final href = attributes['href'];
      if (href == null) {
        return;
      }
      final added = rel(href);
      if (added.isEmpty) {
        return;
      }
      final tokens = (attributes['rel'] ?? '').split(' ')
        ..removeWhere((t) => t.isEmpty);
      for (final token in added) {
        if (!tokens.contains(token)) {
          tokens.add(token);
        }
      }
      attributes['rel'] = tokens.join(' ');
    });

/// See `HtmlRewriter.prefixIds`.
HtmlRewriter prefixIds(String prefix) =>
    HtmlRewriter((next) => _PrefixIds(prefix, next));

/// See `HtmlRewriter.keepTokens`.
HtmlRewriter keepTokens(String attribute, bool Function(String token) where) =>
    HtmlRewriter((next) => _KeepTokens(attribute, where, next));

final class _PrefixIds extends HtmlTokenSink {
  final String _prefix;
  final HtmlTokenSink _next;

  _PrefixIds(this._prefix, this._next);

  @override
  void text(String source, int start, int end) =>
      _next.text(source, start, end);

  @override
  void startTag(String name, Map<String, String> attributes) {
    if (attributes.isEmpty) {
      _next.startTag(name, attributes);
      return;
    }
    final id = attributes['id'];
    if (id != null && !id.startsWith(_prefix)) {
      attributes['id'] = '$_prefix$id';
    }
    final href = attributes['href'];
    if (href != null &&
        href.length > 1 &&
        href.startsWith('#') &&
        !href.startsWith(_prefix, 1)) {
      attributes['href'] = '#$_prefix${href.substring(1)}';
    }
    _next.startTag(name, attributes);
  }

  @override
  void endTag(String name) => _next.endTag(name);
}

final class _KeepTokens extends HtmlTokenSink {
  final String _attribute;
  final bool Function(String) _where;
  final HtmlTokenSink _next;

  _KeepTokens(this._attribute, this._where, this._next);

  @override
  void text(String source, int start, int end) =>
      _next.text(source, start, end);

  @override
  void startTag(String name, Map<String, String> attributes) {
    final value = attributes[_attribute];
    if (value != null) {
      final kept = value
          .split(_asciiWhitespace)
          .where((t) => t.isNotEmpty && _where(t))
          .join(' ');
      if (kept.isEmpty) {
        attributes.remove(_attribute);
      } else {
        attributes[_attribute] = kept;
      }
    }
    _next.startTag(name, attributes);
  }

  @override
  void endTag(String name) => _next.endTag(name);
}

final _asciiWhitespace = RegExp(r'[ \t\n\f\r]+');

/// See `HtmlRewriter.dropElements`.
HtmlRewriter dropElements(Set<String> names) =>
    HtmlRewriter((next) => _DropElements(names, next));

/// Drops named elements with their content, counting same-name nesting so
/// that `<x><x></x>still dropped</x>` drops the whole subtree.
final class _DropElements extends HtmlTokenSink {
  final Set<String> _names;
  final HtmlTokenSink _next;
  String? _droppedName;
  int _droppedDepth = 0;

  _DropElements(this._names, this._next);

  @override
  void text(String source, int start, int end) {
    if (_droppedDepth > 0) {
      return;
    }
    _next.text(source, start, end);
  }

  @override
  void startTag(String name, Map<String, String> attributes) {
    if (_droppedDepth > 0) {
      if (name == _droppedName) {
        _droppedDepth++;
      }
      return;
    }
    if (_names.contains(name)) {
      if (!isVoidElement(name)) {
        _droppedName = name;
        _droppedDepth = 1;
      }
      return;
    }
    _next.startTag(name, attributes);
  }

  @override
  void endTag(String name) {
    if (_droppedDepth > 0) {
      if (name == _droppedName) {
        _droppedDepth--;
      }
      return;
    }
    _next.endTag(name);
  }
}

final class _RewriteAttributes extends HtmlTokenSink {
  final String _tagName;
  final void Function(Map<String, String>) _rewrite;
  final HtmlTokenSink _next;

  _RewriteAttributes(this._tagName, this._rewrite, this._next);

  @override
  void text(String source, int start, int end) =>
      _next.text(source, start, end);

  @override
  void startTag(String name, Map<String, String> attributes) {
    if (name == _tagName) {
      // Tags without attributes may carry a shared const map.
      if (attributes.isEmpty) {
        attributes = {};
      }
      _rewrite(attributes);
    }
    _next.startTag(name, attributes);
  }

  @override
  void endTag(String name) => _next.endTag(name);
}
