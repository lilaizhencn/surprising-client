import 'package:flutter/material.dart';
import '../models.dart';

/// Palettes mirror the Web workspace; red/green continue to mean loss/gain.
ColorScheme clientColorScheme(ClientTheme theme) {
  final (
    canvas,
    surface,
    raised,
    active,
    ink,
    muted,
    border,
    primary,
  ) = switch (theme) {
    ClientTheme.dark => (
      0xFF111318,
      0xFF191C23,
      0xFF222630,
      0xFF24345D,
      0xFFF2F0F3,
      0xFFC6CAD6,
      0xFF3B4252,
      0xFF7C9AFF,
    ),
    ClientTheme.light => (
      0xFFF7F8FA,
      0xFFFFFFFF,
      0xFFF0F2F5,
      0xFFEAF0FF,
      0xFF182230,
      0xFF526071,
      0xFFD5DCE6,
      0xFF2859C5,
    ),
    ClientTheme.ocean => (
      0xFF081B29,
      0xFF102938,
      0xFF183747,
      0xFF214B60,
      0xFFE5F5FA,
      0xFFB4CBD6,
      0xFF365363,
      0xFF71D8EF,
    ),
    ClientTheme.forest => (
      0xFF0C1C18,
      0xFF142E26,
      0xFF1E3D32,
      0xFF285440,
      0xFFE7F4EB,
      0xFFB8CEBF,
      0xFF3E5A4B,
      0xFF83DDB6,
    ),
    ClientTheme.dusk => (
      0xFF1C1427,
      0xFF2A2039,
      0xFF382C4A,
      0xFF4A3762,
      0xFFF5EEFA,
      0xFFD0BEDC,
      0xFF59446B,
      0xFFC9A5FA,
    ),
    ClientTheme.sand => (
      0xFFF6EFE3,
      0xFFFFFAF2,
      0xFFEEE3D1,
      0xFFECD9B8,
      0xFF30271E,
      0xFF6B5945,
      0xFFCEBAA0,
      0xFF815019,
    ),
  };
  return ColorScheme.fromSeed(
    seedColor: Color(primary),
    brightness: theme.isLight ? Brightness.light : Brightness.dark,
  ).copyWith(
    primary: Color(primary),
    onPrimary: theme.isLight ? Colors.white : Color(canvas),
    primaryContainer: Color(active),
    onPrimaryContainer: Color(ink),
    secondary: Color(primary),
    secondaryContainer: Color(active),
    onSecondaryContainer: Color(ink),
    tertiary: Color(theme.isLight ? 0xFF006D3F : 0xFF55DF9A),
    error: Color(theme.isLight ? 0xFF9E0D22 : 0xFFFF7D86),
    surface: Color(surface),
    surfaceDim: Color(canvas),
    surfaceContainerLowest: Color(canvas),
    surfaceContainerLow: Color(surface),
    surfaceContainer: Color(raised),
    surfaceContainerHigh: Color(raised),
    surfaceContainerHighest: Color(raised),
    onSurface: Color(ink),
    onSurfaceVariant: Color(muted),
    outline: Color(border),
    outlineVariant: Color(border),
    inverseSurface: Color(ink),
    onInverseSurface: Color(canvas),
    surfaceTint: Colors.transparent,
  );
}

ThemeData buildClientTheme(ClientTheme theme) {
  final colors = clientColorScheme(theme);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  return ThemeData(
    useMaterial3: true,
    brightness: colors.brightness,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surfaceDim,
    canvasColor: colors.surfaceDim,
    dividerColor: colors.outlineVariant,
    textTheme: TextTheme(
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
      ),
      bodyMedium: TextStyle(fontSize: 12, color: colors.onSurface),
      labelMedium: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.inverseSurface,
      contentTextStyle: TextStyle(color: colors.onInverseSurface, fontSize: 13),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: colors.outline,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryContainer,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.onSurfaceVariant,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.surfaceContainerHighest,
      selectedColor: colors.primaryContainer,
      side: BorderSide(color: colors.outlineVariant),
      labelStyle: TextStyle(
        color: colors.onSurface,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
      secondaryLabelStyle: TextStyle(
        color: colors.onSurface,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
      shape: shape,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: colors.surfaceContainerHighest,
        foregroundColor: colors.onSurface,
        shape: shape,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        disabledBackgroundColor: colors.surfaceContainerHighest,
        disabledForegroundColor: colors.onSurfaceVariant,
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.onSurface,
        side: BorderSide(color: colors.outline),
        shape: shape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHighest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
