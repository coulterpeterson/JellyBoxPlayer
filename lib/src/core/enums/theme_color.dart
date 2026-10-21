/// The colour of the regular app interface. Each keeps the saturation and
/// brightness of the original JellyBox maroon and changes only its hue;
/// [white] drops the colour entirely.
enum ThemeColor {
  red('Red', hue: 348),
  orange('Orange', hue: 24),
  yellow('Yellow', hue: 50),
  green('Green', hue: 135),
  blue('Blue', hue: 214),
  purple('Purple', hue: 272),
  white('White');

  const ThemeColor(this.label, {this.hue});

  final String label;

  /// The hue every colour of the palette is turned to, or null for a
  /// colourless palette.
  final double? hue;
}
