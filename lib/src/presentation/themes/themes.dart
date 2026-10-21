import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:jplayer/resources/resources.dart';
import 'package:jplayer/src/core/enums/theme_color.dart';
import 'package:jplayer/src/presentation/themes/app_palette.dart';

export 'app_palette.dart';

abstract class Themes {
  /// Dark background for the changelog dialog/sheet, so it doesn't inherit the
  /// [BottomSheetThemeData] panel color used elsewhere in the app.
  static Color changelogSurfaceOf(BuildContext context) =>
      AppPalette.maybeOf(context)?.surface ??
      AppPalette.of(ThemeColor.red).surface;

  static const tooltipDelay = Duration(milliseconds: 350);

  static const tooltipPadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 6,
  );

  static const tooltipTextStyle = TextStyle(
    color: Colors.white,
    fontSize: 13,
    height: 1.2,
  );

  static BoxDecoration tooltipDecorationOf(BuildContext context) =>
      _tooltipDecoration(changelogSurfaceOf(context));

  static BoxDecoration _tooltipDecoration(Color color) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(6),
    boxShadow: const [
      BoxShadow(
        color: Colors.black54,
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ],
  );

  /// The original JellyBox look.
  static final red = of(ThemeColor.red);

  static final _themes = <ThemeColor, ThemeData>{};

  static ThemeData of(ThemeColor color) =>
      _themes[color] ??= _build(AppPalette.of(color));

  static ThemeData _build(AppPalette palette) => ThemeData(
    useMaterial3: true,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    brightness: Brightness.dark,
    fontFamily: FontFamily.gilroy,
    extensions: [palette],
    // The app uses onPrimary for its white text on black, so it stays white;
    // controls that draw on the accent use the palette's onAccent instead.
    colorScheme: ColorScheme.dark(
      primary: palette.accent,
      onPrimary: Colors.white,
    ),
    checkboxTheme: CheckboxThemeData(
      checkColor: WidgetStatePropertyAll(palette.onAccent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(foregroundColor: palette.onAccent),
    ),
    scaffoldBackgroundColor: Colors.black,
    cupertinoOverrideTheme: NoDefaultCupertinoThemeData(
      primaryColor: Colors.white,
      primaryContrastingColor: palette.accent,
      barBackgroundColor: palette.panel,
      scaffoldBackgroundColor: Colors.black,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Colors.black87,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 4,
      overlayColor: Colors.transparent,
      thumbColor: Colors.white,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 16),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(38)),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: palette.panel,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: palette.panel,
      indicatorColor: palette.indicator,
    ),
    chipTheme: ChipThemeData(
      labelPadding: const EdgeInsets.symmetric(horizontal: 11),
      backgroundColor: palette.chip,
      selectedColor: const Color(0xFF0066FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      side: BorderSide.none,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: _tooltipDecoration(palette.surface),
      textStyle: tooltipTextStyle,
      padding: tooltipPadding,
      waitDuration: tooltipDelay,
    ),
  );
}
