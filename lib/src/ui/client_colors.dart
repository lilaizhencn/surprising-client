import 'package:material_ui/material_ui.dart';

abstract final class ClientColors {
  static const foreground = Color(0xFFF4F6FF);
  static const muted = Color(0xFFB3BBE0);
  static const background = Color(0xFF05060F);
  static const surface = Color(0xFF0A0D1A);
  static const surfaceRaised = Color(0xFF101426);
  static const border = Color(0xFF283154);
  static const primary = Color(0xFF00E5FF);
  static const secondary = Color(0xFF7C4DFF);
  static const positive = Color(0xFF00E699);
  static const negative = Color(0xFFFF4D6D);
  static const warning = Color(0xFFFFB800);
  static Color warningFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? warning
      : const Color(0xFF895000);
}
