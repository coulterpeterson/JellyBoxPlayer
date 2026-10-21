import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:jplayer/src/core/enums/theme_color.dart';

/// The colours of the regular app interface for one [ThemeColor].
///
/// Every colour starts from the original JellyBox maroon palette and is turned
/// to the theme's hue, keeping its saturation and lightness, so each choice is
/// as calm as the original. Accents are only lightened as far as needed to
/// stay readable on the app's black background.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.accent,
    required this.onAccent,
    required this.panel,
    required this.chip,
    required this.surface,
    required this.indicator,
  });

  factory AppPalette.of(ThemeColor color) => _cache[color] ??= _build(color);

  static AppPalette? maybeOf(BuildContext context) =>
      Theme.of(context).extension<AppPalette>();

  /// Buttons, highlights and the background glow.
  final Color accent;

  /// Text and icons drawn on [accent].
  final Color onAccent;

  /// Bars, sheets and the side rail.
  final Color panel;

  /// Unselected chips.
  final Color chip;

  /// Dialogs and tooltips.
  final Color surface;

  /// The selected item behind the side rail's icons.
  final Color indicator;

  static final _cache = <ThemeColor, AppPalette>{};

  // The original palette, which ThemeColor.red reproduces exactly.
  static const _red = AppPalette(
    accent: Color(0xFFFD2F2F),
    onAccent: Colors.white,
    panel: Color(0xFF471F27),
    chip: Color(0xFF362A30),
    surface: Color(0xFF1C1518),
    indicator: Color(0xFF341010),
  );

  /// The hue of the original panel colour, which each palette turns to its
  /// theme's hue; the other dark colours keep their offset from it, and the
  /// accent takes the theme's hue exactly.
  static const _baseHue = 348.0;

  /// Contrast an accent must reach against black to be used as text.
  static const minAccentContrast = 4.5;

  /// Contrast an accent must reach against the palette's [panel].
  static const minPanelContrast = 3.0;

  /// Contrast text on an accent must reach; the original white on red sits
  /// just above this, so it's kept.
  static const minOnAccentContrast = 3.0;

  static AppPalette _build(ThemeColor color) {
    final hue = color.hue;
    if (color == ThemeColor.red) return _red;
    Color turn(Color original) {
      final hsl = HSLColor.fromColor(original);
      if (hue == null) return hsl.withSaturation(0).toColor();
      return hsl.withHue((hsl.hue - _baseHue + hue) % 360).toColor();
    }

    final panel = turn(_red.panel);
    final accent = _readable(
      hue == null
          ? const Color(0xFFF2F2F2)
          : HSLColor.fromColor(_red.accent).withHue(hue).toColor(),
      panel,
    );
    return AppPalette(
      accent: accent,
      onAccent: textOn(accent),
      panel: panel,
      chip: turn(_red.chip),
      surface: turn(_red.surface),
      indicator: turn(_red.indicator),
    );
  }

  /// Lightens [color] until it reads as text on black and stands out from
  /// [panel].
  static Color _readable(Color color, Color panel) {
    var hsl = HSLColor.fromColor(color);
    bool readable(Color c) =>
        contrast(c, Colors.black) >= minAccentContrast &&
        contrast(c, panel) >= minPanelContrast;
    while (!readable(hsl.toColor()) && hsl.lightness < 0.95) {
      hsl = hsl.withLightness(math.min(0.95, hsl.lightness + 0.01));
    }
    return hsl.toColor();
  }

  /// White, or black when white wouldn't read on [background].
  static Color textOn(Color background) =>
      contrast(Colors.white, background) >= minOnAccentContrast
      ? Colors.white
      : Colors.black;

  /// The WCAG contrast ratio between two colours, from 1 to 21.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  @override
  AppPalette copyWith({
    Color? accent,
    Color? onAccent,
    Color? panel,
    Color? chip,
    Color? surface,
    Color? indicator,
  }) => AppPalette(
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    panel: panel ?? this.panel,
    chip: chip ?? this.chip,
    surface: surface ?? this.surface,
    indicator: indicator ?? this.indicator,
  );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      chip: Color.lerp(chip, other.chip, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      indicator: Color.lerp(indicator, other.indicator, t)!,
    );
  }
}
