/// Non-web stub — HTML SFX is only used on web.
class HtmlSfx {
  HtmlSfx(this.url, {this.volume = 1.0});

  final String url;
  final double volume;

  void preload() {}

  Future<void> unlock() async {}

  void play() {}

  void stop() {}
}
