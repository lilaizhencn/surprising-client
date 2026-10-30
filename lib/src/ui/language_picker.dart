import 'package:flutter/material.dart';
import '../app_scope.dart';
import '../i18n/client_messages.dart';
import '../models.dart';

Future<void> showClientLanguagePicker(BuildContext context) {
  final state = AppScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * .8,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 8, 0),
              child: Row(
                children: [
                  const Expanded(child: LText('语言 / Language')),
                  IconButton(
                    tooltip: clientLabel(sheetContext, '关闭'),
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                children: [
                  for (final language in ClientLanguage.values)
                    Semantics(
                      identifier: 'client.language.option.${language.code}',
                      child: ListTile(
                        title: Text(language.label),
                        trailing: language == state.language
                            ? const Icon(Icons.check)
                            : null,
                        selected: language == state.language,
                        onTap: () {
                          state.selectLanguage(language);
                          Navigator.pop(sheetContext);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
