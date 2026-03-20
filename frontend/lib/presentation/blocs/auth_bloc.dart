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
  final String gender;
  SignupRequested(this.email, this.password, this.name, {this.phone = '', this.gender = ''});
  @override
  List<Object?> get props => [email, password, name, phone, gender];
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
  final String userName;
  Authenticated(this.token, {this.userName = ''});
  @override
  List<Object?> get props => [token, userName];
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
        final name = await authRepository.getUserName();
        
        // Emit IMMEDIATELY so the splash screen goes away and we don't block LogoutRequested
        emit(Authenticated(token ?? '', userName: name ?? ''));
        
        // Fetch config in background after emitting initial state
        try {
          await authRepository.fetchAndCacheFavourConfig();
        } catch (e) {
          // Errors are handled by the repository (logging) and Dio interceptor (401 logout)
        }
      } else {
        emit(Unauthenticated());
      }
    });

    on<LoginRequested>((event, emit) async {
      emit(AuthLoading());
      try {
        final token = await authRepository.login(event.email, event.password);
        final name = await authRepository.getUserName();
        if (token != null) {
          emit(Authenticated(token, userName: name ?? ''));
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
        await authRepository.signup(event.email, event.password, event.name, phone: event.phone, gender: event.gender);
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
