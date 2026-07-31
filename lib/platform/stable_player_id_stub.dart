/// Non-web: no browser localStorage — caller falls back to Auth uid.
String? readStablePlayerId() => null;

void writeStablePlayerId(String id) {}

int? readCachedTotalScore() => null;

void writeCachedTotalScore(int total) {}

bool? readLocalFlag(String key) => null;

void writeLocalFlag(String key, bool value) {}
