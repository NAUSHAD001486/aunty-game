/// No-op on native platforms (APK uses [SystemChrome] landscape lock).
void requestBrowserFullscreen() {}

bool get isBrowserFullscreen => false;

void lockLandscapeOrientation() {}
