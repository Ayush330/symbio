import 'dart:convert';
import '../../core/api/dio_client.dart';

class FriendsRepository {
  final DioClient dioClient;

  FriendsRepository({required this.dioClient});

  Future<List<dynamic>> getFriends() async {
    final response = await dioClient.get('/friends');
    return response.data as List<dynamic>;
  }

  Future<List<dynamic>> getFriendActivity(String friendId) async {
    final response = await dioClient.get('/friends/$friendId/activity');
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> lookupUser(String email) async {
    final response = await dioClient.get('/user/lookup', queryParameters: {'email': email});
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getEntities(String type) async {
    final response = await dioClient.get('/entities', queryParameters: {'type': type});
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createEntity(String name, String type, double rating) async {
    final response = await dioClient.post('/entities', data: {
      'name': name,
      'type': type,
      'rating': rating,
    });
    
    // Sometimes Dio returns the raw JSON string if Content-Type parsing fails
    var data = response.data;
    if (data is String) {
      data = jsonDecode(data);
    }
    
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<dynamic>> getFriendRequests() async {
    final response = await dioClient.get('/friends/requests');
    return response.data as List<dynamic>;
  }

  Future<void> sendFriendRequest(String targetId) async {
    await dioClient.post('/friends/request', data: {'target_id': targetId});
  }

  Future<void> acceptFriendRequest(String relId) async {
    await dioClient.post('/friends/accept', data: {'rel_id': relId});
  }

  Future<void> rejectFriendRequest(String relId) async {
    await dioClient.post('/friends/reject', data: {'rel_id': relId});
  }
}
