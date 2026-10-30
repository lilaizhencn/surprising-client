import 'package:flutter/material.dart';
import '../app_scope.dart';
import 'messages.g.dart';

/// Catalogs contain UI labels only. Arbitrary user content is never translated here.
String translateClientLabel(String source, String locale) {
  if (source.isEmpty) return source;
  final messages = clientMessageCatalogs[locale];
  if (messages == null) throw StateError('Unsupported client locale: $locale');
  final exact = messages[source];
  if (exact != null) return exact;
  if (clientSourceMessages.contains(source)) {
    throw StateError('Missing client translation: $locale / $source');
  }
  if (source.length <= 2048) {
    for (final template in _templates) {
      final match = template.expression.firstMatch(source);
      if (match == null) continue;
      var result = messages[template.source];
      if (result == null) {
        throw StateError(
          'Missing client template: $locale / ${template.source}',
        );
      }
      for (var index = 0; index < template.parameters; index++) {
        result = result!.replaceAll('{p$index}', match.group(index + 1)!);
      }
      return result!;
    }
  }
  // Dynamic data and identifiers are displayed exactly as supplied.
  return source;
}

final _templates = clientSourceMessages
    .where((source) => source.contains('{p0}'))
    .map(_LabelTemplate.new)
    .toList(growable: false);

class _LabelTemplate {
  _LabelTemplate(this.source) {
    final placeholders = RegExp(r'\{p\d+\}');
    var start = 0;
    final pattern = StringBuffer('^');
    for (final match in placeholders.allMatches(source)) {
      pattern.write(RegExp.escape(source.substring(start, match.start)));
      pattern.write('(.*?)');
      parameters++;
      start = match.end;
    }
    pattern.write(RegExp.escape(source.substring(start)));
    pattern.write(r'$');
    expression = RegExp(pattern.toString(), dotAll: true);
  }
  final String source;
  late final RegExp expression;
  int parameters = 0;
}

String clientLabel(BuildContext context, String source) {
  final state = AppScope.maybeOf(context);
  return state == null
      ? source
      : translateClientLabel(source, state.language.code);
}

/// A presentation boundary for translated UI labels; data-bearing Text stays a normal Text.
class LText extends StatelessWidget {
  const LText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.semanticsIdentifier,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });
  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel, semanticsIdentifier;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;
  @override
  Widget build(BuildContext context) => Text(
    clientLabel(context, data),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    textDirection: textDirection,
    locale: locale,
    softWrap: softWrap,
    overflow: overflow,
    textScaler: textScaler,
    maxLines: maxLines,
    semanticsLabel: semanticsLabel == null
        ? null
        : clientLabel(context, semanticsLabel!),
    semanticsIdentifier: semanticsIdentifier,
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    selectionColor: selectionColor,
  );
}
