import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../../api.dart';
import '../auth/auth_state.dart';

enum UploadStage {
  idle,
  creatingSession,
  uploading,
  processing,
  allowed,
  review,
  blocked,
  failed,
}

class UploadTaskState {
  final UploadStage stage;
  final double progress; // 0.0 to 1.0
  final String message;
  final int? postId;
  final String? uploadId;
  final String? error;
  final String kind;
  final File? file;

  const UploadTaskState({
    this.stage = UploadStage.idle,
    this.progress = 0.0,
    this.message = '',
    this.postId,
    this.uploadId,
    this.error,
    this.kind = 'post',
    this.file,
  });

  bool get isActive =>
      stage == UploadStage.creatingSession ||
      stage == UploadStage.uploading ||
      stage == UploadStage.processing;

  bool get isCompleted =>
      stage == UploadStage.allowed ||
      stage == UploadStage.review ||
      stage == UploadStage.blocked;

  bool get isFailed => stage == UploadStage.failed;

  UploadTaskState copyWith({
    UploadStage? stage,
    double? progress,
    String? message,
    int? postId,
    String? uploadId,
    String? error,
    String? kind,
    File? file,
  }) {
    return UploadTaskState(
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      postId: postId ?? this.postId,
      uploadId: uploadId ?? this.uploadId,
      error: error ?? this.error,
      kind: kind ?? this.kind,
      file: file ?? this.file,
    );
  }
}

class UploadParams {
  final File? file;
  final String kind;
  final String caption;
  final String category;
  final String audience;
  final List<String> tags;
  final String? locationName;
  final int? musicId;
  final int? musicStart;
  final int? musicDuration;
  final AuthState authState;

  UploadParams({
    required this.file,
    required this.kind,
    required this.caption,
    required this.category,
    required this.audience,
    required this.tags,
    this.locationName,
    this.musicId,
    this.musicStart,
    this.musicDuration,
    required this.authState,
  });
}

/// Global Singleton for LittleNet asynchronous uploads & background moderation tracking.
class UploadManager extends ChangeNotifier {
  UploadManager._();
  static final UploadManager instance = UploadManager._();

  UploadTaskState _state = const UploadTaskState();
  UploadParams? _lastParams;
  Timer? _pollingTimer;
  Timer? _autoDismissTimer;

  static const String _pendingUploadKey = 'littlenet_pending_upload';
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  UploadTaskState get state => _state;

  void _setState(UploadTaskState newState) {
    _state = newState;
    notifyListeners();
  }

  Future<void> _persistPendingUpload() async {
    try {
      if (_state.postId != null && _state.isActive) {
        final data = {
          'postId': _state.postId,
          'uploadId': _state.uploadId,
          'kind': _state.kind,
          'stage': _state.stage.name,
        };
        await _storage.write(key: _pendingUploadKey, value: jsonEncode(data));
      }
    } catch (_) {}
  }

  Future<void> _clearPendingUpload() async {
    try {
      await _storage.delete(key: _pendingUploadKey);
    } catch (_) {}
  }

  /// Reconcile any unfinished uploads on app startup or restart.
  Future<void> reconcilePendingUpload(ApiClient apiClient) async {
    try {
      final jsonStr = await _storage.read(key: _pendingUploadKey);
      if (jsonStr == null || jsonStr.isEmpty) return;
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final postId = data['postId'] as int?;
      final kind = data['kind'] as String? ?? 'post';
      if (postId == null) return;

      final res = await apiClient
          .getJson('/api/mobile/v2/posts/$postId/processing-status');
      if (res['ok'] == true) {
        final status = (res['status'] as String? ?? '').toUpperCase();
        final stage = (res['stage'] as String? ?? '').toUpperCase();
        final kindName = switch (kind.toLowerCase()) {
          'reel' => 'Reel',
          'story' => 'Story',
          _ => 'Post',
        };

        if (status == 'ALLOWED' || stage == 'ALLOWED') {
          await _clearPendingUpload();
          _setState(_state.copyWith(
            stage: UploadStage.allowed,
            postId: postId,
            kind: kind,
            progress: 1.0,
            message: '$kindName published! ✓',
          ));
          _scheduleAutoDismiss();
        } else if (status == 'REVIEW' || stage == 'REVIEW') {
          await _clearPendingUpload();
          _setState(_state.copyWith(
            stage: UploadStage.review,
            postId: postId,
            kind: kind,
            progress: 1.0,
            message: 'Sent for Parent Safety Review',
          ));
          _scheduleAutoDismiss(seconds: 5);
        } else if (status == 'BLOCKED' || stage == 'BLOCKED') {
          await _clearPendingUpload();
          final reason = res['moderation_reason']?.toString() ??
              'Content does not follow child safety standards.';
          _setState(_state.copyWith(
            stage: UploadStage.blocked,
            postId: postId,
            kind: kind,
            error: reason,
            message: 'Blocked: $reason',
          ));
        } else if (status == 'PROCESSING' ||
            stage == 'PROCESSING' ||
            status == 'PENDING') {
          _setState(_state.copyWith(
            stage: UploadStage.processing,
            postId: postId,
            kind: kind,
            progress: 0.9,
            message:
                'Still checking your $kindName. You can keep using LittleNet.',
          ));
          _startStatusPolling(apiClient, postId, kindName);
        }
      }
    } catch (e) {
      debugPrint('[UploadManager] Reconcile error: $e');
    }
  }

