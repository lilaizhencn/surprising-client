import '../models.dart';

class LegalDocument {
  const LegalDocument({
    required this.revisionId,
    required this.type,
    required this.locale,
    required this.title,
    required this.bodyHtml,
    required this.revisionLabel,
    required this.registrationRequired,
  });
  factory LegalDocument.fromJson(Map<String, dynamic> value) {
    final id = parseInt64(value['revisionId']);
    final title = requireString(value['title'], 'title');
    final html = requireString(value['bodyHtml'], 'bodyHtml');
    final locale = requireString(value['locale'], 'locale');
    if (id == null ||
        id <= 0 ||
        title.isEmpty ||
        title.length > 160 ||
        html.isEmpty ||
        html.length > 64000 ||
        value['registrationRequired'] is! bool ||
        !ClientLanguage.values.any(
          (language) => language.contentLocale == locale,
        )) {
      throw const FormatException('协议内容不完整，请重新加载');
    }
    return LegalDocument(
      revisionId: id,
      type: requireString(value['type'], 'type'),
      locale: locale,
      title: title,
      bodyHtml: html,
      revisionLabel: requireString(value['revisionLabel'], 'revisionLabel'),
      registrationRequired: value['registrationRequired'] as bool,
    );
  }
  final int revisionId;
  final String type, locale, title, bodyHtml, revisionLabel;
  final bool registrationRequired;
}
