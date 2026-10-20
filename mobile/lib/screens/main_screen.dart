import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants/colors.dart';
import '../models/user_profile.dart';
import '../models/open_ui_card.dart';
import '../services/audio_manager.dart';
import '../services/api_service.dart';
import '../widgets/voice_orb.dart';
import '../widgets/open_ui_card_widget.dart';
import '../widgets/nuvin_mark.dart';

class FeedMessage {
  final String id;
  final String sender; // 'you' or 'nuvin'
  final String text;
  final OpenUICard? card;
  final DateTime timestamp;

  FeedMessage({
    required this.id,
    required this.sender,
    required this.text,
    this.card,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class MemoryItem {
  final String id;
  final String text;
  final String category;
  final String savedAt;
  final String reason;

  MemoryItem({
    required this.id,
    required this.text,
    required this.category,
    required this.savedAt,
    required this.reason,
  });
}

class MainScreen extends StatefulWidget {
  final UserProfile profile;
  final VoidCallback? onSignOut;

  const MainScreen({super.key, required this.profile, this.onSignOut});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final AudioManager _audioManager = AudioManager();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String _interactionMode = 'chat'; // 'chat' or 'voice'
  String _audioMode = 'speaker'; // 'speaker' or 'call'
  OrbState _orbState = OrbState.idle;
  late UserProfile _profile;

  final List<FeedMessage> _feed = [];
  final List<MemoryItem> _memories = [
    MemoryItem(
      id: 'm-aarav',
      text: "Grandson Aarav's birthday is coming up on October 24th.",
      category: 'Family & Relationships',
      savedAt: 'Today · 10:15 AM',
      reason: 'You asked me to remember an important family date.',
    ),
    MemoryItem(
      id: 'm-meds',
      text: 'Amlodipine 5mg, one tablet with warm water in the afternoon.',
      category: 'Health & Medication',
      savedAt: 'Yesterday · 4:20 PM',
      reason: 'You shared your medicine routine so I can help with reminders.',
    ),
    MemoryItem(
      id: 'm-chai',
      text: 'You like a quiet cup of chai after your evening walk.',
      category: 'Daily Preferences & Habits',
      savedAt: 'Monday · 6:05 PM',
      reason: 'You mentioned this as part of your evening routine.',
    ),
  ];

  // SOS state
  bool _sosOpen = false;
  bool _sosActive = false;
  int _sosCount = 5;
  Timer? _sosTimer;

  // Notice toast
  String _notice = '';

  // Backend Voice & Chat state
  bool _isSending = false;
  WebSocketChannel? _voiceChannel;
  bool _isVoiceConnected = false;
  String _voiceTranscript = 'Tap the orb or select a prompt below to speak.';

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _audioManager.initializeProximityListener();

    final isElder = _profile.isElder;
    final compName = _profile.companionName;

    final initialGreeting = isElder
        ? "Namaste ji. Aapka BP medicine lene ka samay ho gaya hai. $compName yahin hai."
        : "Good afternoon. I'm $compName, here if you need a reminder or a quiet moment.";

    _feed.add(FeedMessage(
      id: 'msg-hello',
      sender: 'nuvin',
      text: initialGreeting,
    ));

    // Seed medication card
    _feed.add(FeedMessage(
      id: 'med-card-1',
      sender: 'nuvin',
      text: '',
      card: OpenUICard(
        type: 'medication_card',
        title: 'Afternoon blood pressure medicine',
        data: {'detail': 'Amlodipine 5mg · 1 tablet with warm water'},
      ),
    ));

    _connectVoiceWs();

    _audioManager.onSpeakingStarted = () {
      if (mounted) setState(() => _orbState = OrbState.speaking);
    };
    _audioManager.onSpeakingCompleted = () {
      if (mounted && _orbState == OrbState.speaking) {
        setState(() => _orbState = OrbState.idle);
      }
    };
  }

  void _connectVoiceWs() {
    try {
      _voiceChannel?.sink.close();
      _voiceChannel = ApiService.connectVoiceStream(_profile.id);
      _voiceChannel?.stream.listen((event) {
        try {
          final data = jsonDecode(event.toString()) as Map<String, dynamic>;
          _handleVoiceEvent(data);
        } catch (e) {
          debugPrint('Error parsing voice event: $e');
        }
      }, onError: (err) {
        debugPrint('Voice WS error: $err');
        if (mounted) setState(() => _isVoiceConnected = false);
      }, onDone: () {
        if (mounted) setState(() => _isVoiceConnected = false);
      });
      if (mounted) setState(() => _isVoiceConnected = true);
    } catch (e) {
      debugPrint('Failed to connect voice WS: $e');
      if (mounted) setState(() => _isVoiceConnected = false);
    }
  }

  void _handleVoiceEvent(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'audio_chunk') {
      final text = data['text'] as String? ?? '';
      final seqId = data['sequence_id'] as int? ?? 1;
      setState(() {
        _orbState = OrbState.speaking;
        if (text.isNotEmpty) {
          if (seqId <= 1) {
            _voiceTranscript = text;
          } else {
            _voiceTranscript = '$_voiceTranscript $text';
          }
        }
      });
      if (text.isNotEmpty) {
        _audioManager.speakChunk(text, locale: _profile.locale);
      }
    } else if (type == 'open_ui_card') {
      final cardJson = data['card'] as Map<String, dynamic>;
      setState(() {
        _feed.add(FeedMessage(
          id: 'card-${DateTime.now().millisecondsSinceEpoch}',
          sender: 'nuvin',
          text: '',
          card: OpenUICard.fromJson(cardJson),
        ));
      });
      _scrollToBottom();
    } else if (type == 'turn_complete') {
      final fullText = data['full_text'] as String?;
      if (fullText != null && fullText.isNotEmpty && mounted) {
        setState(() {
          _voiceTranscript = fullText;
        });
      }
    } else if (type == 'barge_in_ack') {
      _audioManager.stop();
      setState(() {
        _orbState = OrbState.listening;
        _voiceTranscript = 'Listening... (Interrupted)';
      });
    }
  }

  void _sendVoiceTurn(String text) {
    _audioManager.stop();
    if (!_isVoiceConnected || _voiceChannel == null) {
      _connectVoiceWs();
    }
    setState(() {
      _orbState = OrbState.thinking;
      _voiceTranscript = 'Thinking: "$text"...';
    });
    _voiceChannel?.sink.add(jsonEncode({
      'type': 'user_turn',
      'text': text,
      'locale': _profile.locale,
    }));
  }

  void _handleOrbTap() {
    if (_orbState == OrbState.speaking) {
      // Barge-in interruption: immediately halt audio playback and notify backend
      _audioManager.stop();
      _voiceChannel?.sink.add(jsonEncode({
        'type': 'barge_in',
        'last_played_seq': 1,
      }));
      setState(() {
        _orbState = OrbState.listening;
        _voiceTranscript = 'Listening... (Barged in)';
      });
    } else if (_orbState == OrbState.idle) {
      _audioManager.stop();
      setState(() {
        _orbState = OrbState.listening;
        _voiceTranscript = 'Listening...';
      });
    } else if (_orbState == OrbState.listening) {
      // Simulate/trigger voice turn
      _sendVoiceTurn("Hello Nuvin, I am here.");
    } else {
      _audioManager.stop();
      setState(() => _orbState = OrbState.idle);
    }
  }

  @override
  void dispose() {
    _sosTimer?.cancel();
    _voiceChannel?.sink.close();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showNotice(String msg) {
    setState(() => _notice = msg);
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _notice = '');
    });
  }

  void _cycleOrbState() {
    _handleOrbTap();
  }

  Future<void> _handleSendMessage() async {
    final query = _textController.text.trim();
    if (query.isEmpty || _isSending) return;

    _textController.clear();

    setState(() {
      _isSending = true;
      _feed.add(FeedMessage(
        id: 'user-${DateTime.now().millisecondsSinceEpoch}',
        sender: 'you',
        text: query,
      ));
      _orbState = OrbState.thinking;
    });

    _scrollToBottom();

    try {
      final response = await ApiService.sendChatMessage(
        userId: _profile.id,
        message: query,
        locale: _profile.locale,
      );

      if (mounted) {
        setState(() {
          _feed.add(FeedMessage(
            id: 'nuvin-${response.sessionId}',
            sender: 'nuvin',
            text: response.spokenResponse,
            card: response.openUiCard != null ? OpenUICard.fromJson(response.openUiCard!) : null,
          ));

          if (response.actionTriggered == 'create_reminder' && response.actionPayload != null) {
            final payload = response.actionPayload!;
            _showNotice('Reminder scheduled: ${payload['title'] ?? 'New Reminder'}');
          }

          _orbState = OrbState.speaking;
          _isSending = false;
        });

        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && _orbState == OrbState.speaking) {
            setState(() => _orbState = OrbState.idle);
          }
        });
      }
    } catch (e) {
      debugPrint('Backend call failed: $e. Falling back to local offline handler.');
      if (mounted) {
        _handleLocalMessageFallback(query);
        setState(() => _isSending = false);
      }
    }

    _scrollToBottom();
  }

  void _handleLocalMessageFallback(String query) {
    final lower = query.toLowerCase();
    final isDistress = RegExp(r"(suicid|kill myself|hurt myself|self harm|hopeless|can't go on|unsafe|want to die|marna|jeena nahi|khud ko)", caseSensitive: false).hasMatch(lower);
    final asksToRemember = RegExp(r"^(please )?remember\b", caseSensitive: false).hasMatch(lower);

    String reply;
    if (isDistress) {
      reply = "I’m really glad you told me. You deserve support from a person right now. If you may be in immediate danger, call your local emergency number.";
    } else if (asksToRemember) {
      reply = "I can save that in your Memory Vault. You can review or delete it any time.";
    } else if (_profile.isElder) {
      reply = "Ji, main sun rahi hoon. Aap aaram se bataiye — kya aap chahenge ki hum iske baare mein baat karein?";
    } else {
      reply = "I'm right here with you. Want to tell me a little more?";
    }

    setState(() {
      _feed.add(FeedMessage(
        id: 'nuvin-${DateTime.now().millisecondsSinceEpoch}',
        sender: 'nuvin',
        text: reply,
      ));

      if (isDistress) {
        _feed.add(FeedMessage(
          id: 'crisis-${DateTime.now().millisecondsSinceEpoch}',
          sender: 'nuvin',
          text: '',
          card: OpenUICard(type: 'crisis_card', title: 'Crisis Support', data: {}),
        ));
      }

      _orbState = OrbState.speaking;
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _forgetMemory(String id) {
    setState(() {
      _memories.removeWhere((m) => m.id == id);
      _feed.removeWhere((f) => f.card?.type == 'memory_vault_card' && f.card?.data['id'] == id);
    });
    _showNotice('Memory deleted from this device.');
  }

  // SOS Countdown handling
  void _startSos() {
    setState(() {
      _sosOpen = true;
      _sosActive = true;
      _sosCount = 5;
    });

    _sosTimer?.cancel();
    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sosCount <= 1) {
        timer.cancel();
        setState(() {
          _sosActive = false;
        });
      } else {
        setState(() => _sosCount--);
      }
    });
  }

  void _cancelSos() {
    _sosTimer?.cancel();
    setState(() {
      _sosActive = false;
      _sosOpen = false;
    });
    _showNotice('SOS canceled.');
  }

  @override
  Widget build(BuildContext context) {
    final isElder = _profile.isElder;
    final touchSize = isElder ? 56.0 : 46.0;
    final titleSize = isElder ? 28.0 : 22.0;

    return Scaffold(
      backgroundColor: NuvinColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(touchSize),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      _buildWelcomeBanner(titleSize),
                      const SizedBox(height: 12),
                      _buildModeTabs(),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
                Expanded(
                  child: _interactionMode == 'chat'
                      ? SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildChatStream(isElder),
                              const SizedBox(height: 12),
                              _buildDisclaimer(),
                              const SizedBox(height: 16),
                            ],
                          ),
                        )
                      : _buildVoiceTabContent(isElder),
                ),
                _buildBottomComposer(touchSize, isElder),
              ],
            ),

            // Top notice bar
            if (_notice.isNotEmpty)
              Positioned(
                top: 8,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  decoration: BoxDecoration(
                    color: NuvinColors.secondary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: NuvinColors.primary.withOpacity(0.5)),
                  ),
                  child: Text(
                    _notice,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: NuvinColors.primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

            // SOS Modal overlay
            if (_sosOpen) _buildSosOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(double touchSize) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        color: NuvinColors.background,
        border: Border(bottom: BorderSide(color: NuvinColors.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const NuvinMark(size: 38),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'nuvin',
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: NuvinColors.text,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: NuvinColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'A little more support',
                        style: TextStyle(
                          fontSize: 11,
                          color: NuvinColors.mutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: _openProfileSheet,
                icon: const Icon(Icons.account_circle_outlined, color: Color(0xFFB6C5D8), size: 28),
                constraints: BoxConstraints(minWidth: touchSize, minHeight: touchSize),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: _startSos,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  constraints: BoxConstraints(minHeight: touchSize - 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: NuvinColors.destructive,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: NuvinColors.destructive.withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'SOS',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeBanner(double titleSize) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'YOUR SPACE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: NuvinColors.mutedForeground,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Take a breath.',
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: titleSize + 2,
                fontWeight: FontWeight.w400,
                color: NuvinColors.text,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: NuvinColors.secondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NuvinColors.border),
          ),
          child: Row(
            children: const [
              Icon(Icons.lock_outline, size: 12, color: NuvinColors.mutedForeground),
              SizedBox(width: 5),
              Text(
                'On this device',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: NuvinColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NuvinColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: NuvinColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _tabPill(
              label: 'Chat',
              icon: Icons.chat_bubble_outline_rounded,
              isSelected: _interactionMode == 'chat',
              onTap: () {
                _audioManager.stop();
                setState(() => _interactionMode = 'chat');
              },
            ),
          ),
          Expanded(
            child: _tabPill(
              label: 'Voice',
              icon: Icons.mic_none_rounded,
              isSelected: _interactionMode == 'voice',
              onTap: () {
                setState(() => _interactionMode = 'voice');
                _audioManager.speakChunk("Voice mode active. How can I help you?", locale: _profile.locale);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabPill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? NuvinColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: isSelected ? NuvinColors.primaryForeground : NuvinColors.mutedForeground,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: isSelected ? NuvinColors.primaryForeground : NuvinColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatStream(bool isElder) {
    return Column(
      children: _feed.map((msg) {
        if (msg.card != null) {
          return OpenUiCardWidget(
            card: msg.card!,
            isElder: isElder,
            onAction: (action, data) {
              if (action == 'forget') {
                _forgetMemory(data['id'] ?? 'm-aarav');
              } else if (action == 'taken') {
                setState(() {
                  _feed.add(FeedMessage(
                    id: 'conf-${DateTime.now().millisecondsSinceEpoch}',
                    sender: 'nuvin',
                    text: 'Thank you for letting me know. I’ve marked this reminder as taken.',
                  ));
                });
              }
            },
          );
        }

        final isUser = msg.sender == 'you';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: NuvinColors.secondary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 14, color: NuvinColors.primary),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser ? NuvinColors.primary : NuvinColors.card,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                    border: isUser ? null : Border.all(color: NuvinColors.border),
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      fontSize: isElder ? 18 : 15,
                      color: isUser ? NuvinColors.primaryForeground : NuvinColors.text,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDisclaimer() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.info_outline, size: 13, color: Color(0xFF8493AA)),
        SizedBox(width: 6),
        Text(
          'Sample chat · AI service connected locally (Llama 3.1:8b)',
          style: TextStyle(fontSize: 11, color: Color(0xFF8493AA)),
        ),
      ],
    );
  }

  Widget _buildBottomComposer(double touchSize, bool isElder) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: NuvinColors.card,
        border: Border(top: BorderSide(color: NuvinColors.border)),
      ),
      child: _interactionMode == 'chat'
          ? Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: NuvinColors.secondary,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: NuvinColors.border),
                    ),
                    child: TextField(
                      controller: _textController,
                      style: TextStyle(
                        color: NuvinColors.text,
                        fontSize: isElder ? 17 : 15,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type a thought or question…',
                        hintStyle: const TextStyle(color: Color(0xFF8290A4), fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: _handleSendMessage,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: touchSize,
                    height: touchSize,
                    decoration: const BoxDecoration(
                      color: NuvinColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_upward_rounded, color: NuvinColors.primaryForeground, size: 24),
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _audioChoicePill(
                      label: 'Speaker',
                      icon: Icons.volume_up_outlined,
                      isActive: _audioMode == 'speaker',
                      onTap: () {
                        setState(() => _audioMode = 'speaker');
                        _audioManager.setMode(InteractionMode.openSpeaker);
                      },
                    ),
                    const SizedBox(width: 12),
                    _audioChoicePill(
                      label: 'Call mode',
                      icon: Icons.call_outlined,
                      isActive: _audioMode == 'call',
                      onTap: () {
                        setState(() => _audioMode = 'call');
                        _audioManager.setMode(InteractionMode.callEarpiece);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _isVoiceConnected
                      ? 'Nuvin Voice Engine active · Tap orb to speak or interrupt'
                      : 'Connecting to voice engine...',
                  style: const TextStyle(fontSize: 11.5, color: NuvinColors.mutedForeground),
                ),
              ],
            ),
    );
  }

  Widget _buildVoiceTabContent(bool isElder) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            VoiceOrb(
              state: _orbState,
              onTap: _cycleOrbState,
              isElder: isElder,
              size: 155.0,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: NuvinColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NuvinColors.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isVoiceConnected ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isVoiceConnected
                            ? (_orbState == OrbState.speaking
                                ? 'Nuvin is speaking (tap orb to barge in)'
                                : (_orbState == OrbState.thinking
                                    ? 'Thinking...'
                                    : (_orbState == OrbState.listening
                                        ? 'Listening...'
                                        : 'Voice Engine Connected')))
                            : 'Connecting to Voice WebSocket...',
                        style: TextStyle(
                          color: _isVoiceConnected ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _voiceTranscript.isNotEmpty
                        ? _voiceTranscript
                        : 'Tap the orb or select a prompt below to speak with Nuvin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: NuvinColors.text,
                      fontSize: isElder ? 17 : 14.5,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'TAP TO SPEAK',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: NuvinColors.mutedForeground,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _voicePromptChip('“How is my health today?”'),
                _voicePromptChip('“Remind me to take medicine”'),
                _voicePromptChip('“Who is my emergency contact?”'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _voicePromptChip(String prompt) {
    final cleanText = prompt.replaceAll('“', '').replaceAll('”', '');
    return InkWell(
      onTap: () => _sendVoiceTurn(cleanText),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: NuvinColors.secondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NuvinColors.border),
        ),
        child: Text(
          prompt,
          style: const TextStyle(
            color: NuvinColors.text,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _audioChoicePill({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? NuvinColors.secondary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? NuvinColors.primary : NuvinColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isActive ? NuvinColors.primary : NuvinColors.mutedForeground),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isActive ? NuvinColors.text : NuvinColors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openProfileSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF131E33),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: Color(0xFF28364F))),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF64738A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'YOUR ACCOUNT',
                              style: TextStyle(
                                color: Color(0xFF68C9D8),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Profile',
                              style: TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFF1F5F8),
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Color(0xFFC7D3E2),
                              size: 21,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Identity Row
                    Row(
                      children: [
                        const NuvinMark(size: 46),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _profile.displayName.isNotEmpty ? _profile.displayName : 'Nuvin member',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFF2F6FA),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _profile.email.isNotEmpty ? _profile.email : 'peeyush.panthari@gmail.com',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFFAAB7C9),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(height: 1, thickness: 1, color: Colors.white.withOpacity(0.08)),
                    const SizedBox(height: 18),

                    // Section label
                    const Text(
                      'PERSONAL SETUP',
                      style: TextStyle(
                        color: Color(0xFF8F9FB5),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 9),

                    // Profile Info Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.025),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Column(
                        children: [
                          _dataRow('Companion name', _profile.companionName),
                          Divider(height: 1, thickness: 1, color: Colors.white.withOpacity(0.07)),
                          _dataRow(
                            'Age for personalization',
                            _profile.isElder
                                ? 'Added privately (55+)'
                                : (_profile.ageBand != 'unspecified' ? 'Added privately' : 'Not shared'),
                          ),
                          Divider(height: 1, thickness: 1, color: Colors.white.withOpacity(0.07)),
                          _dataRow(
                            'Trusted contact',
                            _profile.emergencyContacts.isNotEmpty
                                ? _profile.emergencyContacts.first.displayName
                                : 'Not added',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 9),

                    // Action Tile 1: Edit personal setup
                    InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _openEditPersonalSetupSheet();
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 66),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.025),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF48CAE4).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.tune_rounded,
                                size: 19,
                                color: Color(0xFF70D7E4),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Text(
                                    'Edit personal setup',
                                    style: TextStyle(
                                      color: Color(0xFFEAF0F6),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    'Preferences and trusted contact',
                                    style: TextStyle(
                                      color: Color(0xFF8998AD),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: Color(0xFF8290A4),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),

                    // Action Tile 2: Memory Vault
                    InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _openVaultSheet();
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 66),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.025),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF48CAE4).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.bookmark_outline_rounded,
                                size: 19,
                                color: Color(0xFF70D7E4),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Memory Vault',
                                    style: TextStyle(
                                      color: Color(0xFFEAF0F6),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${_memories.length} saved ${_memories.length == 1 ? "memory" : "memories"}',
                                    style: const TextStyle(
                                      color: Color(0xFF8998AD),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: Color(0xFF8290A4),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, thickness: 1, color: Colors.white.withOpacity(0.07)),
                    const SizedBox(height: 13),

                    // Privacy footnote
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 15,
                          color: Color(0xFF48CAE4),
                        ),
                        SizedBox(width: 7),
                        Text(
                          'Personal setup and memories stay on this device.',
                          style: TextStyle(
                            color: Color(0xFF9CAFC1),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Sign out button
                    InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        widget.onSignOut?.call();
                      },
                      borderRadius: BorderRadius.circular(13),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE63946).withOpacity(0.09),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: const Color(0xFFE63946).withOpacity(0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.logout_rounded,
                              color: Color(0xFFF08A91),
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Sign out',
                              style: TextStyle(
                                color: Color(0xFFF08A91),
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _dataRow(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minHeight: 46),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9EADBF),
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFE6EDF4),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _openEditPersonalSetupSheet() {
    final nameCtrl = TextEditingController(text: _profile.companionName);
    final kinNameCtrl = TextEditingController(
      text: _profile.emergencyContacts.isNotEmpty
          ? _profile.emergencyContacts.first.displayName
          : '',
    );
    final kinPhoneCtrl = TextEditingController(
      text: _profile.emergencyContacts.isNotEmpty
          ? _profile.emergencyContacts.first.phoneE164
          : '',
    );
    bool isElder = _profile.isElder;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setEditState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF131E33),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(top: BorderSide(color: Color(0xFF28364F))),
                ),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFF64738A),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'CUSTOMIZE',
                                style: TextStyle(
                                  color: Color(0xFF68C9D8),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Personal Setup',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFF1F5F8),
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Color(0xFFC7D3E2)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Companion Name',
                        style: TextStyle(
                          color: Color(0xFF9EADBF),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. Nuvin or Saathi',
                          hintStyle: const TextStyle(color: Color(0xFF5D6E87)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.04),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF28364F)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF28364F)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Personalization Persona',
                        style: TextStyle(
                          color: Color(0xFF9EADBF),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setEditState(() => isElder = true),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                decoration: BoxDecoration(
                                  color: isElder
                                      ? const Color(0xFF48CAE4).withOpacity(0.18)
                                      : Colors.white.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isElder
                                        ? const Color(0xFF48CAE4)
                                        : const Color(0xFF28364F),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'Elder Support (55+)',
                                    style: TextStyle(
                                      color: isElder ? const Color(0xFF48CAE4) : const Color(0xFF9EADBF),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: () => setEditState(() => isElder = false),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                decoration: BoxDecoration(
                                  color: !isElder
                                      ? const Color(0xFF48CAE4).withOpacity(0.18)
                                      : Colors.white.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: !isElder
                                        ? const Color(0xFF48CAE4)
                                        : const Color(0xFF28364F),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'Companion Ear (20-50)',
                                    style: TextStyle(
                                      color: !isElder ? const Color(0xFF48CAE4) : const Color(0xFF9EADBF),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Trusted / Emergency Contact Name',
                        style: TextStyle(
                          color: Color(0xFF9EADBF),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: kinNameCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. Aarav Sharma (Son)',
                          hintStyle: const TextStyle(color: Color(0xFF5D6E87)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.04),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF28364F)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF28364F)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Trusted Contact Phone (E.164)',
                        style: TextStyle(
                          color: Color(0xFF9EADBF),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: kinPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: '+919876543211',
                          hintStyle: const TextStyle(color: Color(0xFF5D6E87)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.04),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF28364F)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF28364F)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      ElevatedButton(
                        onPressed: () {
                          final updatedCompanion = nameCtrl.text.trim().isNotEmpty
                              ? nameCtrl.text.trim()
                              : 'Nuvin';
                          final contactName = kinNameCtrl.text.trim();
                          final contactPhone = kinPhoneCtrl.text.trim();

                          List<EmergencyContact> updatedContacts = [];
                          if (contactName.isNotEmpty) {
                            updatedContacts.add(EmergencyContact(
                              id: 'ec-custom',
                              displayName: contactName,
                              relationship: 'Trusted Kin',
                              phoneE164: contactPhone.isNotEmpty ? contactPhone : '+919876543210',
                            ));
                          }

                          setState(() {
                            _profile = _profile.copyWith(
                              companionName: updatedCompanion,
                              persona: isElder ? 'elder' : 'ear',
                              ageBand: isElder ? '55-64' : '25-34',
                              emergencyContacts: updatedContacts,
                            );
                          });

                          Navigator.pop(context);
                          _showNotice('Personal setup updated.');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF48CAE4),
                          foregroundColor: const Color(0xFF0B132B),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Save Changes',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openVaultSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              decoration: const BoxDecoration(
                color: NuvinColors.card,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: NuvinColors.border)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: NuvinColors.mutedForeground.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('YOUR PRIVATE SPACE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: NuvinColors.mutedForeground)),
                  const Text('Memory Vault', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: NuvinColors.text)),
                  const SizedBox(height: 6),
                  const Text(
                    "You're in control. Memories stay on this device, and you can forget any of them at any time.",
                    style: TextStyle(fontSize: 13, color: NuvinColors.mutedForeground),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _memories.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final mem = _memories[index];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: NuvinColors.secondary,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: NuvinColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.bookmark, color: NuvinColors.accent, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(mem.text, style: const TextStyle(color: NuvinColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
                                        const SizedBox(height: 4),
                                        Text(mem.reason, style: const TextStyle(color: NuvinColors.mutedForeground, fontSize: 12)),
                                        const SizedBox(height: 2),
                                        Text(mem.savedAt, style: const TextStyle(color: NuvinColors.mutedForeground, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () {
                                    setSheetState(() {
                                      _forgetMemory(mem.id);
                                    });
                                  },
                                  icon: const Icon(Icons.delete_outline, size: 15, color: NuvinColors.dangerMuted),
                                  label: const Text('Forget this', style: TextStyle(color: NuvinColors.dangerMuted, fontSize: 12)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSosOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.85),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: NuvinColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: NuvinColors.destructive, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emergency_rounded, color: NuvinColors.destructive, size: 54),
              const SizedBox(height: 14),
              const Text('EMERGENCY SAFETY PREVIEW', style: TextStyle(color: NuvinColors.destructive, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              if (_sosActive) ...[
                Text(
                  '$_sosCount',
                  style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text('Dispatching siren & SMS alert to emergency contact...', textAlign: TextAlign.center, style: TextStyle(color: NuvinColors.mutedForeground, fontSize: 13)),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _cancelSos,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NuvinColors.secondary,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  ),
                  child: const Text('Cancel Alert', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ] else ...[
                const Text('Alert Dispatched (Preview Mode)', style: TextStyle(color: NuvinColors.success, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Live tracking link and siren sound simulated.', textAlign: TextAlign.center, style: TextStyle(color: NuvinColors.mutedForeground, fontSize: 13)),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => setState(() => _sosOpen = false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NuvinColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  ),
                  child: const Text('Dismiss', style: TextStyle(color: NuvinColors.primaryForeground, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
