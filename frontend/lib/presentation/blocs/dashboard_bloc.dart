import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../core/websocket/websocket_client.dart';

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

class CommitmentReceived extends DashboardEvent {
  final Map<String, dynamic> data;
  CommitmentReceived(this.data);
}

// States
class DashboardState extends Equatable {
  final double reciprocityScore;
  final List<dynamic> pendingActions;
  final List<dynamic> materialisticEntities;
  final List<dynamic> emotionalEntities;
  final bool isConnected;

  const DashboardState({
    this.reciprocityScore = 0.0,
    this.pendingActions = const [],
    this.materialisticEntities = const [],
    this.emotionalEntities = const [],
    this.isConnected = false,
  });

  DashboardState copyWith({
    double? reciprocityScore,
    List<dynamic>? pendingActions,
    List<dynamic>? materialisticEntities,
    List<dynamic>? emotionalEntities,
    bool? isConnected,
  }) {
    return DashboardState(
      reciprocityScore: reciprocityScore ?? this.reciprocityScore,
      pendingActions: pendingActions ?? this.pendingActions,
      materialisticEntities: materialisticEntities ?? this.materialisticEntities,
      emotionalEntities: emotionalEntities ?? this.emotionalEntities,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  @override
  List<Object?> get props => [
        reciprocityScore,
        pendingActions,
        materialisticEntities,
        emotionalEntities,
        isConnected,
      ];
}

// BLoC
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final WebSocketClient webSocketClient;
  StreamSubscription? _wsSubscription;

  DashboardBloc({required this.webSocketClient}) : super(const DashboardState()) {
    on<StartRealTimeUpdates>((event, emit) {
      webSocketClient.connect(event.token);
      _wsSubscription?.cancel();
      _wsSubscription = webSocketClient.messages.listen((message) {
        add(CommitmentReceived(message));
      });
      emit(state.copyWith(isConnected: true));
    });

    on<CommitmentReceived>((event, emit) {
      final type = event.data['type'];
      final payload = event.data['data'];

      if (type == 'commitment_requested') {
        final newPending = List.from(state.pendingActions)..add(payload);
        emit(state.copyWith(pendingActions: newPending));
      } else if (type == 'commitment_accepted' || type == 'entity_rating_updated') {
        // Update reciprocity score if present
        if (payload['reciprocity_score'] != null) {
          emit(state.copyWith(reciprocityScore: (payload['reciprocity_score'] as num).toDouble()));
        }

        // Update entity lists
        final entityType = payload['entity_type'];
        if (entityType != null) {
          if (entityType == 'MATERIALISTIC' || entityType == 'MATERIAL') {
            final newList = _updateEntityInList(state.materialisticEntities, payload);
            emit(state.copyWith(materialisticEntities: newList));
          } else if (entityType == 'EMOTIONAL') {
            final newList = _updateEntityInList(state.emotionalEntities, payload);
            emit(state.copyWith(emotionalEntities: newList));
          }
        }

        // Remove from pending if it was accepted
        if (type == 'commitment_accepted') {
          final newPending = List.from(state.pendingActions)
            ..removeWhere((a) => a['id'] == payload['id']);
          emit(state.copyWith(pendingActions: newPending));
        }
      } else if (type == 'initial_data') {
        // Handle bulk data if backend sends it on connect
        emit(state.copyWith(
          reciprocityScore: (payload['reciprocity_score'] as num?)?.toDouble() ?? state.reciprocityScore,
          materialisticEntities: payload['materialistic'] ?? state.materialisticEntities,
          emotionalEntities: payload['emotional'] ?? state.emotionalEntities,
        ));
      }
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
