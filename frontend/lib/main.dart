import 'package:flutter/material.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  const baseUrl = 'https://symbio.anandayush.in';
  const wsUrl = 'wss://symbio.anandayush.in/ws';

  final dioClient = DioClient(baseUrl: baseUrl);
  final authRepository = AuthRepository(dioClient: dioClient);
  final webSocketClient = WebSocketClient(url: wsUrl);
  final commitmentRepository = CommitmentRepository(webSocketClient: webSocketClient);
  final friendsRepository = FriendsRepository(dioClient: dioClient);

  // Initialize Notifications
  final notificationService = NotificationService(authRepository: authRepository);
  notificationService.initialize(); // Run in background

  runApp(SymbioApp(
    authRepository: authRepository,
    commitmentRepository: commitmentRepository,
    webSocketClient: webSocketClient,
    friendsRepository: friendsRepository,
  ));
}

class SymbioApp extends StatelessWidget {
  final AuthRepository authRepository;
  final CommitmentRepository commitmentRepository;
  final WebSocketClient webSocketClient;
  final FriendsRepository friendsRepository;

  const SymbioApp({
    super.key,
    required this.authRepository,
    required this.commitmentRepository,
    required this.webSocketClient,
    required this.friendsRepository,
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
          BlocProvider(
            create: (context) => AuthBloc(authRepository: authRepository)..add(AuthCheckRequested()),
          ),
          BlocProvider(
            create: (context) => DashboardBloc(webSocketClient: webSocketClient),
          ),
          BlocProvider(
            create: (context) => FriendsBloc(friendsRepository: friendsRepository),
          ),
        ],
        child: BlocListener<AuthBloc, AuthState>(
          listener: (context, state) {
            if (state is Authenticated) {
              FirebaseMessaging.instance.getToken().then((token) {
                if (token != null) {
                  context.read<AuthRepository>().updateFCMToken(token);
                }
              });
            }
          },
          child: MaterialApp(
            title: 'Symbio',
            debugShowCheckedModeBanner: false,
            theme: SymbioTheme.darkTheme,
            home: BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                if (state is Authenticated) {
                  if (state.token.isNotEmpty) {
                    context.read<DashboardBloc>().add(StartRealTimeUpdates(state.token));
                  }
                  return const SymbioHome();
                }

              if (state is AuthInitial) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              return const LoginScreen();
            },
          ),
        ),
      ),
    ),
  );
}
}

/// Root widget with bottom navigation
class SymbioHome extends StatefulWidget {
  const SymbioHome({super.key});

  @override
  State<SymbioHome> createState() => _SymbioHomeState();
}

class _SymbioHomeState extends State<SymbioHome> {
  int _currentIndex = 0;

  final _screens = const [
    SymbiosisDashboard(),
    FriendsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: SymbioTheme.surfaceGlass,
          border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: SymbioTheme.primaryBlue,
          unselectedItemColor: Colors.white24,
          selectedLabelStyle: const TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w900),
          unselectedLabelStyle: const TextStyle(fontSize: 10, letterSpacing: 1.5),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'DASHBOARD',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline),
              activeIcon: Icon(Icons.people),
              label: 'FRIENDS',
            ),
          ],
        ),
      ),
    );
  }
}
