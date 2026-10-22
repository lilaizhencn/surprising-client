import 'package:flutter/material.dart';
import '../models.dart';
import 'client_colors.dart';

ThemeData buildClientTheme(ClientTheme theme) {
  final isLight = theme == ClientTheme.light;
  return ThemeData(
    brightness: isLight ? Brightness.light : Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: isLight
        ? const Color(0xFFFBF9FB)
        : ClientColors.background,
    colorScheme: isLight
        ? ColorScheme.light(
            primary: const Color(0xFF003EC7),
            onSurface: const Color(0xFF1B1C1E),
            onSurfaceVariant: const Color(0xFF434656),
            outlineVariant: const Color(0xFFE9E7EA),
            secondary: ClientColors.secondary,
            tertiary: const Color(0xFF006D3F),
            surface: Colors.white,
            surfaceContainerHighest: const Color(0xFFF5F3F6),
            error: const Color(0xFF9E0D22),
          )
        : const ColorScheme.dark(
            primary: ClientColors.primary,
            onPrimary: Color(0xFF111318),
            onSurface: ClientColors.foreground,
            onSurfaceVariant: ClientColors.muted,
            outlineVariant: ClientColors.border,
            secondary: ClientColors.secondary,
            tertiary: ClientColors.positive,
            surface: ClientColors.surface,
            surfaceContainerHighest: ClientColors.surfaceRaised,
            error: ClientColors.negative,
          ),
    canvasColor: isLight ? const Color(0xFFFBF9FB) : ClientColors.background,
    dividerColor: isLight ? const Color(0xFFD9DEE5) : ClientColors.border,
    textTheme: TextTheme(
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: isLight ? const Color(0xFF1B1C1E) : ClientColors.foreground,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: isLight ? const Color(0xFF1B1C1E) : ClientColors.foreground,
      ),
      bodyMedium: TextStyle(
        fontSize: 12,
        color: isLight ? const Color(0xFF1B1C1E) : ClientColors.foreground,
      ),
      labelMedium: TextStyle(
        fontSize: 11,
        color: isLight ? const Color(0xFF5F7482) : ClientColors.muted,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ClientColors.surface,
      contentTextStyle: TextStyle(color: ClientColors.foreground, fontSize: 13),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isLight ? Colors.white : ClientColors.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: ClientColors.border,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ClientColors.surface,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? ClientColors.foreground
              : ClientColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? ClientColors.warning
              : ClientColors.muted,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: isLight
          ? const Color(0xFFF5F3F6)
          : ClientColors.surfaceRaised,
      selectedColor: ClientColors.primary.withValues(alpha: .20),
      side: BorderSide(
        color: isLight ? const Color(0xFFC3C5D9) : ClientColors.border,
      ),
      labelStyle: TextStyle(
        color: isLight ? const Color(0xFF1B1C1E) : ClientColors.foreground,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
      secondaryLabelStyle: TextStyle(
        color: isLight ? const Color(0xFF1B1C1E) : ClientColors.foreground,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: isLight
            ? const Color(0xFFF5F3F6)
            : ClientColors.surfaceRaised,
        foregroundColor: isLight
            ? const Color(0xFF1B1C1E)
            : ClientColors.foreground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isLight ? const Color(0xFFC3C5D9) : ClientColors.border,
          ),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: isLight
            ? const Color(0xFF003EC7)
            : ClientColors.primary,
        foregroundColor: isLight ? Colors.white : ClientColors.background,
        disabledBackgroundColor: ClientColors.surfaceRaised,
        disabledForegroundColor: ClientColors.muted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: isLight
            ? const Color(0xFF1B1C1E)
            : ClientColors.foreground,
        side: BorderSide(
          color: isLight ? const Color(0xFFC3C5D9) : ClientColors.border,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
