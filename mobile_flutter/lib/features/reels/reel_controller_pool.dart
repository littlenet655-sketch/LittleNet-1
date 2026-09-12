import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

typedef ControllerFactory = VideoPlayerController Function(Uri uri);
typedef UrlRefreshCallback = Future<String?> Function(int index, Map<String, dynamic> reel);

/// High-performance VideoPlayerController pool for LittleNet Reels.
///
/// STRICT RESOURCE RULE:
/// Maintains AT MOST 3 active VideoPlayerController instances:
/// - index N-1: initialized, paused
/// - index N: initialized, playing, looping
/// - index N+1: initialized, buffering/preloaded
///
/// Distances |index - N| >= 2 have NO live controller and rely exclusively on
/// precached poster images to protect mobile hardware decoders and memory.
class ReelControllerPool {
  ReelControllerPool({
    ControllerFactory? controllerFactory,
    this.maxLiveControllers = 3,
    this.onRefreshUrl,
  }) : _controllerFactory = controllerFactory ??
            ((uri) => VideoPlayerController.networkUrl(uri));

  final ControllerFactory _controllerFactory;
  final int maxLiveControllers;

  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, int> _initializingTokens = {};
  final Set<int> _brokenIndices = {};
  final Set<int> _retriedExpiryIndices = {};

  int _focusedIndex = -1;
  bool _isAppActive = true;
  VoidCallback? onStateChanged;
  UrlRefreshCallback? onRefreshUrl;

  int get focusedIndex => _focusedIndex;
  int get liveCount => _controllers.length;
  bool isBroken(int index) => _brokenIndices.contains(index);

  VideoPlayerController? getController(int index) => _controllers[index];

  bool isReady(int index) {
    final c = _controllers[index];
    return c != null && c.value.isInitialized;
  }

  /// Called when the PageView changes page.
  void onPageChanged(
    int newIndex,
    List<Map<String, dynamic>> reels, [
    BuildContext? context,
  ]) {
    if (newIndex < 0 || newIndex >= reels.length) return;
    _focusedIndex = newIndex;

    // 1. Immediately pause any controller that is not the newly focused reel.
    for (final entry in _controllers.entries) {
      if (entry.key != newIndex && entry.value.value.isInitialized) {
        entry.value.pause();
      }
    }

    // 2. Play new current controller if already initialized and app is in foreground.
    final currentCtrl = _controllers[newIndex];
    if (currentCtrl != null && currentCtrl.value.isInitialized && _isAppActive) {
      currentCtrl.play();
    }

    // 3. Strict resource cleanup: immediately dispose any controllers beyond distance 1.
    _pruneDistantControllers(newIndex);

    // 4. Initialize adjacent window: current (N), next (N+1), previous (N-1).
    _ensureControllerForIndex(newIndex, reels);
    if (newIndex + 1 < reels.length) {
      _ensureControllerForIndex(newIndex + 1, reels);
    }
    if (newIndex - 1 >= 0) {
      _ensureControllerForIndex(newIndex - 1, reels);
    }

    // 5. Precache poster images for N, N+1, N+2, N-1, N-2 in Flutter image cache.
    if (context != null) {
      _precachePosters(newIndex, reels, context);
    }

    onStateChanged?.call();
  }

  /// Preload/precache posters for newly fetched batch of reels.
  void preload(List<Map<String, dynamic>> reels, BuildContext context) {
    final targetIndex = _focusedIndex >= 0 ? _focusedIndex : 0;
    _precachePosters(targetIndex, reels, context);
  }

  void _pruneDistantControllers(int targetIndex) {
    final toRemove = _controllers.keys
        .where((idx) => (idx - targetIndex).abs() > 1)
        .toList();

    for (final idx in toRemove) {
      final ctrl = _controllers.remove(idx);
      _initializingTokens.remove(idx);
      ctrl?.pause();
      ctrl?.dispose();
    }
  }

