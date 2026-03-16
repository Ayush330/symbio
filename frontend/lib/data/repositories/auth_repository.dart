import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/dio_client.dart';

class AuthRepository {
  final DioClient dioClient;

  AuthRepository({required this.dioClient});

  Future<String?> login(String email, String password) async {
    try {
      final response = await dioClient.post('/login', data: {
        'email': email,
        'password': password,
      });
      
      final token = response.data['token'];
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);
        await fetchAndCacheFavourConfig();
        return token;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signup(String email, String password, String name, {String phone = ''}) async {
    try {
      await dioClient.post('/signup', data: {
        'email': email,
        'password': password,
        'name': name,
        'phone': phone,
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('jwt_token');
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }
  Future<void> forgotPassword(String email) async {
    try {
      await dioClient.post('/forgot-password', data: {'email': email});
    } catch (e) {
      rethrow;
    }
  }

  Future<void> resetPassword(String token, String newPassword) async {
    try {
      await dioClient.post('/reset-password', data: {
        'token': token,
        'password': newPassword,
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateFCMToken(String token) async {
    try {
      await dioClient.post('/user/fcm-token', data: {'token': token});
    } catch (e) {
      // Background task, maybe just log it
      print('FCM Token Update error: $e');
    }
  }

  Future<void> fetchAndCacheFavourConfig() async {
    try {
      final response = await dioClient.get('/favour/config');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('favour_config', jsonEncode(response.data));
    } catch (e) {
      print('Favour config update error: $e');
    }
  }

  Future<Map<String, int>> getFavourConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configStr = prefs.getString('favour_config');
    if (configStr != null) {
      final Map<String, dynamic> decoded = jsonDecode(configStr);
      return decoded.map((key, value) => MapEntry(key, value as int));
    }
    return {};
  }
}
