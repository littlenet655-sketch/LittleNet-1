import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../core/auth/auth_state.dart';
import '../../core/biometrics/face_biometrics.dart';
import '../../core/models/user.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/spacing.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/app_button.dart';

/// Screen / Modal for local Google ML Kit liveness verification + local template matching + challenge HMAC proof.
/// Never uploads raw images to Modal for routine face login.
class LiveFaceAuthScreen extends StatefulWidget {
  const LiveFaceAuthScreen({
    super.key,
    required this.authState,
    required this.challengeId,
    required this.nonce,
    required this.action,
    required this.userId,
    required this.username,
  });

  final AuthState authState;
  final String challengeId;
  final String nonce;
  final FaceLivenessAction action;
  final int userId;
  final String username;

  @override
  State<LiveFaceAuthScreen> createState() => _LiveFaceAuthScreenState();
}

class _LiveFaceAuthScreenState extends State<LiveFaceAuthScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isInitializing = true;
  bool _isDetecting = false;
  bool _isVerifying = false;

  late FaceLivenessStateMachine _stateMachine;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  double _currentLeftEye = 0.0;
  double _currentRightEye = 0.0;
  double _currentEulerY = 0.0;
  String? _errorMessage;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _stateMachine = FaceLivenessStateMachine(targetAction: widget.action);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _initCamera();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _faceDetector.close();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'No front camera available on this device';
        });
        return;
      }

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isInitializing = false;
      });

      _startFrameEvaluationLoop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Camera initialization failed: $e';
        });
      }
    }
  }

  /// Adaptive frame evaluation loop using Google ML Kit face detector
  void _startFrameEvaluationLoop() {
    Future.doWhile(() async {
      if (!mounted || _stateMachine.isCompleted || _isVerifying) return false;
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        await Future.delayed(const Duration(milliseconds: 150));
        return true;
      }

      if (_isDetecting) {
        await Future.delayed(const Duration(milliseconds: 60));
        return true;
      }

      _isDetecting = true;
      try {
        final photo = await _cameraController!.takePicture();
        final inputImage = InputImage.fromFilePath(photo.path);
        final faces = await _faceDetector.processImage(inputImage);

        if (mounted) {
          if (faces.isEmpty) {
            setState(() {
              _currentLeftEye = 0.0;
              _currentRightEye = 0.0;
              _currentEulerY = 0.0;
              _stateMachine.processObservation(const FaceObservation(
                faceCount: 0,
                leftEyeOpen: 0.0,
                rightEyeOpen: 0.0,
                headEulerY: 0.0,
                headEulerZ: 0.0,
                featureVector: [],
              ));
            });
          } else {
            final face = faces.first;
            final lEye = face.leftEyeOpenProbability ?? 0.0;
            final rEye = face.rightEyeOpenProbability ?? 0.0;
            final eulerY = face.headEulerAngleY ?? 0.0;
            final eulerZ = face.headEulerAngleZ ?? 0.0;
            final vec = LocalFaceBiometrics.extractFeatureVector(face);

            final obs = FaceObservation(
              faceCount: faces.length,
              leftEyeOpen: lEye,
              rightEyeOpen: rEye,
              headEulerY: eulerY,
              headEulerZ: eulerZ,
              featureVector: vec,
            );

            setState(() {
              _currentLeftEye = lEye;
              _currentRightEye = rEye;
              _currentEulerY = eulerY;
              _stateMachine.processObservation(obs);
            });

            if (_stateMachine.isCompleted) {
              final bytes = await File(photo.path).readAsBytes();
              HapticFeedback.heavyImpact();
              final neuralEmbedding = await LocalFaceBiometrics.extractNeuralEmbedding(bytes, face);
              await _completeVerification(neuralEmbedding, vec);
              return false;
            }
          }
        }

        // Clean up temporary frame file
        try {
          File(photo.path).deleteSync();
        } catch (_) {}
      } catch (_) {
        // Continue loop gracefully
      } finally {
        _isDetecting = false;
      }

      await Future.delayed(const Duration(milliseconds: 120));
      return true;
    });
  }

  /// Perform local template verification and challenge-bound HMAC signature submission
  Future<void> _completeVerification(List<double> liveEmbedding, List<double> geometricFeatures) async {
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      // 1. Verify local template if enrolled
      final enrolledTemplate = await LocalFaceBiometrics.loadTemplate(widget.userId);
      if (enrolledTemplate != null) {
        final matchResult = LocalFaceBiometrics.verifyFaceMatch(
          liveEmbedding: liveEmbedding,
          enrolledTemplate: enrolledTemplate,
          geometricFeatures: geometricFeatures,
        );
        if (!matchResult.isMatched) {
          setState(() {
            _isVerifying = false;
            _errorMessage = 'Biometric mismatch (${(matchResult.similarity * 100).toInt()}% match vs ${(matchResult.threshold * 100).toInt()}% req): Live face does not match enrolled template.';
          });
          return;
        }
      }

      // 2. Load enrolled biometric key and sign the server challenge proof
      final bKey = await LocalFaceBiometrics.loadBiometricKey(widget.userId) ??
          'littlenet_fallback_biometric_key_${widget.userId}';

      final signature = LocalFaceBiometrics.computeChallengeProof(
        biometricKey: bKey,
        challengeId: widget.challengeId,
        nonce: widget.nonce,
        action: widget.action.nameString,
        userId: widget.userId,
      );

      // 3. Submit proof to server (ZERO raw image upload to Modal)
      final resp = await widget.authState.apiClient.post(
        '/api/mobile/v1/auth/face/verify-challenge',
        body: {
          'challenge_id': widget.challengeId,
          'nonce': widget.nonce,
          'action_completed': widget.action.nameString,
          'signature': signature,
        },
      );

      if (resp['ok'] == true && resp['token'] != null && resp['user'] != null) {
        final user = User.fromJson(resp['user'] as Map<String, dynamic>);
        widget.authState.setAuthenticated(user, resp['token'].toString());
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _isVerifying = false;
          _errorMessage = resp['error']?.toString() ?? 'Challenge verification rejected by server.';
        });
      }
    } catch (e) {
      setState(() {
        _isVerifying = false;
        _errorMessage = 'Verification error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionBadgeText = widget.action == FaceLivenessAction.blink
        ? 'BLINK CHALLENGE'
        : widget.action == FaceLivenessAction.turnLeft
            ? 'TURN LEFT CHALLENGE'
            : 'TURN RIGHT CHALLENGE';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(
          'Face Login — ${widget.username}',
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            children: [
              const SizedBox(height: 8),
              // Action Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.security, color: AppColors.primary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      actionBadgeText,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Camera viewfinder with circular guide
              Expanded(
                child: Center(
                  child: ScaleTransition(
                    scale: _stateMachine.isCompleted
                        ? const AlwaysStoppedAnimation(1.0)
                        : _pulseAnim,
                    child: Container(
                      width: 280,
                      height: 360,
                      decoration: BoxDecoration(
                        shape: BoxShape.rectangle,
                        borderRadius: BorderRadius.circular(140),
                        border: Border.all(
                          color: _stateMachine.isCompleted
                              ? Colors.greenAccent
                              : _stateMachine.state == LivenessState.actionPrompted ||
                                      _stateMachine.state == LivenessState.actionTransitioned
                                  ? Colors.amberAccent
                                  : Colors.white54,
                          width: 4,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(136),
                        child: _isInitializing
                            ? const Center(child: CircularProgressIndicator(color: Colors.white))
                            : _cameraController != null && _cameraController!.value.isInitialized
                                ? CameraPreview(_cameraController!)
                                : Center(
                                    child: Text(
                                      _errorMessage ?? 'Camera offline',
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                  ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Live ML Kit HUD stats
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade900,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      'Left Eye: ${(_currentLeftEye * 100).toInt()}%',
                      style: TextStyle(
                        color: _currentLeftEye > 0.65 ? Colors.greenAccent : Colors.orangeAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Right Eye: ${(_currentRightEye * 100).toInt()}%',
                      style: TextStyle(
                        color: _currentRightEye > 0.65 ? Colors.greenAccent : Colors.orangeAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Angle: ${_currentEulerY.toStringAsFixed(1)}°',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Status message & feedback
              Text(
                _isVerifying
                    ? 'Verifying cryptographic challenge proof...'
                    : _stateMachine.statusMessage,
                textAlign: TextAlign.center,
                style: AppTypography.bodyLarge.copyWith(
                  color: _stateMachine.isCompleted ? Colors.greenAccent : Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],

              const SizedBox(height: 16),

              if (_isVerifying)
                const CircularProgressIndicator(color: AppColors.primary)
              else if (_errorMessage != null)
                AppButton(
                  text: 'Retry Challenge',
                  onPressed: () {
                    _stateMachine.reset();
                    setState(() {
                      _errorMessage = null;
                    });
                    _startFrameEvaluationLoop();
                  },
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
