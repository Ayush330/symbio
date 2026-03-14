import '../../core/websocket/websocket_client.dart';

class CommitmentRepository {
  final WebSocketClient webSocketClient;

  CommitmentRepository({required this.webSocketClient});

  Future<void> requestCommitment({
    required String targetUserId,
    required String entityType,
    required int rating,
    String? entityId,
    String? entityName,
  }) async {
    webSocketClient.send({
      'type': 'request_commitment',
      'data': {
        'target_user_id': targetUserId,
        'entity_type': entityType,
        'rating': rating,
        'entity_id': entityId,
        'entity_name': entityName,
      }
    });
  }

  Future<void> acceptCommitment(String id) async {
    webSocketClient.send({
      'type': 'accept_commitment',
      'data': {'commitment_id': id}
    });
  }

  Future<void> denyCommitment(String id) async {
    webSocketClient.send({
      'type': 'deny_commitment',
      'data': {'commitment_id': id}
    });
  }
}
