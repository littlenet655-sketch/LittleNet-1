import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:littlenet_native/api.dart';
import 'package:littlenet_native/core/auth/auth_state.dart';
import 'package:littlenet_native/core/upload/upload_manager.dart';
import 'package:littlenet_native/core/upload/upload_progress_banner.dart';
import 'package:littlenet_native/features/create_post/create_post_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UploadManager & MIME types', () {
    test('lookupMimeType correctly classifies extensions', () {
      expect(UploadManager.lookupMimeType('video.mp4', true), 'video/mp4');
      expect(UploadManager.lookupMimeType('clip.mov', true), 'video/quicktime');
      expect(UploadManager.lookupMimeType('movie.webm', true), 'video/webm');
      expect(UploadManager.lookupMimeType('drawing.jpg', false), 'image/jpeg');
      expect(UploadManager.lookupMimeType('drawing.jpeg', false), 'image/jpeg');
      expect(UploadManager.lookupMimeType('photo.png', false), 'image/png');
      expect(UploadManager.lookupMimeType('anim.gif', false), 'image/gif');
      expect(UploadManager.lookupMimeType('sticker.webp', false), 'image/webp');
      expect(UploadManager.lookupMimeType('unknown', true), 'video/mp4');
      expect(UploadManager.lookupMimeType('unknown', false), 'image/jpeg');
    });

    test('UploadManager state transitions and dismiss', () {
      final manager = UploadManager.instance;
      expect(manager.state.stage, UploadStage.idle);
      expect(manager.state.isActive, false);

      // Dismiss resets to idle
      manager.dismiss();
      expect(manager.state.stage, UploadStage.idle);
      expect(manager.state.message, '');
    });
  });

  group('UploadProgressBanner widget', () {
    testWidgets('Renders shrink when idle', (tester) async {
      UploadManager.instance.dismiss();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UploadProgressBanner(),
          ),
        ),
      );

      expect(find.byType(UploadProgressBanner), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('CreatePostScreen Hashtag Chip UI', () {
    testWidgets('Displays hashtag input and adds valid tag chips', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final auth = AuthState(apiClient: ApiClient());

      await tester.pumpWidget(
        MaterialApp(
          home: CreatePostScreen(authState: auth),
        ),
      );

      // Verify Hashtags section is rendered
      expect(find.textContaining('Hashtags'), findsOneWidget);

      // Find the hashtag text field
      final textFieldFinder = find.widgetWithText(TextField, 'Add a tag (e.g. science, art)');
      expect(textFieldFinder, findsOneWidget);

      // Enter a valid tag
      await tester.enterText(textFieldFinder, 'astronomy');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Check that #astronomy chip is displayed
      expect(find.text('#astronomy'), findsOneWidget);

      // Add another tag with leading '#'
      await tester.enterText(textFieldFinder, '#science_fun');
      await tester.tap(find.byTooltip('Add hashtag'));
      await tester.pumpAndSettle();

      // Check that #science_fun chip is displayed
      expect(find.text('#science_fun'), findsOneWidget);

      // Remove the astronomy tag by tapping its close icon
      final closeIcons = find.byIcon(Icons.close_rounded);
      // Tap the first tag close icon (close_rounded on #astronomy)
      await tester.tap(closeIcons.first);
      await tester.pumpAndSettle();

      // Verify #astronomy was removed
      expect(find.text('#astronomy'), findsNothing);
      expect(find.text('#science_fun'), findsOneWidget);
    });

    testWidgets('Rejects invalid hashtags with phone numbers or special characters', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final auth = AuthState(apiClient: ApiClient());

      await tester.pumpWidget(
        MaterialApp(
          home: CreatePostScreen(authState: auth),
        ),
      );

      final textFieldFinder = find.widgetWithText(TextField, 'Add a tag (e.g. science, art)');

      // Attempt to add a phone number
      await tester.enterText(textFieldFinder, '9876543210');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should show SnackBar error and not add the tag chip
      expect(find.text('#9876543210'), findsNothing);
      expect(find.textContaining('Phone numbers'), findsOneWidget);

      // Dismiss snackbar
      ScaffoldMessenger.of(tester.element(textFieldFinder)).clearSnackBars();
      await tester.pumpAndSettle();

      // Attempt to add special characters
      await tester.enterText(textFieldFinder, 'tag!@#\$%');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('#tag!@#\$%'), findsNothing);
      expect(find.textContaining('only contain letters'), findsOneWidget);
    });
  });
}
