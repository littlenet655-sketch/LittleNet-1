import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';

List<Map<String, dynamic>> listMaps(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

int asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String friendlyError(Object error) {
  if (error is ApiException) {
    switch (error.message) {
      case 'invalid_credentials':
        return 'Invalid username/email or password.';
      case 'disabled_by_parent':
        return 'This feature is turned off in Parent Mode.';
      case 'screen_time_limit':
        return 'Screen time is finished for today.';
      case 'quiet_hours':
        return 'Quiet hours are active right now.';
      case 'quiz_required':
      case 'onboarding_quiz_required':
        return 'A short learning quiz is required before continuing.';
      case 'face_enrollment_required':
        return 'Face ID setup is required before Kids Mode opens.';
      case 'approved_connection_required':
        return 'Both parents must approve this friendship first.';
      case 'contact_sharing_blocked':
        return 'Personal contact information cannot be shared.';
      case 'content_blocked':
      case 'message_blocked':
      case 'comment_blocked':
        return 'LittleNet held this for safety.';
      default:
        return error.message.replaceAll('_', ' ');
    }
  }
  return 'Something went wrong. Please try again.';
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.api,
    required this.url,
    this.radius = 22,
  });

  final ApiClient api;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final safeUrl = url?.trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE0F2FE),
      foregroundImage: safeUrl == null || safeUrl.isEmpty
          ? null
          : NetworkImage(safeUrl, headers: api.authHeaders),
      child: Icon(
        Icons.child_care_rounded,
        size: radius,
        color: const Color(0xFF2563EB),
      ),
    );
  }
}

class NativeMedia extends StatefulWidget {
  const NativeMedia({
    super.key,
    required this.api,
    required this.url,
    required this.mediaType,
    this.fit = BoxFit.cover,
    this.autoPlay = true,
  });

  final ApiClient api;
  final String url;
  final String? mediaType;
  final BoxFit fit;
  final bool autoPlay;

  @override
  State<NativeMedia> createState() => _NativeMediaState();
}

class _NativeMediaState extends State<NativeMedia> {
  VideoPlayerController? controller;
  Future<void>? initialize;

  bool get isVideo => widget.mediaType?.toUpperCase() == 'VIDEO';

  @override
  void initState() {
    super.initState();
    _startVideo();
  }

  @override
  void didUpdateWidget(covariant NativeMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.mediaType != widget.mediaType) {
      controller?.dispose();
      controller = null;
      initialize = null;
      _startVideo();
    }
  }

  void _startVideo() {
    if (!isVideo) return;
    final c = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: widget.api.authHeaders,
    );
    controller = c;
    initialize = c.initialize().then((_) async {
      await c.setLooping(true);
      await c.setVolume(0); // LittleNet intentionally ships silent moderated video.
      if (widget.autoPlay) await c.play();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isVideo) {
      return Image.network(
        widget.url,
        headers: widget.api.authHeaders,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Color(0xFFF1F5F9),
          child: Center(child: Icon(Icons.image_not_supported_outlined)),
        ),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const ColoredBox(
                color: Color(0xFFF8FAFC),
                child: Center(child: CircularProgressIndicator()),
              ),
      );
    }
    final c = controller;
    if (c == null || initialize == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return FutureBuilder<void>(
      future: initialize,
      builder: (_, snapshot) {
        if (snapshot.connectionState != ConnectionState.done || !c.value.isInitialized) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return GestureDetector(
          onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio == 0 ? 9 / 16 : c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            ),
          ),
        );
      },
    );
  }
}

class AsyncBody extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.future,
    required this.builder,
    required this.onRetry,
  });

  final Future<Map<String, dynamic>>? future;
  final Widget Function(Map<String, dynamic> data) builder;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 54),
                  const SizedBox(height: 12),
                  Text(friendlyError(snapshot.error!text)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }
        return builder(snapshot.data ?? const {});
      },
    );
  }
}

extension on Object {
  Object get text => this;
}