  void dismiss() {
    _pollingTimer?.cancel();
    _autoDismissTimer?.cancel();
    _setState(const UploadTaskState(stage: UploadStage.idle));
  }

  void retry() {
    if (_lastParams != null) {
      startUpload(_lastParams!);
    }
  }

  static String lookupMimeType(String path, bool isVideo) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.m4v')) return 'video/x-m4v';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return isVideo ? 'video/mp4' : 'image/jpeg';
  }

  /// Start background upload and tracking. Immediately returns while async task proceeds.
  Future<void> startUpload(UploadParams params) async {
    _pollingTimer?.cancel();
    _autoDismissTimer?.cancel();
    _lastParams = params;

    final kindName = switch (params.kind.toLowerCase()) {
      'reel' => 'Reel',
      'story' => 'Story',
      _ => 'Post',
    };

    final file = params.file;
    // If no media file is attached (text-only post), use direct v1 fallback
    if (file == null) {
      await _uploadTextOnlyFallback(params, kindName);
      return;
    }

    try {
      final isVideo = params.kind.toLowerCase() == 'reel' ||
          file.path.toLowerCase().endsWith('.mp4') ||
          file.path.toLowerCase().endsWith('.mov') ||
          file.path.toLowerCase().endsWith('.webm');

      final mimeType = lookupMimeType(file.path, isVideo);
      final filename = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : 'media_${DateTime.now().millisecondsSinceEpoch}.${isVideo ? "mp4" : "jpg"}';
      final sizeBytes = await file.length();

      // Step 1: Create direct upload session
      _setState(UploadTaskState(
        stage: UploadStage.creatingSession,
        progress: 0.05,
        message: 'Preparing $kindName upload...',
        kind: params.kind,
        file: file,
      ));

      Map<String, dynamic> sessionResp;
      try {
        final ext = filename.contains('.')
            ? filename.split('.').last.toLowerCase()
            : (isVideo ? 'mp4' : 'jpg');
        sessionResp = await params.authState.apiClient.postJson(
          '/api/mobile/v2/uploads/session',
          {
            'kind': params.kind,
            'filename': filename,
            'media_type': isVideo ? 'VIDEO' : 'IMAGE',
            'extension': ext,
            'content_type': mimeType,
            'mime_type': mimeType,
            'size_bytes': sizeBytes,
          },
        );
      } catch (sessionErr) {
        // Strict fallback gate: Fallback to V1 ONLY when server explicitly signals
        // direct_upload_unavailable AND fallback_allowed == true.
        Map<String, dynamic>? errorPayload;
        if (sessionErr is ApiException) {
          errorPayload = sessionErr.payload;
        }

        final isFallbackAllowed = errorPayload != null &&
            errorPayload['error'] == 'direct_upload_unavailable' &&
            errorPayload['fallback_allowed'] == true;

        if (isFallbackAllowed) {
          debugPrint(
              '[UploadManager] Direct upload unavailable with fallback allowed. Falling back to V1.');
          await _uploadV1Fallback(params, kindName);
          return;
        }

        debugPrint(
            '[UploadManager] V2 session failed ($sessionErr). Direct error surfaced; fallback not permitted.');
        rethrow;
      }

      final uploadId = sessionResp['upload_id']?.toString() ?? '';
      final uploadUrlStr = sessionResp['upload_url']?.toString() ?? '';

      if (uploadId.isEmpty || uploadUrlStr.isEmpty) {
        throw Exception(
            'Invalid upload session response: missing URL or session ID.');
      }

      // Step 2: Stream media PUT directly to storage upload URL
      _setState(_state.copyWith(
        stage: UploadStage.uploading,
        uploadId: uploadId,
        progress: 0.1,
        message: 'Uploading $kindName... 10%',
      ));

      await _directPutWithProgress(
        uploadUrlStr: uploadUrlStr,
        file: file,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        kindName: kindName,
      );

      // Step 3: Call complete to trigger background moderation and save metadata
      _setState(_state.copyWith(
        stage: UploadStage.processing,
        progress: 1.0,
        message: 'Checking child safety...',
      ));

      final completeResp = await params.authState.apiClient.postJson(
        '/api/mobile/v2/uploads/$uploadId/complete',
        {
          'kind': params.kind,
          'caption': params.caption,
          'content_category': params.category,
          'audience_age_group': params.audience,
          'tags': params.tags,
          if (params.locationName != null && params.locationName!.isNotEmpty)
            'location_name': params.locationName,
          if (params.musicId != null) 'music_id': params.musicId,
          if (params.musicStart != null) 'music_start': params.musicStart,
          if (params.musicDuration != null)
            'music_duration': params.musicDuration,
        },
      );

      final postId = completeResp['post_id'] is int
          ? completeResp['post_id'] as int
          : int.tryParse(completeResp['post_id']?.toString() ?? '');

      if (postId == null) {
        throw Exception('Failed to finalize post: missing post_id.');
      }

      _setState(_state.copyWith(
        postId: postId,
        message: 'Checking child safety...',
      ));

      // Step 4: Poll post processing status
      _startStatusPolling(params.authState.apiClient, postId, kindName);
    } catch (e) {
      debugPrint('[UploadManager] Upload failed: $e');
      final quizRequired = e is ApiException && e.isQuizGate;
      _setState(_state.copyWith(
        stage: UploadStage.failed,
        error: quizRequired ? 'quiz_required' : e.toString(),
        message: quizRequired
            ? 'Complete the required safety quiz before uploading.'
            : 'Upload failed: ${e.toString().replaceAll("Exception: ", "")}',
      ));
    }
  }

  /// Stream HTTP PUT to presigned / mock upload URL tracking byte progress
  Future<void> _directPutWithProgress({
    required String uploadUrlStr,
    required File file,
    required String mimeType,
    required int sizeBytes,
    required String kindName,
  }) async {
    final uri = Uri.parse(uploadUrlStr);
    final request = http.StreamedRequest('PUT', uri);
    request.contentLength = sizeBytes;
    request.headers['Content-Type'] = mimeType;

    int bytesSent = 0;
    final fileStream = file.openRead();

    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, sink) {
        bytesSent += chunk.length;
        if (sizeBytes > 0) {
          final ratio = (bytesSent / sizeBytes).clamp(0.0, 1.0);
          final percent = (ratio * 100).toInt();
          _setState(_state.copyWith(
            progress: ratio,
            message: 'Uploading $kindName... $percent%',
          ));
        }
        sink.add(chunk);
      },
      handleDone: (sink) => sink.close(),
      handleError: (err, stack, sink) => sink.addError(err, stack),
    );

    fileStream.transform(transformer).listen(
          request.sink.add,
          onDone: request.sink.close,
          onError: request.sink.addError,
          cancelOnError: true,
        );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Upload failed with HTTP status ${response.statusCode}');
    }
  }

  /// Poll /api/mobile/v2/posts/{post_id}/processing-status until terminal state
  void _startStatusPolling(ApiClient apiClient, int postId, String kindName) {
    _pollingTimer?.cancel();
    int attempts = 0;
    const maxAttempts = 35; // ~70-80s max

    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;
      if (attempts > maxAttempts) {
        timer.cancel();
        _setState(_state.copyWith(
          stage: UploadStage.processing,
          message:
              'Still checking your $kindName. You can keep using LittleNet.',
        ));
        _persistPendingUpload();
        return;
      }

      try {
        final res = await apiClient.getJson(
          '/api/mobile/v2/posts/$postId/processing-status',
        );

        if (res['ok'] != true) return;

        final status = (res['status'] as String? ?? '').toUpperCase();
        final stage = (res['stage'] as String? ?? '').toUpperCase();

        if (status == 'ALLOWED' || stage == 'ALLOWED') {
          timer.cancel();
          await _clearPendingUpload();
          _setState(_state.copyWith(
            stage: UploadStage.allowed,
            progress: 1.0,
            message: '$kindName published! ✓',
          ));
          _scheduleAutoDismiss();
        } else if (status == 'REVIEW' || stage == 'REVIEW') {
          timer.cancel();
          await _clearPendingUpload();
          _setState(_state.copyWith(
            stage: UploadStage.review,
            progress: 1.0,
            message: 'Sent for Parent Safety Review',
          ));
          _scheduleAutoDismiss(seconds: 5);
        } else if (status == 'BLOCKED' || stage == 'BLOCKED') {
          timer.cancel();
          await _clearPendingUpload();
          final reason = res['moderation_reason']?.toString() ??
              'Content does not follow child safety standards.';
          _setState(_state.copyWith(
            stage: UploadStage.blocked,
            error: reason,
            message: 'Blocked: $reason',
          ));
        } else if (stage == 'FAILED') {
          timer.cancel();
          await _clearPendingUpload();
          final err = res['error']?.toString() ?? 'Media processing failed.';
          _setState(_state.copyWith(
            stage: UploadStage.failed,
            error: err,
            message: 'Failed: $err',
          ));
        } else {
          // Still PROCESSING / UPLOADED
          _persistPendingUpload();
          _setState(_state.copyWith(
            stage: UploadStage.processing,
            message: 'Checking child safety...',
          ));
        }
      } catch (e) {
        debugPrint('[UploadManager] Polling tick error: $e');
      }
    });
  }

  void _scheduleAutoDismiss({int seconds = 4}) {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(Duration(seconds: seconds), () {
      if (_state.isCompleted) {
        dismiss();
      }
    });
  }

  /// Fallback to V1 synchronous multipart
  Future<void> _uploadV1Fallback(UploadParams params, String kindName) async {
    try {
      _setState(UploadTaskState(
        stage: UploadStage.uploading,
        progress: 0.5,
        message: 'Uploading $kindName...',
        kind: params.kind,
        file: params.file,
      ));

      final res = await params.authState.apiClient.multipart(
        '/api/mobile/v1/kids/posts',
        file: params.file,
        fileField: 'media',
        fields: {
          'caption': params.caption,
          'content_category': params.category,
          'audience_age_group': params.audience,
          'kind': params.kind,
          if (params.tags.isNotEmpty) 'tags': jsonEncode(params.tags),
        },
      );

      final status = (res['status'] as String? ?? '').toUpperCase();
      final postId = res['post_id'] is int
          ? res['post_id'] as int
          : int.tryParse(res['post_id']?.toString() ?? '');
      if (res['ok'] == true &&
          (status == 'ALLOW' || status == 'ALLOWED' || status == '')) {
        _setState(_state.copyWith(
          stage: UploadStage.allowed,
          postId: postId,
          progress: 1.0,
          message: '$kindName published! ✓',
        ));
        _scheduleAutoDismiss();
      } else if (res['ok'] == true && status == 'REVIEW') {
        _setState(_state.copyWith(
          stage: UploadStage.review,
          postId: postId,
          progress: 1.0,
          message: 'Sent for Parent Safety Review',
        ));
        _scheduleAutoDismiss(seconds: 5);
      } else {
        _setState(_state.copyWith(
          stage: UploadStage.failed,
          message: 'Post could not be published right now.',
        ));
      }
    } on ApiException catch (e) {
      if (e.payload?['blocked'] == true || e.message.contains('blocked')) {
        final reason = e.payload?['reason'] as String? ??
            'Content does not follow child safety standards.';
        _setState(_state.copyWith(
          stage: UploadStage.blocked,
          error: reason,
          message: 'Blocked: $reason',
        ));
      } else {
        _setState(_state.copyWith(
          stage: UploadStage.failed,
          error: e.message,
          message: e.message,
        ));
      }
    } catch (e) {
      _setState(_state.copyWith(
        stage: UploadStage.failed,
        error: e.toString(),
        message: 'Upload failed: $e',
      ));
    }
  }

  /// Text-only post submission
  Future<void> _uploadTextOnlyFallback(
      UploadParams params, String kindName) async {
    try {
      _setState(UploadTaskState(
        stage: UploadStage.processing,
        progress: 0.5,
        message: 'Publishing $kindName...',
        kind: params.kind,
      ));

      final res = await params.authState.apiClient.postJson(
        '/api/mobile/v1/kids/posts',
        {
          'caption': params.caption,
          'content_category': params.category,
          'audience_age_group': params.audience,
          'kind': params.kind,
          if (params.tags.isNotEmpty) 'tags': params.tags,
          if (params.locationName != null && params.locationName!.isNotEmpty)
            'location_name': params.locationName,
          if (params.musicId != null) 'music_id': params.musicId,
          if (params.musicStart != null) 'music_start': params.musicStart,
          if (params.musicDuration != null)
            'music_duration': params.musicDuration,
        },
      );

      final status = (res['status'] as String? ?? '').toUpperCase();
      if (res['ok'] == true && status == 'ALLOW') {
        _setState(_state.copyWith(
          stage: UploadStage.allowed,
          progress: 1.0,
          message: '$kindName published! ✓',
        ));
        _scheduleAutoDismiss();
      } else if (res['ok'] == true && status == 'REVIEW') {
        _setState(_state.copyWith(
          stage: UploadStage.review,
          progress: 1.0,
          message: 'Sent for Parent Safety Review',
        ));
        _scheduleAutoDismiss(seconds: 5);
      } else {
        _setState(_state.copyWith(
          stage: UploadStage.failed,
          message: 'Post could not be published right now.',
        ));
      }
    } catch (e) {
      _setState(_state.copyWith(
        stage: UploadStage.failed,
        error: e.toString(),
        message: 'Post failed: $e',
      ));
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _autoDismissTimer?.cancel();
    super.dispose();
  }
}
