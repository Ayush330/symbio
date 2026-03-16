import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/repositories/auth_repository.dart';

// Events
abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoginRequested extends AuthEvent {
  final String email;
  final String password;
  LoginRequested(this.email, this.password);
  @override
  List<Object?> get props => [email, password];
}

class SignupRequested extends AuthEvent {
  final String email;
  final String password;
  final String name;
  final String phone;
  SignupRequested(this.email, this.password, this.name, {this.phone = ''});
  @override
  List<Object?> get props => [email, password, name, phone];
}

class LogoutRequested extends AuthEvent {}

class AuthCheckRequested extends AuthEvent {}

// States
abstract class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}
class Authenticated extends AuthState {
  final String token;
  Authenticated(this.token);
  @override
  List<Object?> get props => [token];
}
class Unauthenticated extends AuthState {}
class AuthFailure extends AuthState {
  final String message;
  AuthFailure(this.message);
  @override
  List<Object?> get props => [message];
}

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository authRepository;

  AuthBloc({required this.authRepository}) : super(AuthInitial()) {
    on<AuthCheckRequested>((event, emit) async {
      final isLoggedIn = await authRepository.isLoggedIn();
      if (isLoggedIn) {
        final token = await authRepository.getToken();
        await authRepository.fetchAndCacheFavourConfig();
        emit(Authenticated(token ?? '')); 
      } else {
        emit(Unauthenticated());
      }
    });

    on<LoginRequested>((event, emit) async {
      emit(AuthLoading());
      try {
        final token = await authRepository.login(event.email, event.password);
        if (token != null) {
          emit(Authenticated(token));
        } else {
          emit(AuthFailure('Login failed'));
        }
      } catch (e) {
        emit(AuthFailure(e.toString()));
      }
    });

    on<SignupRequested>((event, emit) async {
      emit(AuthLoading());
      try {
        await authRepository.signup(event.email, event.password, event.name, phone: event.phone);
        add(LoginRequested(event.email, event.password));
      } catch (e) {
        emit(AuthFailure(e.toString()));
      }
    });

    on<LogoutRequested>((event, emit) async {
      await authRepository.logout();
      emit(Unauthenticated());
    });
  }
}
