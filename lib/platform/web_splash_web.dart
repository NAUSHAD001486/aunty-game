import 'package:web/web.dart' as web;

/// Hides the HTML landing shell once Flutter's first frame is painted.
/// Fades out to avoid a layout jump when Flutter mirrors the same card copy.
void hideWebLoadingOverlay() {
  final shell = web.document.getElementById('landing-shell');
  final host = web.document.getElementById('flutter-host');
  if (host != null) {
    host.classList.add('is-ready');
  }
  if (shell != null) {
    shell.classList.add('is-hiding');
    // Match CSS transition (~180ms) then remove.
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      shell.remove();
    });
  }
  web.document.getElementById('loading')?.remove();
}
