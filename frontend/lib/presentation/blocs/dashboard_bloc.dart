import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../core/websocket/websocket_client.dart';
import '../../data/models/favour_models.dart';
import '../../data/repositories/friends_repository.dart';

// Events
abstract class DashboardEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class StartRealTimeUpdates extends DashboardEvent {
  final String token;
  StartRealTimeUpdates(this.token);
}

class StopRealTimeUpdates extends DashboardEvent {}

class LoadDashboardStats extends DashboardEvent {}

class CommitmentReceived extends DashboardEvent {
  final Map<String, dynamic> data;
  CommitmentReceived(this.data);
}

class AcceptCommitment extends DashboardEvent {
  final String commitmentId;
  AcceptCommitment(this.commitmentId);
}

class DenyCommitment extends DashboardEvent {
  final String commitmentId;
  DenyCommitment(this.commitmentId);
}

class DismissPendingAction extends DashboardEvent {
  final dynamic action;
  DismissPendingAction(this.action);
}

// States
class DashboardState extends Equatable {
  final double reciprocityScore;
  final List<dynamic> pendingActions;
  final List<dynamic> materialisticEntities;
  final List<dynamic> emotionalEntities;
  final ProfileStats? stats;
  final bool isConnected;
  final bool isLoadingStats;

  const DashboardState({
    this.reciprocityScore = 0.0,
    this.pendingActions = const [],
    this.materialisticEntities = const [],
    this.emotionalEntities = const [],
    this.stats,
    this.isConnected = false,
    this.isLoadingStats = false,
  });

  DashboardState copyWith({
    double? reciprocityScore,
    List<dynamic>? pendingActions,
    List<dynamic>? materialisticEntities,
    List<dynamic>? emotionalEntities,
    ProfileStats? stats,
    bool? isConnected,
    bool? isLoadingStats,
  }) {
    return DashboardState(
      reciprocityScore: reciprocityScore ?? this.reciprocityScore,
      pendingActions: pendingActions ?? this.pendingActions,
      materialisticEntities: materialisticEntities ?? this.materialisticEntities,
      emotionalEntities: emotionalEntities ?? this.emotionalEntities,
      stats: stats ?? this.stats,
      isConnected: isConnected ?? this.isConnected,
      isLoadingStats: isLoadingStats ?? this.isLoadingStats,
    );
  }

  @override
  List<Object?> get props => [
        reciprocityScore,
        pendingActions,
        materialisticEntities,
        emotionalEntities,
        stats,
        isConnected,
        isLoadingStats,
      ];
}

