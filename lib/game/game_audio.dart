import 'dart:async';
import 'dart:math';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/html_sfx.dart';

/// Game sound effects (jump / crash / special crash).
///
/// On **web**, uses [HTMLAudioElement]. On **native**, uses [FlameAudio].
///
/// Desktop Chrome vs mobile: mobile unlocks on the fullscreen hint tap first.
/// Laptop's first gesture is the jump itself — unlock + play used to race on
/// the same element (mute/pause killed the SFX). Unlock is now serialized and
/// web plays await unlock before firing.
class GameAudio {
  final Random _rand = Random();
  int _windowSize = 3;
  int _specialCrashIndex = 1;
  int _windowCrashCount = 0;

  bool _tabLoaded = false;
  bool _specialCrashLoaded = false;
  bool _outCrashLoaded = false;
  bool _unlocked = false;
  Future<void>? _unlockFuture;

  AudioPlayer? _tabPlayer;
  bool _tabMutedBySpecialCrash = false;

  HtmlSfx? _webJump;
  HtmlSfx? _webOut;
  HtmlSfx? _webSpecial;

  void _resetCustomWindow() {
    _windowSize = 3 + _rand.nextInt(10); // 3..12
    _specialCrashIndex = 1 + _rand.nextInt(_windowSize);
    _windowCrashCount = 0;
  }

  Future<void> load() async {
    try {
      FlameAudio.audioCache.prefix = 'assets/';

      if (kIsWeb) {
        _webJump = HtmlSfx('assets/assets/sound/tab.mp3', volume: 0.70)..preload();
        _webOut = HtmlSfx('assets/assets/sound/out.mp3', volume: 1.0)..preload();
        _webSpecial =
            HtmlSfx('assets/assets/sound/sound.mp3', volume: 1.0)..preload();
        _tabLoaded = true;
        _outCrashLoaded = true;
        _specialCrashLoaded = true;
      } else {
        _tabLoaded = await _tryLoad('sound/tab.mp3');
        _specialCrashLoaded = await _tryLoad('sound/sound.mp3');
        _outCrashLoaded = await _tryLoad('sound/out.mp3');
      }
    } catch (e) {
      debugPrint('[GameAudio] load failed (game continues muted): $e');
    }
    _resetCustomWindow();
  }

  Future<bool> _tryLoad(String assetPath) async {
    try {
      await FlameAudio.audioCache.load(assetPath);
      return true;
    } catch (e) {
      debugPrint('[GameAudio] Failed to load $assetPath: $e');
      return false;
    }
  }

  /// Safe to call from any tap — concurrent callers share one unlock.
  Future<void> unlock() {
    if (_unlocked) return Future.value();
    return _unlockFuture ??= _doUnlock();
  }

  Future<void> _doUnlock() async {
    try {
      if (kIsWeb) {
        await Future.wait([
          _webJump?.unlock() ?? Future.value(),
          _webOut?.unlock() ?? Future.value(),
          _webSpecial?.unlock() ?? Future.value(),
        ]);
      }
      _unlocked = true;
      debugPrint('[GameAudio] Audio unlocked');
    } catch (e) {
      debugPrint('[GameAudio] Unlock failed: $e');
      // Allow retry on next gesture.
      _unlockFuture = null;
    }
  }

  void playJump() {
    if (kIsWeb) {
      // Play FIRST while the click/tap still has user-activation.
      // Awaiting unlock() before play() consumes the gesture on desktop Chrome
      // and the following play() is rejected → silent laptop.
      if (!_tabMutedBySpecialCrash) {
        _webJump?.play();
      }
      unawaited(unlock());
    } else if (_tabLoaded && !_tabMutedBySpecialCrash) {
      unawaited(_playJumpNative());
    } else {
      SystemSound.play(SystemSoundType.click);
    }
    debugPrint('[GameAudio] Jump sound');
  }

  Future<void> _playJumpNative() async {
    try {
      final current = _tabPlayer;
      if (current != null) {
        await current.stop();
      }
      _tabPlayer = await FlameAudio.play('sound/tab.mp3', volume: 0.70);
    } catch (e) {
      debugPrint('[GameAudio] Failed to play jump sound: $e');
      SystemSound.play(SystemSoundType.click);
    }
  }

  /// Returns whether the special crash sound was chosen for this window.
  bool playCrash() {
    SystemSound.play(SystemSoundType.click);
    debugPrint('[GameAudio] Crash sound');

    _windowCrashCount++;
    final shouldPlayCustom = _windowCrashCount == _specialCrashIndex;
    if (shouldPlayCustom && _specialCrashLoaded) {
      _tabMutedBySpecialCrash = true;
      unawaited(_playSpecialCrash());
    } else if (_outCrashLoaded) {
      unawaited(_playOutCrash());
    }
    if (_windowCrashCount >= _windowSize) {
      _resetCustomWindow();
    }
    return shouldPlayCustom;
  }

  Future<void> _playOutCrash() async {
    if (kIsWeb) {
      // Crash may fire without a fresh gesture — unlock must already have run
      // from an earlier tap. Still try unlock, then play.
      await unlock();
      _webOut?.play();
    } else {
      try {
        await FlameAudio.play('sound/out.mp3', volume: 1.0);
      } catch (e) {
        debugPrint('[GameAudio] Failed to play out crash: $e');
      }
    }
  }

  void playScore() {
    debugPrint('[GameAudio] Score sound');
  }

  Future<void> _playSpecialCrash() async {
    try {
      if (kIsWeb) {
        await unlock();
        _webJump?.stop();
        _webSpecial?.play();
      } else {
        final current = _tabPlayer;
        if (current != null) {
          await current.stop();
        }
        await FlameAudio.play('sound/sound.mp3', volume: 1.0);
      }
    } catch (e) {
      debugPrint('[GameAudio] Failed to play special crash sound: $e');
    } finally {
      _tabMutedBySpecialCrash = false;
    }
  }
}
