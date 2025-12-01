import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// PcmPlayer handles the playback of raw PCM (Linear16) audio chunks
/// using the Web Audio API. This allows for gapless, low-latency streaming.
class PcmPlayer {
  final int sampleRate;
  web.AudioContext? _audioContext;
  double _nextPlayTime = 0;
  bool _isInitialized = false;
  
  // State Tracking
  int _scheduledNodes = 0;
  int _playedNodes = 0;
  final StreamController<bool> _isPlayingController = StreamController<bool>.broadcast();
  final StreamController<String> _currentTextController = StreamController<String>.broadcast();

  Stream<bool> get isPlayingStream => _isPlayingController.stream;
  Stream<String> get currentTextStream => _currentTextController.stream;

  PcmPlayer({this.sampleRate = 24000});

  void init() {
    if (_isInitialized && _audioContext != null) {
      if (_audioContext!.state == 'suspended') _audioContext!.resume();
      return;
    }
    final options = web.AudioContextOptions(sampleRate: sampleRate);
    _audioContext = web.AudioContext(options);
    _nextPlayTime = 0;
    _isInitialized = true;
  }

  /// Feeds a chunk of raw PCM (Int16) bytes.
  /// [text] is the subtitle associated with this audio chunk.
  void feed(Uint8List rawData, {String? text}) {
    if (!_isInitialized || _audioContext == null) init();
    if (_audioContext!.state == 'suspended') _audioContext!.resume();

    // 1. Convert Uint8 -> Int16 -> Float32
    final byteData = ByteData.sublistView(rawData);
    final int16Length = rawData.length ~/ 2;
    final float32Data = Float32List(int16Length);

    for (int i = 0; i < int16Length; i++) {
      final int16Sample = byteData.getInt16(i * 2, Endian.little);
      float32Data[i] = int16Sample / 32768.0;
    }

    // 2. Create Buffer
    final buffer = _audioContext!.createBuffer(1, int16Length, sampleRate);
    buffer.copyToChannel(float32Data.toJS, 0);

    // 3. Schedule
    _schedulePlayback(buffer, text);
  }

  void _schedulePlayback(web.AudioBuffer buffer, String? text) {
    final currentTime = _audioContext!.currentTime;
    if (_nextPlayTime < currentTime) _nextPlayTime = currentTime + 0.01;

    final source = _audioContext!.createBufferSource();
    source.buffer = buffer;
    source.connect(_audioContext!.destination);
    
    // Schedule Start
    source.start(_nextPlayTime);
    _scheduledNodes++;
    
    if (_scheduledNodes == 1) {
       _isPlayingController.add(true);
    }

    // Schedule Text Update (roughly when audio starts)
    // We use a simple Timer for the visual sync relative to AudioContext time.
    final delayMs = ((_nextPlayTime - currentTime) * 1000).toInt();
    if (text != null) {
      Future.delayed(Duration(milliseconds: delayMs), () {
        _currentTextController.add(text);
      });
    }

    // Handle Completion
    source.addEventListener('ended', (web.Event e) {
      _playedNodes++;
      if (_playedNodes >= _scheduledNodes) {
        _isPlayingController.add(false); // All drained
      }
    }.toJS);

    _nextPlayTime += buffer.duration;
  }

  /// Stops playback immediately and resets the audio context.
  /// Can be re-initialized by calling [init] or [feed].
  void stop() {
    if (_audioContext != null) {
      try {
        _audioContext!.close();
      } catch (e) {
        debugPrint("Error closing AudioContext: $e");
      }
    }
    _audioContext = null;
    _isInitialized = false;
    _nextPlayTime = 0;
    _scheduledNodes = 0;
    _playedNodes = 0;
    _isPlayingController.add(false);
  }
  
  void dispose() {
    _audioContext?.close();
    _isPlayingController.close();
    _currentTextController.close();
  }
}