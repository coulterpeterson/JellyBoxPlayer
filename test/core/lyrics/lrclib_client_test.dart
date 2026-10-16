import 'package:flutter_test/flutter_test.dart';
import 'package:jplayer/src/core/lyrics/lrclib_client.dart';

void main() {
  group('parseLrc', () {
    test('- reads timestamps into synced lines in order', () {
      final lyrics = parseLrc(
        '[ar: Someone]\n[00:12.50]Second\n[00:01.00]First\n[01:02.345]Third',
      );

      expect(lyrics.isSynced, isTrue);
      expect(
        [for (final line in lyrics.lines) line.text],
        [
          'First',
          'Second',
          'Third',
        ],
      );
      expect(
        lyrics.lines[1].start,
        const Duration(seconds: 12, milliseconds: 500),
      );
      expect(
        lyrics.lines[2].start,
        const Duration(minutes: 1, seconds: 2, milliseconds: 345),
      );
    });

    test('- repeats a line that has several timestamps', () {
      final lyrics = parseLrc('[00:01.00][00:05.00]Chorus');

      expect(lyrics.lines, hasLength(2));
      expect(lyrics.lines.every((line) => line.text == 'Chorus'), isTrue);
    });
  });
}
