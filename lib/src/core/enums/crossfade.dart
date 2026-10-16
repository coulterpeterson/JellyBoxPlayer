/// How long the end of a song fades out and the next one fades in.
enum Crossfade {
  off(0),
  s2(2),
  s4(4),
  s6(6),
  s8(8),
  s12(12);

  const Crossfade(this.seconds);

  final int seconds;

  Duration get duration => Duration(seconds: seconds);
}
