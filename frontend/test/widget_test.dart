// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:symbiosis_app/main.dart';
import 'package:symbiosis_app/core/api/dio_client.dart';
import 'package:symbiosis_app/core/websocket/websocket_client.dart';
import 'package:symbiosis_app/data/repositories/auth_repository.dart';
import 'package:symbiosis_app/data/repositories/commitment_repository.dart';
import 'package:symbiosis_app/data/repositories/friends_repository.dart';
import 'package:symbiosis_app/presentation/blocs/auth_bloc.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    final dioClient = DioClient(baseUrl: 'http://localhost:8080');
    final authRepository = AuthRepository(dioClient: dioClient);
    final webSocketClient = WebSocketClient(url: 'ws://localhost:8080/ws');
    final commitmentRepository = CommitmentRepository(webSocketClient: webSocketClient);
    final friendsRepository = FriendsRepository(dioClient: dioClient);
    final authBloc = AuthBloc(authRepository: authRepository);

    await tester.pumpWidget(SymbioApp(
      authBloc: authBloc,
      authRepository: authRepository,
      commitmentRepository: commitmentRepository,
      webSocketClient: webSocketClient,
      friendsRepository: friendsRepository,
      dioClient: dioClient,
    ));

    expect(find.text('SYMBIO'), findsNothing); // Starts with login
    expect(find.text('Welcome Back'), findsOneWidget);
  });
}
