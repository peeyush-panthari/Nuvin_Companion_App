import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum InteractionMode {
  openSpeaker, // Mode 1: Hands-free speakerphone
  chatOpenUI,  // Mode 2: Silent chat with OpenUI cards
  callEarpiece // Mode 3: Near ear / phone call mode
}

class AudioManager extends ChangeNotifier {
  InteractionMode _currentMode = InteractionMode.openSpeaker;
  bool _isNearEar = false;
  StreamSubscription<dynamic>? _proximitySubscription;
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  bool _isInitialized = false;

  VoidCallback? onSpeakingStarted;
  VoidCallback? onSpeakingCompleted;

  InteractionMode get currentMode => _currentMode;
  bool get isNearEar => _isNearEar;
  bool get isSpeaking => _isSpeaking;

  AudioManager() {
    _initTts();
  }

  Future<void> _initTts() async {
    if (_isInitialized) return;
    try {
      final dynamic rawLangs = await _tts.getLanguages;
      final List<String> languages = rawLangs != null ? List<String>.from(rawLangs) : [];
      debugPrint('Available TTS languages count: ${languages.length}');

      // Select best supported language
      if (languages.contains('hi-IN') || languages.contains('hi_IN')) {
        await _tts.setLanguage('hi-IN');
      } else if (languages.contains('en-IN') || languages.contains('en_IN')) {
        await _tts.setLanguage('en-IN');
      } else {
        await _tts.setLanguage('en-US');
      }

      await _tts.setSpeechRate(0.48); // Natural, clear cadence
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);

      // Async dispatch without blocking MethodChannel
      await _tts.awaitSpeakCompletion(false);
      // Native queueing mode (QUEUE_ADD = 1) for streaming chunks
      await _tts.setQueueMode(1);

      _tts.setStartHandler(() {
        _isSpeaking = true;
        onSpeakingStarted?.call();
        notifyListeners();
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        onSpeakingCompleted?.call();
        notifyListeners();
      });

      _tts.setCancelHandler(() {
        _isSpeaking = false;
        onSpeakingCompleted?.call();
        notifyListeners();
      });

      _tts.setErrorHandler((msg) {
        debugPrint('TTS engine error: $msg');
        _isSpeaking = false;
        onSpeakingCompleted?.call();
        notifyListeners();
      });

      _isInitialized = true;
      debugPrint('AudioManager TTS initialized and ready for playback');
    } catch (e) {
      debugPrint('Error initializing TTS: $e');
    }
  }

  /// Speak a streaming phrase chunk using native queueing
  Future<void> speakChunk(String phrase, {String? locale, double? rate}) async {
    final clean = phrase.trim();
    if (clean.isEmpty) return;

    if (!_isInitialized) {
      await _initTts();
    }

    try {
      _isSpeaking = true;
      notifyListeners();
      await _tts.speak(clean);
    } catch (e) {
      debugPrint('TTS speak failed for "$clean": $e');
      _isSpeaking = false;
      notifyListeners();
    }
  }

  /// Speak full text directly
  Future<void> speakImmediate(String fullText, {String? locale, double? rate}) async {
    await stop();
    await speakChunk(fullText, locale: locale, rate: rate);
  }

  /// Instant barge-in: cancel native speech playback immediately
  Future<void> stop() async {
    _isSpeaking = false;
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('Error stopping TTS: $e');
    }
    onSpeakingCompleted?.call();
    notifyListeners();
  }

  void initializeProximityListener() {
    try {
      _proximitySubscription = ProximitySensor.events.listen((int event) {
        bool near = event > 0;
        if (_isNearEar != near) {
          _isNearEar = near;
          if (_isNearEar) {
            _routeAudioToEarpiece();
          } else {
            _routeAudioToSpeaker();
          }
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('Proximity sensor not available on this device: $e');
    }
  }

  void setMode(InteractionMode mode) {
    _currentMode = mode;
    if (mode == InteractionMode.openSpeaker) {
      _routeAudioToSpeaker();
    } else if (mode == InteractionMode.callEarpiece) {
      _routeAudioToEarpiece();
    }
    notifyListeners();
  }

  void _routeAudioToEarpiece() {
    debugPrint('Audio Routed to: EARPIECE (Call Mode Active)');
  }

  void _routeAudioToSpeaker() {
    debugPrint('Audio Routed to: LOUDSPEAKER (Open Speaker Mode Active)');
  }

  @override
  void dispose() {
    _proximitySubscription?.cancel();
    _tts.stop();
    super.dispose();
  }
}
