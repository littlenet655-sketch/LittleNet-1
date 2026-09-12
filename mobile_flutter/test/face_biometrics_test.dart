import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:littlenet_native/core/biometrics/face_biometrics.dart';

void main() {
  group('FaceLivenessStateMachine - Real Temporal Transitions', () {
    test('Blink challenge requires true multi-frame state machine transitions', () {
      final sm = FaceLivenessStateMachine(targetAction: FaceLivenessAction.blink);
      expect(sm.state, LivenessState.searchingFace);
      expect(sm.isCompleted, false);

      // Frame 1: Eyes open facing center
      sm.processObservation(const FaceObservation(
        faceCount: 1,
        leftEyeOpen: 0.92,
        rightEyeOpen: 0.89,
        headEulerY: 1.2,
        headEulerZ: 0.5,
        featureVector: [],
      ));
      expect(sm.state, LivenessState.calibratingCenter);
      expect(sm.isCompleted, false);

      // Frame 2 & 3: Calibrate center
      sm.processObservation(const FaceObservation(
        faceCount: 1,
        leftEyeOpen: 0.91,
        rightEyeOpen: 0.90,
        headEulerY: 0.8,
        headEulerZ: 0.2,
        featureVector: [],
      ));
      sm.processObservation(const FaceObservation(
        faceCount: 1,
        leftEyeOpen: 0.93,
        rightEyeOpen: 0.91,
        headEulerY: 0.0,
        headEulerZ: 0.0,
        featureVector: [],
      ));
      expect(sm.state, LivenessState.actionPrompted);
      expect(sm.isCompleted, false);

      // Frame 4: Still photo (remains open) - MUST NOT COMPLETE
      sm.processObservation(const FaceObservation(
        faceCount: 1,
        leftEyeOpen: 0.93,
        rightEyeOpen: 0.91,
        headEulerY: 0.0,
        headEulerZ: 0.0,
        featureVector: [],
      ));
      expect(sm.state, LivenessState.actionPrompted);
      expect(sm.isCompleted, false);

      // Frame 5: Natural Blink - Eyes close
      sm.processObservation(const FaceObservation(
        faceCount: 1,
        leftEyeOpen: 0.12,
        rightEyeOpen: 0.10,
        headEulerY: 0.5,
        headEulerZ: 0.1,
        featureVector: [],
      ));
      expect(sm.state, LivenessState.actionTransitioned);
      expect(sm.isCompleted, false);

      // Frame 6: Eyes reopen after blink
      sm.processObservation(const FaceObservation(
        faceCount: 1,
        leftEyeOpen: 0.88,
        rightEyeOpen: 0.86,
        headEulerY: 0.2,
        headEulerZ: 0.0,
        featureVector: [],
      ));
      sm.processObservation(const FaceObservation(
        faceCount: 1,
        leftEyeOpen: 0.90,
        rightEyeOpen: 0.89,
        headEulerY: 0.0,
        headEulerZ: 0.0,
        featureVector: [],
      ));

      expect(sm.state, LivenessState.completed);
      expect(sm.isCompleted, true);
      expect(sm.statusMessage, contains('Verified'));
    });

    test('Turn Left challenge rejects static photo and requires head rotation + return to center', () {
      final sm = FaceLivenessStateMachine(targetAction: FaceLivenessAction.turnLeft);

      // Calibrate center (3 frames)
      for (int i = 0; i < 3; i++) {
        sm.processObservation(const FaceObservation(
          faceCount: 1,
          leftEyeOpen: 0.9,
          rightEyeOpen: 0.9,
          headEulerY: 0.0,
          headEulerZ: 0.0,
          featureVector: [],
        ));
      }
      expect(sm.state, LivenessState.actionPrompted);

      // Wrong action: Turning right when left was requested
      sm.processObservation(const FaceObservation(
        faceCount: 1,
        leftEyeOpen: 0.9,
        rightEyeOpen: 0.9,
        headEulerY: -25.0, // Right turn
        headEulerZ: 0.0,
        featureVector: [],
      ));
      expect(sm.state, LivenessState.actionPrompted);
      expect(sm.isCompleted, false);

      // Correct action: Turn left across frames
      sm.processObservation(const FaceObservation(
        faceCount: 1,
        leftEyeOpen: 0.9,
        rightEyeOpen: 0.9,
        headEulerY: 22.5,
        headEulerZ: 0.0,
        featureVector: [],
      ));
      sm.processObservation(const FaceObservation(
        faceCount: 1,
        leftEyeOpen: 0.9,
        rightEyeOpen: 0.9,
        headEulerY: 24.0,
        headEulerZ: 0.0,
        featureVector: [],
      ));
      expect(sm.state, LivenessState.actionTransitioned);
      expect(sm.isCompleted, false);

      // Return to center
      sm.processObservation(const FaceObservation(
        faceCount: 1,
        leftEyeOpen: 0.9,
        rightEyeOpen: 0.9,
        headEulerY: 2.0,
        headEulerZ: 0.0,
        featureVector: [],
      ));
      sm.processObservation(const FaceObservation(
        faceCount: 1,
        leftEyeOpen: 0.9,
        rightEyeOpen: 0.9,
        headEulerY: 0.5,
        headEulerZ: 0.0,
        featureVector: [],
      ));

      expect(sm.state, LivenessState.completed);
      expect(sm.isCompleted, true);
    });

    test('Multiple faces in frame immediately flags error state', () {
      final sm = FaceLivenessStateMachine(targetAction: FaceLivenessAction.blink);
      sm.processObservation(const FaceObservation(
        faceCount: 2,
        leftEyeOpen: 0.9,
        rightEyeOpen: 0.9,
        headEulerY: 0.0,
        headEulerZ: 0.0,
        featureVector: [],
      ));
      expect(sm.state, LivenessState.multipleFacesError);
      expect(sm.isCompleted, false);
    });
  });

  group('LocalFaceBiometrics - Neural Embeddings & Threshold Calibration', () {
    test('Controlled validation set: genuine vs impostor 192-D embedding distribution', () {
      // 10 genuine comparison pairs (same subject with subtle noise/lighting/expression variations)
      final rng = Random(12345);
      final genuineScores = <double>[];
      final impostorScores = <double>[];

      // Generate 5 distinct enrolled identities
      final identities = List.generate(5, (_) {
        final raw = List.generate(192, (_) => rng.nextDouble() * 2.0 - 1.0);
        return LocalFaceBiometrics.l2Normalize(raw);
      });

      // 1. Genuine comparisons (varying same identity with +/- 0.08 perturbation)
      for (final template in identities) {
        for (int sample = 0; sample < 2; sample++) {
          final live = List.generate(192, (i) {
            return template[i] + (rng.nextDouble() - 0.5) * 0.12;
          });
          final normLive = LocalFaceBiometrics.l2Normalize(live);
          final sim = LocalFaceBiometrics.computeSimilarity(template, normLive);
          genuineScores.add(sim);
        }
      }

      // 2. Impostor comparisons (comparing distinct identities against each other)
      for (int i = 0; i < identities.length; i++) {
        for (int j = i + 1; j < identities.length; j++) {
          final sim = LocalFaceBiometrics.computeSimilarity(identities[i], identities[j]);
          impostorScores.add(sim);
        }
      }

      final minGenuine = genuineScores.reduce(min);
      final maxGenuine = genuineScores.reduce(max);
      final minImpostor = impostorScores.reduce(min);
      final maxImpostor = impostorScores.reduce(max);

      // Calibrated threshold check
      const threshold = LocalFaceBiometrics.neuralMatchThreshold; // 0.70
      final falseRejects = genuineScores.where((s) => s < threshold).length;
      final falseAccepts = impostorScores.where((s) => s >= threshold).length;

      expect(minGenuine, greaterThan(0.70));
      expect(maxGenuine, lessThanOrEqualTo(1.0));
      expect(minImpostor, greaterThanOrEqualTo(-1.0));
      expect(maxImpostor, lessThan(0.60));
      expect(falseRejects, 0, reason: 'False reject count must be 0 in controlled validation');
      expect(falseAccepts, 0, reason: 'False accept count must be 0 in controlled validation');
    });

    test('Multi-frame enrollment computes L2-normalized centroid template', () {
      final rng = Random(42);
      final frames = List.generate(4, (_) {
        final raw = List.generate(192, (_) => rng.nextDouble() * 2.0 - 1.0);
        return LocalFaceBiometrics.l2Normalize(raw);
      });

      final template = LocalFaceBiometrics.createEnrolledTemplate(frames);
      expect(template.length, 192);

      // Verify template is unit vector (L2 norm == 1.0)
      final normSq = template.fold(0.0, (sum, x) => sum + x * x);
      expect(sqrt(normSq), closeTo(1.0, 1e-6));
    });

    test('verifyFaceMatch checks both neural similarity and geometric pose validity', () {
      final rng = Random(77);
      final rawA = List.generate(192, (_) => rng.nextDouble() * 2.0 - 1.0);
      final template = LocalFaceBiometrics.l2Normalize(rawA);

      // Front-facing live sample (matching)
      final matchingLive = List.generate(192, (i) => template[i] + (rng.nextDouble() - 0.5) * 0.05);
      final normMatching = LocalFaceBiometrics.l2Normalize(matchingLive);

      // Valid centered geometric pose
      final validGeom = List.filled(32, 0.5); // yaw = 0 deg

      final resMatch = LocalFaceBiometrics.verifyFaceMatch(
        liveEmbedding: normMatching,
        enrolledTemplate: template,
        geometricFeatures: validGeom,
      );
      expect(resMatch.isMatched, isTrue);
      expect(resMatch.poseValid, isTrue);

      // Off-pose face (yaw > 25 deg)
      final invalidGeom = List.filled(32, 0.5);
      invalidGeom[30] = 0.65; // yaw = (0.65 * 360) - 180 = +54 degrees

      final resOffPose = LocalFaceBiometrics.verifyFaceMatch(
        liveEmbedding: normMatching,
        enrolledTemplate: template,
        geometricFeatures: invalidGeom,
      );
      expect(resOffPose.isMatched, isFalse);
      expect(resOffPose.poseValid, isFalse);
    });

    test('Cryptographic HMAC challenge proof binds challenge_id, nonce, action, and user_id', () {
      const secretKey = '0123456789abcdef0123456789abcdef';
      const challengeId = 'e1a2b3c4-5678-90ab-cdef-1234567890ab';
      const nonce = '9f8e7d6c5b4a39281706';
      const action = 'BLINK';
      const userId = 42;

      final proof = LocalFaceBiometrics.computeChallengeProof(
        biometricKey: secretKey,
        challengeId: challengeId,
        nonce: nonce,
        action: action,
        userId: userId,
      );

      expect(proof, isNotEmpty);
      expect(proof.length, 64); // SHA-256 hex string

      // Proof is deterministic for same inputs
      final proof2 = LocalFaceBiometrics.computeChallengeProof(
        biometricKey: secretKey,
        challengeId: challengeId,
        nonce: nonce,
        action: action,
        userId: userId,
      );
      expect(proof, proof2);

      // Tampered action or nonce produces completely different proof
      final tamperedProof = LocalFaceBiometrics.computeChallengeProof(
        biometricKey: secretKey,
        challengeId: challengeId,
        nonce: 'tampered_nonce',
        action: action,
        userId: userId,
      );
      expect(proof, isNot(tamperedProof));
    });
  });
}
