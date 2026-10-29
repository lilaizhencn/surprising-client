import 'package:flutter/material.dart';
import '../models.dart';

/// Each palette has a distinct canvas and saturated accent; trading colors retain their meaning.
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
      0xFF090B0E,
      0xFF15171C,
      0xFF24262C,
      0xFF54401C,
      0xFFF8F4EA,
      0xFFC8C5BD,
      0xFF66615A,
      0xFFFFC247,
    ),
    ClientTheme.light => (
      0xFFCCD7EB,
      0xFFE7EEFA,
      0xFFD3DEF1,
      0xFFB1C5EB,
      0xFF101D36,
      0xFF364764,
      0xFF687D9F,
      0xFF1649AE,
    ),
    ClientTheme.ocean => (
      0xFF031823,
      0xFF092A3B,
      0xFF104358,
      0xFF105B76,
      0xFFE4F6FF,
      0xFFAFD5E4,
      0xFF42768A,
      0xFF24C6F0,
    ),
    ClientTheme.forest => (
      0xFF061D14,
      0xFF103725,
      0xFF1C5036,
      0xFF256340,
      0xFFEDF9EE,
      0xFFB5DCC0,
      0xFF4D8660,
      0xFF43D983,
    ),
    ClientTheme.dusk => (
      0xFF180B29,
      0xFF2B153F,
      0xFF43225B,
      0xFF5C2F7A,
      0xFFFAEDFF,
      0xFFD6B9EA,
      0xFF88629F,
      0xFFB660FF,
    ),
    ClientTheme.sand => (
      0xFFD8B181,
      0xFFEBCDA6,
      0xFFDAB58A,
      0xFFC99660,
      0xFF2D1B0C,
      0xFF5B3C23,
      0xFF9D7045,
      0xFF743008,
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
    secondary: switch (theme) {
      ClientTheme.dark => const Color(0xFF79A7FF),
      ClientTheme.light => const Color(0xFF7132A4),
      ClientTheme.ocean => const Color(0xFF69AAFF),
      ClientTheme.forest => const Color(0xFFE5CA61),
      ClientTheme.dusk => const Color(0xFFFFB76B),
      ClientTheme.sand => const Color(0xFF465F2B),
    },
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
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: colors.primaryContainer,
      selectedIconTheme: IconThemeData(color: colors.primary),
      unselectedIconTheme: IconThemeData(color: colors.onSurfaceVariant),
      selectedLabelTextStyle: TextStyle(
        color: colors.primary,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(color: colors.onSurfaceVariant),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHighest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
