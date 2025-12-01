import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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

class Chapter {
  String? title;
  Uint8List? image;
  final StringBuffer textBuffer = StringBuffer();
  
  String get text => textBuffer.toString();
}

class _EchoScreenState extends State<EchoScreen> {
  final TextEditingController _controller = TextEditingController();
  WebSocketChannel? _channel;
  final PcmPlayer _player = PcmPlayer(sampleRate: 24000);
  
  final Stopwatch _stopwatch = Stopwatch();
  int? _ttfb;
  bool _isStreaming = false;
  String _status = "Ready";
  
  final List<Chapter> _chapters = [];
  String? _context;
  List<String> _plotSuggestions = [];
  
  final ScrollController _scrollController = ScrollController();

  String _selectedVoice = "Puck";
  String _selectedTTSModel = "gemini-2.5-flash-tts";
  final String _stylePrompt = "Tell a short, engaging story. Keep it under 100 words.";

  final List<String> _ttsModels = [
    "gemini-2.5-flash-tts",
    "gemini-2.5-flash-lite-preview-tts",
    "gemini-2.5-pro-tts",
  ];

  final List<String> _voices = [
    "Achernar", "Achird", "Algenib", "Algieba", "Alnilam", "Aoede", "Autonoe",
    "Callirrhoe", "Charon", "Despina", "Enceladus", "Erinome", "Fenrir", "Gacrux",
    "Iapetus", "Kore", "Laomedeia", "Leda", "Orus", "Pulcherrima", "Puck",
    "Rasalgethi", "Sadachbia", "Sadaltager", "Schedar", "Sulafat", "Umbriel",
    "Vindemiatrix", "Zephyr", "Zubenelgenubi",
  ];

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

  Uri getWebSocketUrl() {
    if (kDebugMode) {
      return Uri.parse('ws://localhost:8080/ws');
    }
    
    final currentUri = Uri.base;
    final wsScheme = currentUri.scheme == 'https' ? 'wss' : 'ws';
    return currentUri.replace(scheme: wsScheme, path: '/ws');
  }

