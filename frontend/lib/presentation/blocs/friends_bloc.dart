import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../core/websocket/websocket_client.dart';
import '../../data/repositories/friends_repository.dart';
import 'dart:async';

// Events
abstract class FriendsEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadFriends extends FriendsEvent {}

class AcceptFriendRequest extends FriendsEvent {
  final String relId;
  AcceptFriendRequest(this.relId);
  @override
  List<Object?> get props => [relId];
}

class RejectFriendRequest extends FriendsEvent {
  final String relId;
  RejectFriendRequest(this.relId);
  @override
  List<Object?> get props => [relId];
}

class LookupUser extends FriendsEvent {
  final String email;
  LookupUser(this.email);
  @override
  List<Object?> get props => [email];
}

class LoadFriendActivity extends FriendsEvent {
  final String friendId;
  LoadFriendActivity(this.friendId);
  @override
  List<Object?> get props => [friendId];
}

// States
abstract class FriendsState extends Equatable {
  @override
  List<Object?> get props => [];
}

class FriendsInitial extends FriendsState {}
class FriendsLoading extends FriendsState {}

class FriendsLoaded extends FriendsState {
  final List<dynamic> friends;
  final List<dynamic> requests;
  FriendsLoaded(this.friends, this.requests);
  @override
  List<Object?> get props => [friends, requests];
}

class FriendsEmpty extends FriendsState {}

class FriendsError extends FriendsState {
  final String message;
  FriendsError(this.message);
  @override
  List<Object?> get props => [message];
}

class UserLookupResult extends FriendsState {
  final bool exists;
  final String? userId;
  final String? name;
  UserLookupResult({required this.exists, this.userId, this.name});
  @override
  List<Object?> get props => [exists, userId, name];
}

class FriendActivityLoaded extends FriendsState {
  final List<dynamic> activities;
  FriendActivityLoaded(this.activities);
  @override
  List<Object?> get props => [activities];
}

// BLoC
class FriendsBloc extends Bloc<FriendsEvent, FriendsState> {
  final FriendsRepository friendsRepository;
  final WebSocketClient webSocketClient;
  StreamSubscription? _wsSubscription;

  FriendsBloc({
    required this.friendsRepository,
    required this.webSocketClient,
  }) : super(FriendsInitial()) {
    // Listen for real-time synchronization messages
    _wsSubscription = webSocketClient.messages.listen((message) {
      final type = message['type'];
      if (type == 'friend_request_received' || 
          type == 'friend_request_accepted' || 
          type == 'favour_created' ||
          type == 'commitment_accepted' ||
          type == 'commitment_requested' ||
          type == 'data_refresh') {
        add(LoadFriends());
      }
    });

    on<LoadFriends>((event, emit) async {
      if (state is! FriendsLoaded) {
        emit(FriendsLoading());
      }
      try {
        final results = await Future.wait([
          friendsRepository.getFriends(),
          friendsRepository.getFriendRequests(),
        ]);
        
        final friends = results[0];
        final requests = results[1];

        if (friends.isEmpty && requests.isEmpty) {
          emit(FriendsEmpty());
        } else {
          emit(FriendsLoaded(friends, requests));
        }
      } catch (e) {
        emit(FriendsError(e.toString()));
      }
    });

    on<AcceptFriendRequest>((event, emit) async {
      try {
        await friendsRepository.acceptFriendRequest(event.relId);
        add(LoadFriends()); // Refresh lists
      } catch (e) {
        emit(FriendsError(e.toString()));
      }
    });

    on<RejectFriendRequest>((event, emit) async {
      try {
        await friendsRepository.rejectFriendRequest(event.relId);
        add(LoadFriends()); // Refresh lists
      } catch (e) {
        emit(FriendsError(e.toString()));
      }
    });

    on<LookupUser>((event, emit) async {
      emit(FriendsLoading());
      try {
        final result = await friendsRepository.lookupUser(event.email);
        emit(UserLookupResult(
          exists: result['exists'] ?? false,
          userId: result['user_id'],
          name: result['name'],
        ));
      } catch (e) {
        emit(FriendsError(e.toString()));
      }
    });

    on<LoadFriendActivity>((event, emit) async {
      emit(FriendsLoading());
      try {
        final activities = await friendsRepository.getFriendActivity(event.friendId);
        emit(FriendActivityLoaded(activities));
      } catch (e) {
        emit(FriendsError(e.toString()));
      }
    });
  }

  @override
  Future<void> close() {
    _wsSubscription?.cancel();
    return super.close();
  }
}