  void _ensureControllerForIndex(
    int index,
    List<Map<String, dynamic>> reels,
  ) {
    if (index < 0 || index >= reels.length) return;
    if (_controllers.containsKey(index)) return;
    if (_brokenIndices.contains(index)) return;

    // Hard ceiling enforcement: never exceed maxLiveControllers (3).
    if (_controllers.length >= maxLiveControllers) {
      _pruneDistantControllers(_focusedIndex);
      if (_controllers.length >= maxLiveControllers) {
        final furthest = _controllers.keys.reduce(
          (a, b) =>
              (a - _focusedIndex).abs() > (b - _focusedIndex).abs() ? a : b,
        );
        final ctrl = _controllers.remove(furthest);
        _initializingTokens.remove(furthest);
        ctrl?.pause();
        ctrl?.dispose();
      }
    }

    final reel = reels[index];
    final mediaUrl = reel['media_url']?.toString();
    if (mediaUrl == null || mediaUrl.isEmpty) {
      _brokenIndices.add(index);
      return;
    }

    // Near-expiry check (<30s remaining): proactively refresh
    final expiresAtRaw = reel['playback_expires_at'];
    if (expiresAtRaw != null && onRefreshUrl != null) {
      DateTime? expiresAt;
      if (expiresAtRaw is int) {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtRaw * 1000);
      } else if (expiresAtRaw is String) {
        expiresAt = DateTime.tryParse(expiresAtRaw);
      }
      if (expiresAt != null && expiresAt.difference(DateTime.now()).inSeconds < 30) {
        onRefreshUrl!(index, reel).then((freshUrl) {
          if (freshUrl != null && freshUrl.isNotEmpty) {
            reel['media_url'] = freshUrl;
          }
        }).catchError((_) {});
      }
    }

    final token = DateTime.now().microsecondsSinceEpoch + index;
    _initializingTokens[index] = token;

    try {
      final uri = Uri.parse(mediaUrl);
      final controller = _controllerFactory(uri)
        ..setLooping(true)
        ..setVolume(0.0); // LittleNet silent/moderated policy

      _controllers[index] = controller;

      controller.initialize().then((_) {
        // Race condition prevention:
        // If the user swiped away while initialize() was awaiting network,
        // or if a newer token replaced this index, dispose immediately.
        if (_initializingTokens[index] != token ||
            (_focusedIndex != -1 && (index - _focusedIndex).abs() > 1)) {
          _controllers.remove(index)?.dispose();
          _initializingTokens.remove(index);
          return;
        }

        _initializingTokens.remove(index);

        if (index == _focusedIndex && _isAppActive) {
          controller.play();
        } else {
          controller.pause();
        }

        onStateChanged?.call();
      }).catchError((_) async {
        // If playback initialization fails (e.g. 401/403 expired signed URL), retry once with refreshed URL
        if (onRefreshUrl != null && !_retriedExpiryIndices.contains(index)) {
          _retriedExpiryIndices.add(index);
          try {
            final freshUrl = await onRefreshUrl!(index, reel);
            if (freshUrl != null && freshUrl.isNotEmpty) {
              reel['media_url'] = freshUrl;
              _controllers.remove(index)?.dispose();
              _initializingTokens.remove(index);
              _ensureControllerForIndex(index, reels);
              return;
            }
          } catch (_) {}
        }

        _brokenIndices.add(index);
        _controllers.remove(index)?.dispose();
        _initializingTokens.remove(index);
        onStateChanged?.call();
      });
    } catch (_) {
      _brokenIndices.add(index);
    }
  }

  void _precachePosters(
    int index,
    List<Map<String, dynamic>> reels,
    BuildContext context,
  ) {
    final posterIndices = [index, index + 1, index + 2, index - 1, index - 2];
    for (final i in posterIndices) {
      if (i >= 0 && i < reels.length) {
        final posterUrl = reels[i]['poster_url']?.toString();
        if (posterUrl != null && posterUrl.startsWith('http')) {
          precacheImage(NetworkImage(posterUrl), context).catchError((_) {});
        }
      }
    }
  }

  /// App lifecycle handling.
  void onAppLifecycleChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _isAppActive = false;
      pauseCurrent();
    } else if (state == AppLifecycleState.resumed) {
      _isAppActive = true;
      resumeCurrent();
    }
  }

  void pauseCurrent() {
    if (_focusedIndex >= 0 && _controllers.containsKey(_focusedIndex)) {
      _controllers[_focusedIndex]?.pause();
    }
  }

  void resumeCurrent() {
    if (_isAppActive &&
        _focusedIndex >= 0 &&
        _controllers.containsKey(_focusedIndex)) {
      final ctrl = _controllers[_focusedIndex];
      if (ctrl != null && ctrl.value.isInitialized) {
        ctrl.play();
      }
    }
  }

  void disposeAll() {
    for (final c in _controllers.values) {
      c.pause();
      c.dispose();
    }
    _controllers.clear();
    _initializingTokens.clear();
    _brokenIndices.clear();
    _focusedIndex = -1;
  }
}