  void _connect() {
    try {
      final wsUrl = getWebSocketUrl();
      _channel = WebSocketChannel.connect(wsUrl);
      setState(() => _status = "Connected");
      
      _channel!.stream.listen((message) {
        if (message is List<int>) {
          _handleAudioChunk(Uint8List.fromList(message));
        } else if (message is String) {
          try {
            final data = jsonDecode(message);
            final type = data['type'];
            final content = data['content'];

            setState(() {
              if (type == 'title') {
                final chapter = Chapter();
                chapter.title = content;
                _chapters.add(chapter);
              } else if (type == 'image') {
                if (_chapters.isEmpty) _chapters.add(Chapter());
                _chapters.last.image = base64Decode(content);
              } else if (type == 'context') {
                _context = content;
              } else if (type == 'suggestions') {
                if (data['data'] is List) {
                  _plotSuggestions = List<String>.from(data['data']);
                }
              } else {
                // Sentence
                if (_chapters.isEmpty) _chapters.add(Chapter());
                _chapters.last.textBuffer.write("$content ");
              }
            });
            _scrollToBottom();
          } catch (e) {
            // Fallback for legacy plain text (if any)
             setState(() {
              if (_chapters.isEmpty) _chapters.add(Chapter());
              _chapters.last.textBuffer.write("$message ");
            });
            _scrollToBottom();
          }
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

  void _sendMessage(String text, {bool keepContext = false}) {
    _player.init();
    
    if (text.isNotEmpty && _channel != null) {
      _stopwatch.reset();
      _stopwatch.start();
      
      setState(() {
        _ttfb = null;
        _isStreaming = true;
        _status = "Dreaming...";
        _controller.text = keepContext ? "" : text; // Clear input if continuing? Or keep? Usually clear.
        if (!keepContext) {
          _chapters.clear();
          _context = null;
        }
        _plotSuggestions = [];
      });

      final payload = jsonEncode({
        "topic": text,
        "voice": _selectedVoice,
        "tts_model": _selectedTTSModel,
        "context": _context,
      });
      _channel!.sink.add(payload);
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
    final cardColor = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          (_chapters.isNotEmpty && _chapters.first.title != null) 
              ? "The Echo Storyteller: ${_chapters.first.title}" 
              : "The Echo Storyteller",
          style: TextStyle(color: textColor),
        ),
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
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  side: BorderSide.none,
                  avatar: _isStreaming && _status != "Ready"
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.circle, size: 12, color: _status == "Connected" ? Colors.green : Colors.grey),
                  label: Text(_status),
                ),
                // Latency
                if (_ttfb != null)
                  Chip(
                    backgroundColor: Colors.green.withValues(alpha: 0.1),
                    side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
                    label: Text("TTFB: ${_ttfb}ms", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
                // Voice Info
                Tooltip(
                  message: "Model: $_selectedTTSModel\nEncoding: LINEAR16 (24kHz)",
                  child: Chip(
                    avatar: const Icon(Icons.record_voice_over, size: 16),
                    label: Text("Voice: $_selectedVoice"),
                  ),
                ),
                // Persona Info
                Tooltip(
                                        message: "Persona:\n$_stylePrompt",                  child: const Chip(
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
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ..._chapters.map((chapter) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (chapter.title != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 24.0, bottom: 16.0),
                              child: Text(
                                chapter.title!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Georgia',
                                  color: textColor,
                                ),
                              ),
                            ),
                          
                          // Chapter Image
                          AnimatedSize(
                            duration: const Duration(milliseconds: 800),
                            curve: Curves.easeOutQuart,
                            child: chapter.image == null
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding: const EdgeInsets.only(bottom: 24.0),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.memory(
                                        chapter.image!,
                                        fit: BoxFit.cover,
                                        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                                          if (wasSynchronouslyLoaded) return child;
                                          return AnimatedOpacity(
                                            opacity: frame == null ? 0 : 1,
                                            duration: const Duration(seconds: 1),
                                            curve: Curves.easeOut,
                                            child: child,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                          ),

                          // Chapter Text
                          SelectableText(
                            chapter.text,
                            style: TextStyle(
                              fontSize: 20,
                              height: 1.6,
                              fontFamily: 'Georgia',
                              color: textColor, // Simplify color logic for now (all black/white)
                            ),
                          ),
                          const Divider(height: 48, thickness: 0.5),
                        ],
                      )),
                    ],
                  ),
                ),
              ),
            ),
            
            // Plot Suggestions (Fixed between Book and Input)
            AnimatedSize(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutQuart,
              child: _plotSuggestions.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 16),
                        Text("What happens next?", style: TextStyle(color: dimColor, fontStyle: FontStyle.italic, fontSize: 12)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          alignment: WrapAlignment.center,
                          children: _plotSuggestions.map((s) => ActionChip(
                            label: Text(s),
                            onPressed: () => _sendMessage(s, keepContext: true),
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                            side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                            labelStyle: TextStyle(color: textColor),
                          )).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            
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
                      hintText: "Enter your story topic...",
                      hintStyle: TextStyle(color: dimColor),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                    onSubmitted: (val) => _sendMessage(val, keepContext: false),
                  ),
                ),
                const SizedBox(width: 12),
                // Voice Selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey[200],
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedVoice,
                      icon: Icon(Icons.record_voice_over, color: textColor, size: 20),
                      dropdownColor: isDark ? Colors.grey[900] : Colors.white,
                      style: TextStyle(color: textColor),
                      onChanged: _isStreaming ? null : (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedVoice = newValue;
                          });
                        }
                      },
                      items: _voices.map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Model Selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey[200],
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedTTSModel,
                      icon: Icon(Icons.psychology, color: textColor, size: 20),
                      dropdownColor: isDark ? Colors.grey[900] : Colors.white,
                      style: TextStyle(color: textColor),
                      onChanged: _isStreaming ? null : (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedTTSModel = newValue;
                          });
                        }
                      },
                      items: _ttsModels.map<DropdownMenuItem<String>>((String value) {
                        String label = "Flash";
                        if (value.contains("lite")) label = "Lite";
                        if (value.contains("pro")) label = "Pro";
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(label),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  onPressed: () => _sendMessage(_controller.text, keepContext: false),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.auto_awesome),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Quick Start Suggestions (Only on empty state)
            if (_chapters.isEmpty && !_isStreaming)
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                alignment: WrapAlignment.center,
                children: _suggestions.map((s) => ActionChip(
                  label: Text(s),
                  onPressed: () => _sendMessage(s, keepContext: false),
                  backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
                  labelStyle: TextStyle(color: textColor),
                )).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
