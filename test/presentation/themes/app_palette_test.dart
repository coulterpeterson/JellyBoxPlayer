import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jplayer/src/core/enums/theme_color.dart';
import 'package:jplayer/src/presentation/themes/themes.dart';

void main() {
  double contrast(Color a, Color b) => AppPalette.contrast(a, b);

  test('red reproduces the original JellyBox palette', () {
    final red = AppPalette.of(ThemeColor.red);
    expect(red.accent, const Color(0xFFFD2F2F));
    expect(red.panel, const Color(0xFF471F27));
    expect(red.onAccent, Colors.white);
  });

  test('other colours keep the maroon panel saturation and lightness', () {
    final original = HSLColor.fromColor(AppPalette.of(ThemeColor.red).panel);
    for (final color in ThemeColor.values) {
      final panel = HSLColor.fromColor(AppPalette.of(color).panel);
      expect(
        panel.lightness,
        closeTo(original.lightness, 0.01),
        reason: '$color',
      );
      if (color.hue != null) {
        expect(panel.saturation, closeTo(original.saturation, 0.01));
        expect(panel.hue, closeTo(color.hue!, 1), reason: '$color');
      }
    }
  });

  group('text stays readable', () {
    for (final color in ThemeColor.values) {
      test(color.label, () {
        final p = AppPalette.of(color);
        // Accent used as text or icons on the black background and on bars.
        expect(contrast(p.accent, Colors.black), greaterThanOrEqualTo(4.5));
        expect(contrast(p.accent, p.panel), greaterThanOrEqualTo(3));
        // Labels on accent-coloured buttons.
        expect(contrast(p.onAccent, p.accent), greaterThanOrEqualTo(3));
        // White text on bars, sheets, chips, dialogs and the rail indicator.
        for (final background in [p.panel, p.chip, p.surface, p.indicator]) {
          expect(
            contrast(Colors.white, background),
            greaterThanOrEqualTo(7),
            reason: '$color on $background',
          );
        }
      });
    }
  });

  testWidgets('every theme renders readable text on its surfaces', (
    tester,
  ) async {
    for (final color in ThemeColor.values) {
      final theme = Themes.of(color);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(onPressed: () {}, child: const Text('Play')),
                const Text('Body'),
                Checkbox(value: true, onChanged: (_) {}),
                ColoredBox(
                  color: theme.bottomSheetTheme.backgroundColor!,
                  child: const Text('Sheet'),
                ),
              ],
            ),
          ),
        ),
      );
      // MaterialApp animates between themes.
      await tester.pumpAndSettle();
      final button = tester.widget<DefaultTextStyle>(
        find
            .ancestor(
              of: find.text('Play'),
              matching: find.byType(DefaultTextStyle),
            )
            .first,
      );
      expect(
        contrast(button.style.color!, theme.colorScheme.primary),
        greaterThanOrEqualTo(3),
        reason: '$color button label',
      );
      // The app writes its body text in onPrimary on the black background.
      expect(theme.colorScheme.onPrimary, Colors.white, reason: '$color');
      expect(
        contrast(theme.colorScheme.onPrimary, theme.scaffoldBackgroundColor),
        greaterThanOrEqualTo(7),
      );
      final check = theme.checkboxTheme.checkColor!.resolve({
        WidgetState.selected,
      })!;
      expect(
        contrast(check, theme.colorScheme.primary),
        greaterThanOrEqualTo(3),
        reason: '$color checkbox tick',
      );
      final sheet = tester.widget<DefaultTextStyle>(
        find
            .ancestor(
              of: find.text('Sheet'),
              matching: find.byType(DefaultTextStyle),
            )
            .first,
      );
      expect(
        contrast(sheet.style.color!, theme.bottomSheetTheme.backgroundColor!),
        greaterThanOrEqualTo(7),
        reason: '$color sheet text',
      );
    }
  });
}
