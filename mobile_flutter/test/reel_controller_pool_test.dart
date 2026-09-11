import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:littlenet_native/features/reels/reel_controller_pool.dart';

class TestVideoPlayerController extends VideoPlayerController {
  TestVideoPlayerController(super.uri) : super.networkUrl();

  bool isDisposed = false;
  bool playCalled = false;
  bool pauseCalled = false;
  Completer<void> initCompleter = Completer<void>();

  @override
  Future<void> initialize() async {
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(seconds: 10),
    );
    await initCompleter.future;
  }

  @override
  Future<void> play() async {
    playCalled = true;
    pauseCalled = false;
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauseCalled = true;
    playCalled = false;
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> setLooping(bool looping) async {
    value = value.copyWith(isLooping: looping);
  }

  @override
  Future<void> setVolume(double volume) async {
    value = value.copyWith(volume: volume);
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<TestVideoPlayerController> createdControllers;

  ControllerFactory testFactory(List<Completer<void>> completers) {
    return (Uri uri) {
      final ctrl = TestVideoPlayerController(uri);
      createdControllers.add(ctrl);
      if (completers.isNotEmpty) {
        ctrl.initCompleter = completers.removeAt(0);
      } else {
        ctrl.initCompleter.complete();
      }
      return ctrl;
    };
  }

  setUp(() {
    createdControllers = [];
  });

  test('controller pool never exceeds 3 live controllers', () async {
    final completers = List.generate(10, (_) => Completer<void>()..complete());
    final pool = ReelControllerPool(
      controllerFactory: testFactory(completers),
      maxLiveControllers: 3,
    );

    final reels = List.generate(
      10,
      (i) => {'media_url': 'https://cdn.example.com/reel_$i.mp4', 'poster_url': 'https://cdn.example.com/p_$i.jpg'},
    );

    // Initial page 0 -> loads 0, 1
    pool.onPageChanged(0, reels);
    await Future<void>.delayed(Duration.zero);
    expect(pool.liveCount, lessThanOrEqualTo(3));

    // Move to 1 -> window is [0, 1, 2] -> exactly 3
    pool.onPageChanged(1, reels);
    await Future<void>.delayed(Duration.zero);
    expect(pool.liveCount, lessThanOrEqualTo(3));

    // Move to 2 -> window is [1, 2, 3] -> exactly 3
    pool.onPageChanged(2, reels);
    await Future<void>.delayed(Duration.zero);
    expect(pool.liveCount, lessThanOrEqualTo(3));

    // Move to 5 -> window is [4, 5, 6] -> exactly 3
    pool.onPageChanged(5, reels);
    await Future<void>.delayed(Duration.zero);
    expect(pool.liveCount, lessThanOrEqualTo(3));
  });

  test('moving N -> N+1 disposes N-2', () async {
    final pool = ReelControllerPool(
      controllerFactory: (uri) {
        final ctrl = TestVideoPlayerController(uri);
        createdControllers.add(ctrl);
        ctrl.initCompleter.complete();
        return ctrl;
      },
    );

    final reels = List.generate(
      6,
      (i) => {'media_url': 'https://cdn.example.com/reel_$i.mp4'},
    );

    // At index 1: controllers for 0, 1, 2 exist
    pool.onPageChanged(1, reels);
    await Future<void>.delayed(Duration.zero);
    expect(pool.getController(0), isNotNull);
    final ctrl0 = pool.getController(0) as TestVideoPlayerController;
    expect(ctrl0.isDisposed, isFalse);

    // Move to index 2: window becomes [1, 2, 3]. Index 0 (distance 2) must be disposed!
    pool.onPageChanged(2, reels);
    await Future<void>.delayed(Duration.zero);

    expect(pool.getController(0), isNull);
    expect(ctrl0.isDisposed, isTrue);
    expect(pool.getController(1), isNotNull);
    expect(pool.getController(2), isNotNull);
    expect(pool.getController(3), isNotNull);
  });

  test('rapid page changes do not leave orphan controllers', () async {
    // Simulate slow network on reel 0, 1, 2
    final c0 = Completer<void>();
    final c1 = Completer<void>();
    final c2 = Completer<void>();
    final c5 = Completer<void>();

    final pool = ReelControllerPool(
      controllerFactory: testFactory([c0, c1, c2, c5]),
    );

    final reels = List.generate(
      10,
      (i) => {'media_url': 'https://cdn.example.com/reel_$i.mp4'},
    );

    // User starts at 0, immediately swipes rapidly to 5
    pool.onPageChanged(0, reels);
    pool.onPageChanged(1, reels);
    pool.onPageChanged(5, reels);

    // Now complete the delayed initializations for 0, 1, 2
    c0.complete();
    c1.complete();
    c2.complete();
    c5.complete();
    await Future<void>.delayed(Duration.zero);

    // Any controller outside [4, 5, 6] must be disposed, never orphaned!
    expect(pool.getController(0), isNull);
    expect(pool.getController(1), isNull);
    expect(pool.getController(2), isNull);
    expect(pool.liveCount, lessThanOrEqualTo(3));
  });

  test('app lifecycle pauses current reel and resumes on foreground', () async {
    final pool = ReelControllerPool(
      controllerFactory: (uri) {
        final ctrl = TestVideoPlayerController(uri);
        createdControllers.add(ctrl);
        ctrl.initCompleter.complete();
        return ctrl;
      },
    );

    final reels = [
      {'media_url': 'https://cdn.example.com/reel_0.mp4'},
      {'media_url': 'https://cdn.example.com/reel_1.mp4'},
    ];

    pool.onPageChanged(0, reels);
    await Future<void>.delayed(Duration.zero);
    final ctrl0 = pool.getController(0) as TestVideoPlayerController;
    expect(ctrl0.playCalled, isTrue);

    // App goes to background
    pool.onAppLifecycleChanged(AppLifecycleState.paused);
    expect(ctrl0.pauseCalled, isTrue);

    // App returns to foreground
    pool.onAppLifecycleChanged(AppLifecycleState.resumed);
    expect(ctrl0.playCalled, isTrue);
  });

  test('playback_expires_at near expiry (<30s) triggers onRefreshUrl', () async {
    int refreshCallCount = 0;
    final pool = ReelControllerPool(
      controllerFactory: (uri) {
        final ctrl = TestVideoPlayerController(uri);
        ctrl.initCompleter.complete();
        return ctrl;
      },
      onRefreshUrl: (index, reel) async {
        refreshCallCount++;
        return 'https://cdn.example.com/fresh_reel_0.mp4';
      },
    );

    // Expiring in 10 seconds (< 30s threshold)
    final nearExpiryTime = DateTime.now().add(const Duration(seconds: 10)).toIso8601String();
    final reels = [
      {
        'media_url': 'https://cdn.example.com/expiring_reel_0.mp4',
        'playback_expires_at': nearExpiryTime,
      }
    ];

    pool.onPageChanged(0, reels);
    await Future<void>.delayed(Duration.zero);

    expect(refreshCallCount, equals(1));
    expect(reels[0]['media_url'], equals('https://cdn.example.com/fresh_reel_0.mp4'));
  });

  test('failed playback initialization retries once only without infinite loop', () async {
    int refreshCallCount = 0;
    int controllerCreateCount = 0;

    final pool = ReelControllerPool(
      controllerFactory: (uri) {
        controllerCreateCount++;
        final ctrl = TestVideoPlayerController(uri);
        // Fail initialization (e.g. 403 expired URL)
        ctrl.initCompleter.completeError(Exception('403 Forbidden'));
        return ctrl;
      },
      onRefreshUrl: (index, reel) async {
        refreshCallCount++;
        return 'https://cdn.example.com/refreshed_url.mp4';
      },
    );

    final reels = [
      {'media_url': 'https://cdn.example.com/initial_bad_url.mp4'}
    ];

    pool.onPageChanged(0, reels);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // Exactly 1 refresh attempt and 2 controller creations (initial + 1 retry)
    expect(refreshCallCount, equals(1));
    expect(controllerCreateCount, equals(2));
  });
}
