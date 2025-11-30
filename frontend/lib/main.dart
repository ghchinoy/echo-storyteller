import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'audio/pcm_player.dart';

void main() {
  runApp(const EchoApp());
}

class EchoApp extends StatefulWidget {
  const EchoApp({super.key});

  @override
  State<EchoApp> createState() => _EchoAppState();
}

class _EchoAppState extends State<EchoApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Project Echo',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF050510),
      ),
      home: EchoScreen(onThemeToggle: _toggleTheme, themeMode: _themeMode),
    );
  }
}

class EchoScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final ThemeMode themeMode;

  const EchoScreen({
    super.key,
    required this.onThemeToggle,
    required this.themeMode,
  });

  @override
  State<EchoScreen> createState() => _EchoScreenState();
}

class _EchoScreenState extends State<EchoScreen> {
  final TextEditingController _controller = TextEditingController();
  WebSocketChannel? _channel;
  final PcmPlayer _player = PcmPlayer(sampleRate: 24000);
  
  final Stopwatch _stopwatch = Stopwatch();
  int? _ttfb;
  bool _isStreaming = false;
  String _status = "Ready";
  
  final List<String> _transcript = [];
  final ScrollController _scrollController = ScrollController();

  final String _voiceName = "Puck";
  final String _modelName = "gemini-2.5-flash-tts";
  final String _stylePrompt = "Tell a short, engaging story. Keep it under 100 words.";

  final List<String> _suggestions = [
    "A cyberpunk detective in Neo-Tokyo.",
    "A lonely robot on Mars.",
    "The secret history of cats.",
    "A wizard who lost his hat.",
  ];

  @override
  void initState() {
    super.initState();
    _connect();
    
    _player.isPlayingStream.listen((playing) {
      if (!playing) {
        setState(() => _status = "Ready");
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse('ws://localhost:8080/ws'));
      setState(() => _status = "Connected");
      
      _channel!.stream.listen((message) {
        if (message is List<int>) {
          _handleAudioChunk(Uint8List.fromList(message));
        } else if (message is String) {
          // Decoupled Text Logic: Display immediately
          setState(() {
            _transcript.add(message);
          });
          _scrollToBottom();
        }
      }, onError: (error) {
        setState(() => _status = "Connection Error");
      }, onDone: () {
        setState(() => _status = "Disconnected");
      });
    } catch (e) {
      setState(() => _status = "Error: $e");
    }
  }

  void _handleAudioChunk(Uint8List chunk) {
    if (_stopwatch.isRunning) {
      _stopwatch.stop();
      setState(() {
        _ttfb = _stopwatch.elapsedMilliseconds;
        _status = "Streaming...";
        _isStreaming = true;
      });
    }
    _player.feed(chunk); // No text sync needed
  }

  void _sendMessage(String text) {
    _player.init();
    
    if (text.isNotEmpty && _channel != null) {
      _stopwatch.reset();
      _stopwatch.start();
      setState(() {
        _ttfb = null;
        _isStreaming = true;
        _status = "Dreaming...";
        _controller.text = text;
        _transcript.clear();
      });

      _channel!.sink.add(text);
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _player.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white54 : Colors.black54;
    final cardColor = isDark ? Colors.white.withOpacity(0.05) : Colors.white;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text("The Echo Storyteller", style: TextStyle(color: textColor)),
        actions: [
          IconButton(
            icon: Icon(
              widget.themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
              color: textColor,
            ),
            onPressed: widget.onThemeToggle,
            tooltip: "Toggle Theme",
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: textColor),
            onPressed: _connect,
            tooltip: "Reconnect",
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Stats Row
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                // Status
                Chip(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                  side: BorderSide.none,
                  avatar: _isStreaming && _status != "Ready"
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.circle, size: 12, color: _status == "Connected" ? Colors.green : Colors.grey),
                  label: Text(_status),
                ),
                // Latency
                if (_ttfb != null)
                  Chip(
                    backgroundColor: Colors.green.withOpacity(0.1),
                    side: BorderSide(color: Colors.green.withOpacity(0.3)),
                    label: Text("TTFB: ${_ttfb}ms", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
                // Voice Info
                Tooltip(
                  message: "Model: $_modelName\nEncoding: LINEAR16 (24kHz)",
                  child: Chip(
                    avatar: const Icon(Icons.record_voice_over, size: 16),
                    label: Text("Voice: $_voiceName"),
                  ),
                ),
                // Persona Info
                Tooltip(
                  message: "System Prompt:\n$_stylePrompt",
                  child: const Chip(
                    avatar: Icon(Icons.psychology, size: 16),
                    label: Text("Persona: Storyteller"),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // The Book (Rich Text View)
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: SelectableText.rich(
                    TextSpan(
                      children: _transcript.asMap().entries.map((entry) {
                        final index = entry.key;
                        final text = entry.value;
                        // Highlight logic: Since text arrives before audio, maybe we highlight the LAST few items?
                        // Or just keep the simple logic: Last item is "Dreaming", others are "Written".
                        final isLast = index == _transcript.length - 1;
                        
                        return TextSpan(
                          text: "$text ",
                          style: TextStyle(
                            fontSize: 20,
                            height: 1.6,
                            fontFamily: 'Georgia',
                            color: isLast ? textColor : dimColor,
                            fontWeight: isLast ? FontWeight.w500 : FontWeight.normal,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 24), 
            
            // Suggestions
            if (!_isStreaming || _status == "Ready")
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                alignment: WrapAlignment.center,
                children: _suggestions.map((s) => ActionChip(
                  label: Text(s),
                  onPressed: () => _sendMessage(s),
                  backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
                  labelStyle: TextStyle(color: textColor),
                )).toList(),
              ),
            
            const SizedBox(height: 24),

            // Input Area
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? Colors.white10 : Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      hintText: "Enter a topic...",
                      hintStyle: TextStyle(color: dimColor),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    onSubmitted: (val) => _sendMessage(val),
                  ),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  onPressed: () => _sendMessage(_controller.text),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.auto_awesome),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
