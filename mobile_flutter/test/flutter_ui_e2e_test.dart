import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:littlenet_native/api.dart';
import 'package:littlenet_native/app_theme.dart';
import 'package:littlenet_native/screens/auth.dart';
import 'package:littlenet_native/screens/creator_editors.dart';
import 'package:littlenet_native/screens/search_flow.dart';
import 'package:littlenet_native/screens/stitch_kids_shell_impl.dart';
import 'package:littlenet_native/screens/stitch_shells.dart';

void main() {
  final dummyApi = ApiClient(baseUrl: 'http://127.0.0.1:9');

  Widget makeTestable(Widget child) {
    return MaterialApp(
      theme: LittleNetTheme.light(),
      home: child,
    );
  }

  testWidgets('Screen 1 & 3: LoginScreen renders brand, inputs, and mode segments', (tester) async {
    await tester.pumpWidget(makeTestable(LoginScreen(
      api: dummyApi,
      onSignedIn: (_) {},
    )));
    await tester.pump();

    expect(find.text('LittleNet'), findsWidgets);
    expect(find.text('A safe, AI-guided social world for children'), findsOneWidget);
    expect(find.text('Kids Mode'), findsOneWidget);
    expect(find.text('Parent Mode'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Face ID Login'), findsOneWidget);
  });

  testWidgets('Screen 8: StitchKidsShellV2 renders navigation destinations and header actions', (tester) async {
    final dummyChildUser = {
      'user_id': 101,
      'username': 'little_star',
      'full_name': 'Little Star',
      'role': 'CHILD',
    };

    await tester.pumpWidget(makeTestable(StitchKidsShellV2(
      api: dummyApi,
      user: dummyChildUser,
      onLogout: () async {},
    )));
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Reels'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Learn'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(find.byTooltip('Messages'), findsOneWidget);
  });

  testWidgets('Screen 27: SearchScreen renders safe categories and recent topics', (tester) async {
    await tester.pumpWidget(makeTestable(SearchScreen(
      api: dummyApi,
      refreshToken: 1,
    )));
    await tester.pump();

    expect(find.text('Search LittleNet'), findsOneWidget);
    expect(find.text('Recent Topics'), findsOneWidget);
    expect(find.text('Explore Categories'), findsOneWidget);
    expect(find.text('Science'), findsWidgets);
    expect(find.text('Coding'), findsWidgets);
    expect(find.text('Math'), findsWidgets);
    expect(find.text('LittleNet protects your privacy. Personal contact information is shielded.'), findsOneWidget);
  });

  testWidgets('Screen 28: SearchResultsScreen renders People and Safe Posts tabs', (tester) async {
    await tester.pumpWidget(makeTestable(SearchResultsScreen(
      api: dummyApi,
      initialQuery: 'Science',
      refreshToken: 1,
    )));
    await tester.pump();

    expect(find.text('People'), findsOneWidget);
    expect(find.text('Safe Posts'), findsOneWidget);
  });

  testWidgets('Screen 29: BlockedSearchScreen renders educational privacy shield and reset', (tester) async {
    var resetCalled = false;
    await tester.pumpWidget(makeTestable(BlockedSearchScreen(
      query: '9876543210',
      onReset: () => resetCalled = true,
    )));
    await tester.pump();

    expect(find.text('Search Protected'), findsOneWidget);
    expect(find.text('Search Safe Topics'), findsOneWidget);
    await tester.tap(find.text('Search Safe Topics'));
    expect(resetCalled, isTrue);
  });

  testWidgets('Screen 18: StoryEditorScreen renders canvas, gradient styles, and stickers', (tester) async {
    await tester.pumpWidget(makeTestable(StoryEditorScreen(
      api: dummyApi,
      onPublished: () {},
    )));
    await tester.pump();

    expect(find.text('Story Editor'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Style: '), findsOneWidget);
    expect(find.text('⭐ Star'), findsOneWidget);
    expect(find.text('🚀 Curious'), findsOneWidget);
  });

  testWidgets('Screen 23: ReelEditorScreen renders video duration limit and options', (tester) async {
    await tester.pumpWidget(makeTestable(ReelEditorScreen(
      api: dummyApi,
      onPublished: () {},
    )));
    await tester.pump();

    expect(find.text('Reel Creator & Editor'), findsOneWidget);
    expect(find.text('Record or select video reel (max 60s)'), findsOneWidget);
    expect(find.text('Educational Topic'), findsOneWidget);
    expect(find.text('Audio & Narration'), findsOneWidget);
  });

  testWidgets('Screen 33: StudyCircleScreen renders supervised circle with parent oversight banner', (tester) async {
    await tester.pumpWidget(makeTestable(StudyCircleScreen(
      api: dummyApi,
      circleName: 'Science Study Circle',
      members: const ['Maya', 'Alex', 'Rohan'],
    )));
    await tester.pump();

    expect(find.text('Science Study Circle'), findsOneWidget);
    expect(find.text('Supervised Study Circle • Monitored for safety and respect'), findsOneWidget);
    expect(find.text('Study Circle Guidelines'), findsOneWidget);
  });

  testWidgets('Screen 52: StitchParentShell renders Parent Dashboard and navigation controls', (tester) async {
    final dummyParentUser = {
      'user_id': 1,
      'username': 'parent_jane',
      'full_name': 'Jane Doe',
      'role': 'PARENT',
    };

    await tester.pumpWidget(makeTestable(StitchParentShell(
      api: dummyApi,
      user: dummyParentUser,
      onLogout: () async {},
    )));
    await tester.pump();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Controls'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
  });
}
