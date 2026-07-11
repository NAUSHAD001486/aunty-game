import 'dart:async';
import 'dart:math';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lightweight sound hook system for game audio events.
///
/// Currently logs debug messages only (no actual audio playback).
/// This prepares the architecture for future Flame Audio integration.
class GameAudio {
  final Random _rand = Random();
  int _windowSize = 3;
  int _specialCrashIndex = 1;
  int _windowCrashCount = 0;
  bool _tabLoaded = false;
  bool _specialCrashLoaded = false;
  bool _outCrashLoaded = false;
  AudioPlayer? _tabPlayer;
  bool _tabMutedBySpecialCrash = false;

  void _resetCustomWindow() {
    _windowSize = 3 + _rand.nextInt(10); // 3..12
    _specialCrashIndex = 1 + _rand.nextInt(_windowSize); // one random slot in window
    _windowCrashCount = 0;
  }

  Future<void> load() async {
    // FlameAudio defaults to assets/audio/. Our file is in assets/sound/.
    FlameAudio.audioCache.prefix = 'assets/';
    _tabLoaded = await _tryLoad('sound/tab.mp3');
    _specialCrashLoaded = await _tryLoad('sound/sound.mp3');
    _outCrashLoaded = await _tryLoad('sound/out.mp3');
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

  /// Play jump sound effect.
  ///
  /// Called when player performs a jump action.
  void playJump() {
    if (_tabLoaded && !_tabMutedBySpecialCrash) {
      unawaited(_playJumpFromStart());
    } else {
      SystemSound.play(SystemSoundType.click);
    }
    debugPrint('[GameAudio] Jump sound');
  }

  Future<void> _playJumpFromStart() async {
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

  /// Play crash/collision sound effect.
  ///
  /// Called when player collides with an obstacle (game over).
  bool playCrash() {
    // Default crash click plays every time.
    SystemSound.play(SystemSoundType.click);
    debugPrint('[GameAudio] Crash sound');

    // In each 3..12 crash window, custom sound plays exactly once at random.
    _windowCrashCount++;
    final shouldPlayCustom = _windowCrashCount == _specialCrashIndex;
    if (shouldPlayCustom && _specialCrashLoaded) {
      _tabMutedBySpecialCrash = true;
      unawaited(_muteTabAndPlaySpecialCrash());
    } else if (_outCrashLoaded) {
      unawaited(FlameAudio.play('sound/out.mp3', volume: 1.0));
    }
    if (_windowCrashCount >= _windowSize) {
      _resetCustomWindow();
    }
    return shouldPlayCustom;
  }

  /// Play score increment sound effect.
  ///
  /// Called when player successfully passes an obstacle.
  void playScore() {
    debugPrint('[GameAudio] Score sound');
  }

  Future<void> _muteTabAndPlaySpecialCrash() async {
    try {
      final current = _tabPlayer;
      if (current != null) {
        await current.stop();
      }
      await FlameAudio.play('sound/sound.mp3', volume: 1.0);
    } catch (e) {
      debugPrint('[GameAudio] Failed to play special crash sound: $e');
    } finally {
      _tabMutedBySpecialCrash = false;
    }
  }
}

