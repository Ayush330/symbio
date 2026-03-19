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
  
  String? _lastToken;
  
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  final int _maxReconnectDelay = 30; // Max delay in seconds

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  WebSocketClient({required this.url});

  void connect(String token) {
    if (_isConnected && _lastToken == token) {
      debugPrint('WS: Already connected with same token, skipping redundant connect');
      return;
    }
    
    debugPrint('WS: Connecting to $url...');
    disconnect(); // Clean up any existing connection/timers
    
    _lastToken = token;
    _reconnectTimer?.cancel();
    final socketUrl = Uri.parse('$url?token=$token');
    
    try {
      _channel = WebSocketChannel.connect(socketUrl);
      _isConnected = true; // Optimistically set, will be updated on messages
      
      _subscription = _channel!.stream.listen(
        (message) {
          _reconnectAttempts = 0;
          try {
            final data = jsonDecode(message as String);
            _messageController.add(data as Map<String, dynamic>);
          } catch (e) {
            debugPrint('Error decoding WS message: $e');
          }
        },
        onDone: () {
          debugPrint('WS: Connection closed by server');
          _handleConnectionLost();
        },
        onError: (error) {
          debugPrint('WS: Connection error: $error');
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
    if (!_isConnected && _reconnectAttempts > 0 && _reconnectTimer?.isActive == true) return; 
    
    _isConnected = false;
    _subscription?.cancel();
    _heartbeatTimer?.cancel();
    
    // Exponential backoff
    final delay = Duration(seconds: (_reconnectAttempts + 1).clamp(1, _maxReconnectDelay));
    debugPrint('WS connection lost. Reconnecting in ${delay.inSeconds}s... (Attempt ${_reconnectAttempts + 1})');
    
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      if (_lastToken != null) {
        connect(_lastToken!);
      }
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
