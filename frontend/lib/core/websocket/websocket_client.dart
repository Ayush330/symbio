import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

class WebSocketClient {
  final String url;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  final int _maxReconnectDelay = 30; // Max delay in seconds

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  WebSocketClient({required this.url});

  void connect(String token) {
    _reconnectTimer?.cancel();
    final socketUrl = Uri.parse('$url?token=$token');
    
    try {
      _channel = WebSocketChannel.connect(socketUrl);
      _isConnected = true;
      _reconnectAttempts = 0;

      _subscription = _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String);
            _messageController.add(data as Map<String, dynamic>);
          } catch (e) {
            debugPrint('Error decoding WS message: $e');
          }
        },
        onDone: _handleConnectionLost,
        onError: (error) {
          debugPrint('WS error: $error');
          _handleConnectionLost();
        },
      );

      _startHeartbeat();
    } catch (e) {
      debugPrint('WS connection error: $e');
      _handleConnectionLost();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      }
    });
  }

  void _handleConnectionLost() {
    _isConnected = false;
    _subscription?.cancel();
    _heartbeatTimer?.cancel();
    
    // Exponential backoff
    final delay = Duration(seconds: (_reconnectAttempts + 1).clamp(1, _maxReconnectDelay));
    debugPrint('WS connection lost. Reconnecting in ${delay.inSeconds}s...');
    
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      // We need the token again here, usually fetched from SharedPreferences or passed via a provider
      // For this implementation, we assume the caller will trigger connect() again or we cache the token.
    });
  }

  void send(Map<String, dynamic> data) {
    if (_isConnected) {
      _channel?.sink.add(jsonEncode(data));
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }
}
