import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:littlenet_native/api.dart';
import 'package:littlenet_native/app/theme.dart';
import 'package:littlenet_native/core/auth/auth_state.dart';
import 'package:littlenet_native/core/models/user.dart';
import 'package:littlenet_native/core/theme/colors.dart';
import 'package:littlenet_native/features/quiz/quiz_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async => null,
    );
  });

  testWidgets('answer persistence failure stays on question and is readable',
      (tester) async {
    final client = ApiClient(
      baseUrl: 'https://example.test',
      httpClient: MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            '{"ok":true,"required":true,"reason":"onboarding",'
            '"quizzes":[{"quiz_id":101,"category":"Digital Safety",'
            '"question":"What should you do?",'
            '"options":["Tell a trusted adult","Share it","Ignore it","Post it"]}]}',
            200,
          );
        }
        return http.Response('{"error":"persistence_failed"}', 500);
      }),
    );
    final auth = AuthState(apiClient: client)
      ..setAuthenticated(
        const User(
          userId: 15,
          username: 'saigowda',
          fullName: 'Sai Gowda',
          role: 'CHILD',
          age: 12,
        ),
        'test-token',
      );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: QuizScreen(authState: auth),
      ),
    );
    await tester.pumpAndSettle();

    final question = tester.widget<Text>(find.text('What should you do?'));
    final option = tester.widget<Text>(find.text('Tell a trusted adult'));
    expect(question.style?.color, AppColors.textPrimary);
    expect(option.style?.color, AppColors.textPrimary);

    await tester.tap(find.text('Tell a trusted adult'));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'We could not save your answer. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Next Question'), findsNothing);
    expect(find.textContaining('See Results'), findsNothing);
  });
}
