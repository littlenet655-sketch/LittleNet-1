import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Kids shell exposes Search, Story Editor, Reel Editor, and Study Circle screens', () {
    final shell = File('lib/screens/stitch_kids_shell_impl.dart').readAsStringSync();
    expect(shell, contains('SearchScreen('));
    expect(shell, contains("import 'search_flow.dart';"));
    final kids = File('lib/screens/kids.dart').readAsStringSync();
    expect(kids, contains("import 'creator_editors.dart';"));

    final searchFlow = File('lib/screens/search_flow.dart').readAsStringSync();
    expect(searchFlow, contains('class SearchScreen'));
    expect(searchFlow, contains('class SearchResultsScreen'));
    expect(searchFlow, contains('class BlockedSearchScreen'));

    final editors = File('lib/screens/creator_editors.dart').readAsStringSync();
    expect(editors, contains('class StoryEditorScreen'));
    expect(editors, contains('class ReelEditorScreen'));
    expect(editors, contains('class StudyCircleScreen'));
  });

  test('runtime uses the fully wired Kids shell', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    expect(mainSource, contains('StitchKidsShellV2('));
    expect(mainSource, contains("import 'screens/stitch_kids_shell.dart';"));
  });

  test('Kids shell exposes canonical social and safety destinations', () {
    final shell = File('lib/screens/stitch_kids_shell_impl.dart').readAsStringSync();
    for (final destination in const [
      'PostDetailScreen',
      'OtherUserProfileScreen',
      'SavedContentScreen',
      'SafetyCentreScreen',
      'ReportHistoryScreen',
      'showSharePostSheet',
      'showReportSheet',
      "label: 'Home'",
      "label: 'Reels'",
      "label: 'Create'",
      "label: 'Learn'",
      "label: 'Profile'",
    ]) {
      expect(shell, contains(destination), reason: 'Missing wiring for $destination');
    }
  });

  test('Reels expose all primary interaction controls', () {
    final shell = File('lib/screens/stitch_kids_shell_impl.dart').readAsStringSync();
    for (final fragment in const [
      "tooltip: 'Like'",
      "tooltip: 'Comments'",
      "tooltip: 'Share'",
      "tooltip: saved ? 'Unsave' : 'Save'",
      "tooltip: 'Report'",
      "'/api/mobile/v1/kids/posts/\$postId/save'",
    ]) {
      expect(shell, contains(fragment), reason: 'Missing Reel action $fragment');
    }
  });
}
