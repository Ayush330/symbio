import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/api/dio_client.dart';
import 'core/websocket/websocket_client.dart';
import 'core/theme/app_theme.dart';
import 'core/services/notification_service.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/commitment_repository.dart';
import 'data/repositories/friends_repository.dart';
import 'presentation/blocs/auth_bloc.dart';
import 'presentation/blocs/dashboard_bloc.dart';
import 'presentation/blocs/friends_bloc.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/screens/friends_screen.dart';
import 'presentation/screens/activity_tab.dart';
import 'presentation/screens/animated_splash_screen.dart';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  await Firebase.initializeApp();

  final String baseUrl;
  final String wsUrl;

  if (kReleaseMode) {
    // Production (APK/Release Build)
    baseUrl = 'https://kizuna.anandayush.in';
    wsUrl = 'wss://kizuna.anandayush.in/ws';
  } else {
    // Development (Debug Mode / Run)
    baseUrl = 'http://192.168.1.6:8080';
    wsUrl = 'ws://192.168.1.6:8080/ws';
  }

  final dioClient = DioClient(baseUrl: baseUrl);
  final authRepository = AuthRepository(dioClient: dioClient);
  
  // Pre-load token from storage into DioClient to avoid initial request delays
  final initialToken = await authRepository.getToken();
  dioClient.setToken(initialToken);

  final webSocketClient = WebSocketClient(url: wsUrl);
  final commitmentRepository = CommitmentRepository(webSocketClient: webSocketClient);
  final friendsRepository = FriendsRepository(dioClient: dioClient);

  // Instantiate AuthBloc globally so DioClient can trigger logouts on 401
  final authBloc = AuthBloc(authRepository: authRepository)..add(AuthCheckRequested());
  
  dioClient.onUnauthorized = () {
    print('DEBUG: onUnauthorized triggered, adding LogoutRequested');
    authBloc.add(LogoutRequested());
    dioClient.setToken(null); // Clear token from client immediately
  };

  // Initialize Notifications
  final notificationService = NotificationService(authRepository: authRepository);
  notificationService.initialize(); // Run in background

  runApp(KizunaApp(
    authBloc: authBloc,
    authRepository: authRepository,
    commitmentRepository: commitmentRepository,
    webSocketClient: webSocketClient,
    friendsRepository: friendsRepository,
    dioClient: dioClient,
  ));

  // Fallback: Remove splash anyway after 5s if it's stuck
  Future.delayed(const Duration(seconds: 5), () {
    print('DEBUG: Fallback native splash removal triggered');
    FlutterNativeSplash.remove();
  });
}

class KizunaApp extends StatelessWidget {
  final AuthBloc authBloc;
  final AuthRepository authRepository;
  final CommitmentRepository commitmentRepository;
  final WebSocketClient webSocketClient;
  final FriendsRepository friendsRepository;
  final DioClient dioClient;

  const KizunaApp({
    super.key,
    required this.authBloc,
    required this.authRepository,
    required this.commitmentRepository,
    required this.webSocketClient,
    required this.friendsRepository,
    required this.dioClient,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: authRepository),
        RepositoryProvider.value(value: commitmentRepository),
        RepositoryProvider.value(value: friendsRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: authBloc),
          BlocProvider(
            create: (context) => DashboardBloc(
              webSocketClient: webSocketClient,
              friendsRepository: friendsRepository,
            ),
          ),
          BlocProvider(
            create: (context) => FriendsBloc(
              friendsRepository: friendsRepository,
              webSocketClient: webSocketClient,
            ),
          ),
        ],
        child: BlocListener<AuthBloc, AuthState>(
          listener: (context, state) {
            if (state is! AuthInitial) {
              FlutterNativeSplash.remove();
            }
            if (state is Authenticated) {
              dioClient.setToken(state.token);
              FirebaseMessaging.instance.getToken().then((token) {
                if (token != null) {
                  context.read<AuthRepository>().updateFCMToken(token);
                }
              });
            } else if (state is Unauthenticated) {
              dioClient.setToken(null);
            }
          },
          child: MaterialApp(
            title: 'Kizuna',
            debugShowCheckedModeBanner: false,
            theme: KizunaTheme.darkTheme,
            home: BlocListener<AuthBloc, AuthState>(
              listener: (context, state) {
                if (state is Authenticated && state.token.isNotEmpty) {
                  context.read<DashboardBloc>().add(StartRealTimeUpdates(state.token));
                }
              },
              child: BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  if (state is Authenticated) {
                    return const KizunaHome();
                  }
                  if (state is AuthInitial) {
                    return AnimatedSplashScreen(
                      onInitializationComplete: () {},
                    );
                  }
                  return const LoginScreen();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Root widget with bottom navigation
class KizunaHome extends StatefulWidget {
  const KizunaHome({super.key});

  @override
  State<KizunaHome> createState() => _KizunaHomeState();
}

class _KizunaHomeState extends State<KizunaHome> {
  @override
  void initState() {
    super.initState();
    // Ensure data is loaded on startup if already authenticated
    final authState = context.read<AuthBloc>().state;
    if (authState is Authenticated) {
      context.read<DashboardBloc>().add(LoadDashboardStats());
      context.read<FriendsBloc>().add(LoadFriends());
      context.read<DashboardBloc>().add(StartRealTimeUpdates(authState.token));
    }
  }

  int _currentIndex = 0;

  final _screens = [
    KizunaDashboard(),
    FriendsScreen(),
    ActivityTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BlocBuilder<FriendsBloc, FriendsState>(
      builder: (context, state) {
        int requestCount = 0;
        if (state is FriendsLoaded) {
          requestCount = state.requests.length;
        }

        return Container(
          decoration: const BoxDecoration(
            color: KizunaTheme.surfaceGlass,
            border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: KizunaTheme.primaryBlue,
            unselectedItemColor: Colors.white24,
            selectedLabelStyle: const TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w900),
            unselectedLabelStyle: const TextStyle(fontSize: 10, letterSpacing: 1.5),
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined),
                activeIcon: Icon(Icons.dashboard),
                label: 'PROFILE',
              ),
              BottomNavigationBarItem(
                icon: Badge(
                  label: Text(requestCount.toString()),
                  isLabelVisible: requestCount > 0,
                  backgroundColor: KizunaTheme.accentCyan,
                  textColor: Colors.black,
                  child: const Icon(Icons.people_outline),
                ),
                activeIcon: Badge(
                  label: Text(requestCount.toString()),
                  isLabelVisible: requestCount > 0,
                  backgroundColor: KizunaTheme.accentCyan,
                  textColor: Colors.black,
                  child: const Icon(Icons.people),
                ),
                label: 'FRIENDS',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.bar_chart_outlined),
                activeIcon: Icon(Icons.bar_chart),
                label: 'ACTIVITY',
              ),
            ],
          ),
        );
      },
      ),
    );
  }
}
