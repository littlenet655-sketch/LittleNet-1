import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
