import 'package:flutter/material.dart';
import '../app_scope.dart';
import '../models.dart';
import 'client_theme.dart';

void showClientThemePicker(BuildContext context) {
  final state = AppScope.of(context);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '你的交易空间，你的色彩',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text('选择配色，自动保存在本机。涨跌仍使用红绿语义色。'),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final theme in ClientTheme.values)
                    SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: _ThemeOption(
                        theme: theme,
                        selected: theme == state.clientTheme,
                        onTap: () {
                          state.selectTheme(theme);
                          Navigator.pop(context);
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

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.theme,
    required this.selected,
    required this.onTap,
  });
  final ClientTheme theme;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = clientColorScheme(theme);
    return Semantics(
      selected: selected,
      button: true,
      label: theme.label,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : colors.outline,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 60,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surfaceDim,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(height: 5, color: colors.primary),
                            const SizedBox(height: 7),
                            Expanded(
                              child: ColoredBox(
                                color: colors.surfaceContainerHighest,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          CircleAvatar(
                            radius: 5,
                            backgroundColor: colors.primary,
                          ),
                          const SizedBox(height: 4),
                          CircleAvatar(
                            radius: 5,
                            backgroundColor: colors.tertiary,
                          ),
                          const SizedBox(height: 4),
                          CircleAvatar(
                            radius: 5,
                            backgroundColor: colors.error,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        theme.label,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_circle, color: colors.primary, size: 18),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
