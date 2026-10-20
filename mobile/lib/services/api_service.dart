import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiConfig {
  static String get baseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  static String get wsBaseUrl {
    if (kIsWeb) return 'ws://127.0.0.1:8000';
    if (Platform.isAndroid) return 'ws://10.0.2.2:8000';
    return 'ws://127.0.0.1:8000';
  }
}

class ChatResponse {
  final String sessionId;
  final String spokenResponse;
  final Map<String, dynamic>? openUiCard;
  final String? actionTriggered;
  final Map<String, dynamic>? actionPayload;
  final double ttsRate;
  final int vadPauseToleranceMs;
  final bool isSafe;

  ChatResponse({
    required this.sessionId,
    required this.spokenResponse,
    this.openUiCard,
    this.actionTriggered,
    this.actionPayload,
    required this.ttsRate,
    required this.vadPauseToleranceMs,
    required this.isSafe,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    final guard = json['guardrail_decision'] as Map<String, dynamic>?;
    return ChatResponse(
      sessionId: json['session_id'] ?? '',
      spokenResponse: json['spoken_response'] ?? '',
      openUiCard: json['open_ui_card'] != null ? Map<String, dynamic>.from(json['open_ui_card']) : null,
      actionTriggered: json['action_triggered'],
      actionPayload: json['action_payload'] != null ? Map<String, dynamic>.from(json['action_payload']) : null,
      ttsRate: (json['tts_rate'] as num?)?.toDouble() ?? 1.0,
      vadPauseToleranceMs: (json['vad_pause_tolerance_ms'] as num?)?.toInt() ?? 1500,
      isSafe: guard != null ? (guard['is_safe'] ?? true) : true,
    );
  }
}

class ApiService {
  static final http.Client _client = http.Client();

  /// Send chat message to backend LangChain + Trust Plane agent
  static Future<ChatResponse> sendChatMessage({
    required String userId,
    required String message,
    String? locale,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/agent/chat');
    try {
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'message': message,
          if (locale != null) 'locale': locale,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return ChatResponse.fromJson(data);
      } else {
        throw Exception('Server error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Error calling sendChatMessage: $e');
      rethrow;
    }
  }

  /// Connect to Voice WebSocket
  static WebSocketChannel connectVoiceStream(String userId) {
    final wsUrl = Uri.parse('${ApiConfig.wsBaseUrl}/api/v1/voice/stream/$userId');
    return WebSocketChannel.connect(wsUrl);
  }
}