// BLoC
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final WebSocketClient webSocketClient;
  final FriendsRepository friendsRepository;
  StreamSubscription? _wsSubscription;

  DashboardBloc({
    required this.webSocketClient,
    required this.friendsRepository,
  }) : super(const DashboardState()) {
    
    on<LoadDashboardStats>((event, emit) async {
      print('DEBUG: LoadDashboardStats started');
      emit(state.copyWith(isLoadingStats: true));
      try {
        final data = await friendsRepository.getProfileStats();
        print('DEBUG: Profile stats data received: $data');
        emit(state.copyWith(
          stats: ProfileStats.fromJson(data),
          isLoadingStats: false,
          reciprocityScore: (data['reciprocity_score'] as num?)?.toDouble() ?? state.reciprocityScore,
        ));
      } catch (e) {
        print('DEBUG: Error in LoadDashboardStats: $e');
        emit(state.copyWith(isLoadingStats: false));
      }
    });

    on<StartRealTimeUpdates>((event, emit) async {
      await _wsSubscription?.cancel();
      _wsSubscription = webSocketClient.messages.listen((message) {
        add(CommitmentReceived(message));
      });
      
      emit(state.copyWith(isConnected: true));
      webSocketClient.connect(event.token);
      add(LoadDashboardStats());
    });

    on<CommitmentReceived>((event, emit) {
      final type = event.data['type'];
      final payload = event.data['data'];

      if (type == 'commitment_requested') {
        final newPending = List.from(state.pendingActions)..add(payload);
        emit(state.copyWith(pendingActions: newPending));
      } else if (type == 'commitment_accepted' || type == 'favour_created' || type == 'commitment_denied' || type == 'data_refresh') {
        // Trigger a full stats refresh for any major change
        add(LoadDashboardStats());
        
        if (type == 'commitment_accepted' || type == 'entity_rating_updated') {
          // Update reciprocity score if present in payload
          if (payload != null && payload['reciprocity_score'] != null) {
            emit(state.copyWith(reciprocityScore: (payload['reciprocity_score'] as num).toDouble()));
          }

          // Update entity lists if applicable
          if (payload != null && payload['entity_type'] != null) {
            final entityType = payload['entity_type'];
            if (entityType == 'MATERIALISTIC' || entityType == 'MATERIAL') {
              final newList = _updateEntityInList(state.materialisticEntities, payload);
              emit(state.copyWith(materialisticEntities: newList));
            } else if (entityType == 'EMOTIONAL') {
              final newList = _updateEntityInList(state.emotionalEntities, payload);
              emit(state.copyWith(emotionalEntities: newList));
            }
          }

          // Remove from pending if it was accepted
          if (type == 'commitment_accepted' && payload != null) {
            final newPending = List.from(state.pendingActions)
              ..removeWhere((a) => a['id'] == payload['id']);
            emit(state.copyWith(pendingActions: newPending));
          }
        }
      } else if (type == 'initial_data' && payload != null) {
        emit(state.copyWith(
          reciprocityScore: (payload['reciprocity_score'] as num?)?.toDouble() ?? state.reciprocityScore,
          materialisticEntities: payload['materialistic'] ?? state.materialisticEntities,
          emotionalEntities: payload['emotional'] ?? state.emotionalEntities,
        ));
      } else if (type == 'friend_request_received') {
        // Add to pending if it's a friend request
        final newPending = List.from(state.pendingActions)..add({
          'type': 'friend_request',
          'data': payload,
        });
        emit(state.copyWith(pendingActions: newPending));
      }
    });

    on<AcceptCommitment>((event, emit) async {
      try {
        await friendsRepository.dioClient.post('/commitments/${event.commitmentId}/accept');
        // The real-time update from backend will handle data refresh
        final newPending = List.from(state.pendingActions)
          ..removeWhere((a) => (a['id'] ?? a['data']?['id']) == event.commitmentId);
        emit(state.copyWith(pendingActions: newPending));
      } catch (e) {
        print('DEBUG: Error accepting commitment: $e');
      }
    });

    on<DenyCommitment>((event, emit) async {
      try {
        await friendsRepository.dioClient.post('/commitments/${event.commitmentId}/deny');
        final newPending = List.from(state.pendingActions)
          ..removeWhere((a) => (a['id'] ?? a['data']?['id']) == event.commitmentId);
        emit(state.copyWith(pendingActions: newPending));
      } catch (e) {
        print('DEBUG: Error denying commitment: $e');
      }
    });

    on<DismissPendingAction>((event, emit) {
      final newPending = List.from(state.pendingActions)..removeWhere((a) {
        if (a is Map && event.action is Map) {
          if (a['type'] == 'friend_request' && event.action['type'] == 'friend_request') {
             return a['data']?['rel_id'] == event.action['data']?['rel_id'];
          } else {
             final id1 = a['id'] ?? a['data']?['id'];
             final id2 = event.action['id'] ?? event.action['data']?['id'];
             return id1 == id2 && id1 != null;
          }
        }
        return a == event.action;
      });
      emit(state.copyWith(pendingActions: newPending));
    });

    on<StopRealTimeUpdates>((event, emit) {
      webSocketClient.disconnect();
      _wsSubscription?.cancel();
      emit(state.copyWith(isConnected: false));
    });
  }

  List<dynamic> _updateEntityInList(List<dynamic> list, dynamic payload) {
    final newList = List.from(list);
    final index = newList.indexWhere((e) => e['id'] == payload['entity_id'] || e['name'] == payload['entity_name']);
    
    final entityData = {
      'id': payload['entity_id'],
      'name': payload['entity_name'],
      'reliability': payload['reliability_score'] ?? payload['rating'] ?? 0,
    };

    if (index != -1) {
      newList[index] = entityData;
    } else {
      newList.add(entityData);
    }
    return newList;
  }

  @override
  Future<void> close() {
    _wsSubscription?.cancel();
    return super.close();
  }
}
