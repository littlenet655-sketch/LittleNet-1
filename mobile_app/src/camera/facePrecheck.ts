import { Platform } from 'react-native';
import FaceDetection, { type Face } from '@react-native-ml-kit/face-detection';
import type { CapturedPhoto } from './capture';
import { evaluateFaceQuality, type FaceQualityFailure } from './faceQuality';

export class FacePrecheckError extends Error {
  readonly code: FaceQualityFailure | 'missing_image' | 'native_unavailable';

  constructor(code: FacePrecheckError['code'], message: string) {
    super(message);
    this.name = 'FacePrecheckError';
    this.code = code;
  }
}

/**
 * ML Kit is a local capture-quality gate only. The returned image still goes
 * through the server's authoritative liveness and Facenet512 verification.
 */
export async function precheckFace(photo: CapturedPhoto): Promise<void> {
  // The submission target is a native Android/iOS build. Keep web previews
  // usable without pretending that web has completed the native check.
  if (Platform.OS === 'web') return;
  if (!photo.uri) {
    throw new FacePrecheckError('missing_image', 'The camera image could not be checked. Please retake it.');
  }

  let faces: Face[];
  try {
    if (typeof FaceDetection?.detect !== 'function') {
      throw new Error('FaceDetection.detect is not a function');
    }
    faces = await FaceDetection.detect(photo.uri, {
      performanceMode: 'accurate',
      classificationMode: 'all',
      minFaceSize: 0.1,
    });
  } catch {
    throw new FacePrecheckError(
      'native_unavailable',
      'The on-device face check is unavailable. Rebuild the Android app before continuing.',
    );
  }

  const result = evaluateFaceQuality(photo, faces);
  if (!result.ok) {
    throw new FacePrecheckError(result.failure ?? 'no_face', result.message ?? 'Retake the photo and try again.');
  }
}

export type FaceChallengeAction = 'BLINK' | 'TURN_LEFT' | 'TURN_RIGHT' | 'SMILE';

export type BlinkStage = 'WAITING_FOR_OPEN' | 'WAITING_FOR_BLINK' | 'WAITING_FOR_REOPEN' | 'VERIFIED';

export interface LivenessProgress {
  action: FaceChallengeAction;
  step: 1 | 2 | 3;
  statusText: string;
  detailText: string;
  isAligned: boolean;
  isComplete: boolean;
  ovalColor: string;
  stage: BlinkStage;
}

/** Rapid face detection using on-device Google ML Kit during live camera scanning. */
export async function detectFacesInImage(uri: string): Promise<Face[]> {
  if (Platform.OS === 'web' || !uri) return [];
  if (typeof FaceDetection?.detect !== 'function') return [];
  try {
    return await FaceDetection.detect(uri, {
      performanceMode: 'fast',
      classificationMode: 'all',
      minFaceSize: 0.15,
    });
  } catch {
    return [];
  }
}

/** Safe temporary frame deletion that never throws. */
export async function cleanupTempFrame(uri?: string): Promise<void> {
  if (Platform.OS === 'web' || !uri) return;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const FileSystem = require('expo-file-system');
    if (typeof FileSystem?.deleteAsync === 'function') {
      await FileSystem.deleteAsync(uri, { idempotent: true });
    }
  } catch {
    // Ignore cleanup errors during frame streaming
  }
}

/**
 * Real-time liveness state evaluator.
 * Evaluates face alignment, centering, and interactive action progress (e.g. eye blink sequence).
 */
export function evaluateLivenessFrame(
  photo: { width: number; height: number },
  faces: readonly Face[],
  action: FaceChallengeAction = 'BLINK',
  currentBlinkStage: BlinkStage = 'WAITING_FOR_OPEN',
): LivenessProgress {
  if (faces.length === 0) {
    return {
      action,
      step: 1,
      statusText: 'Looking for face…',
      detailText: 'Center your face inside the oval',
      isAligned: false,
      isComplete: false,
      ovalColor: '#94A3B8',
      stage: 'WAITING_FOR_OPEN',
    };
  }

  if (faces.length > 1) {
    return {
      action,
      step: 1,
      statusText: 'Multiple Faces Detected',
      detailText: 'Only one person must be in frame',
      isAligned: false,
      isComplete: false,
      ovalColor: '#EF4444',
      stage: 'WAITING_FOR_OPEN',
    };
  }

  const face = faces[0]!;
  const quality = evaluateFaceQuality(photo, [face]);

  if (!quality.ok) {
    let detail = quality.message ?? 'Align face in oval';
    if (quality.failure === 'face_too_small') detail = 'Move a little closer to the camera';
    if (quality.failure === 'off_center') detail = 'Center your face inside the oval';
    if (quality.failure === 'head_pose' && action === 'BLINK') detail = 'Look straight at the camera';

    return {
      action,
      step: 1,
      statusText: 'Adjust Position',
      detailText: detail,
      isAligned: false,
      isComplete: false,
      ovalColor: '#F59E0B',
      stage: 'WAITING_FOR_OPEN',
    };
  }

  // Face is aligned and well-positioned! Step 2: Liveness Verification
  if (action === 'TURN_LEFT') {
    const turned = (face.rotationY ?? 0) >= 18;
    return {
      action,
      step: turned ? 3 : 2,
      statusText: turned ? 'Position Verified!' : 'Turn Head Left',
      detailText: turned ? 'Hold steady, capturing photo…' : 'Turn your head slightly to the left ⬅️',
      isAligned: true,
      isComplete: turned,
      ovalColor: turned ? '#10B981' : '#38BDF8',
      stage: turned ? 'VERIFIED' : 'WAITING_FOR_BLINK',
    };
  }

  if (action === 'TURN_RIGHT') {
    const turned = (face.rotationY ?? 0) <= -18;
    return {
      action,
      step: turned ? 3 : 2,
      statusText: turned ? 'Position Verified!' : 'Turn Head Right',
      detailText: turned ? 'Hold steady, capturing photo…' : 'Turn your head slightly to the right ➡️',
      isAligned: true,
      isComplete: turned,
      ovalColor: turned ? '#10B981' : '#38BDF8',
      stage: turned ? 'VERIFIED' : 'WAITING_FOR_BLINK',
    };
  }

  if (action === 'SMILE') {
    const smiling = (face.smilingProbability ?? 0) >= 0.65;
    return {
      action,
      step: smiling ? 3 : 2,
      statusText: smiling ? 'Smile Confirmed!' : 'Smile for Camera',
      detailText: smiling ? 'Hold steady, capturing photo…' : 'Please smile at the camera 😊',
      isAligned: true,
      isComplete: smiling,
      ovalColor: turnedOrSmilingColor(smiling),
      stage: smiling ? 'VERIFIED' : 'WAITING_FOR_BLINK',
    };
  }

  // Default: BLINK verification
  const leftEye = face.leftEyeOpenProbability;
  const rightEye = face.rightEyeOpenProbability;

  // If eye classification is available from ML Kit:
  if (leftEye !== undefined && rightEye !== undefined) {
    const eyesOpen = leftEye > 0.55 && rightEye > 0.55;
    const eyesClosed = leftEye < 0.35 && rightEye < 0.35;

    let nextStage: BlinkStage = currentBlinkStage;
    if (currentBlinkStage === 'WAITING_FOR_OPEN') {
      if (eyesOpen) nextStage = 'WAITING_FOR_BLINK';
    } else if (currentBlinkStage === 'WAITING_FOR_BLINK') {
      if (eyesClosed) nextStage = 'WAITING_FOR_REOPEN';
    } else if (currentBlinkStage === 'WAITING_FOR_REOPEN') {
      if (eyesOpen) nextStage = 'VERIFIED';
    }

    const verified = nextStage === 'VERIFIED';
    return {
      action,
      step: verified ? 3 : 2,
      statusText: verified
        ? 'Blink Verified!'
        : nextStage === 'WAITING_FOR_REOPEN'
          ? 'Reopen Eyes'
          : 'Blink Both Eyes',
      detailText: verified
        ? 'Liveness verified, capturing photo…'
        : nextStage === 'WAITING_FOR_REOPEN'
          ? 'Blink detected! Now open your eyes…'
          : 'Please blink both eyes naturally 👀',
      isAligned: true,
      isComplete: verified,
      ovalColor: verified ? '#10B981' : '#38BDF8',
      stage: nextStage,
    };
  }

  // Fallback if eye classification probability is not emitted by hardware:
  return {
    action,
    step: 2,
    statusText: 'Face Aligned',
    detailText: 'Please blink both eyes naturally 👀',
    isAligned: true,
    isComplete: false,
    ovalColor: '#38BDF8',
    stage: 'WAITING_FOR_BLINK',
  };
}

function turnedOrSmilingColor(ok: boolean): string {
  return ok ? '#10B981' : '#38BDF8';
}

/** Additional on-device proof for the server-selected liveness action. */
export async function precheckFaceChallenge(photo: CapturedPhoto, action: FaceChallengeAction): Promise<void> {
  if (Platform.OS === 'web') {
    throw new FacePrecheckError('native_unavailable', 'Face login requires the Android app.');
  }
  if (!photo.uri) {
    throw new FacePrecheckError('missing_image', 'The camera image could not be checked. Please retake it.');
  }

  // If real-time liveness scanner already verified the challenge action, precheck passes
  if (photo.livenessVerified) {
    await precheckFace(photo);
    return;
  }

  let faces: Face[];
  try {
    faces = await FaceDetection.detect(photo.uri, {
      performanceMode: 'accurate',
      classificationMode: 'all',
      minFaceSize: 0.1,
    });
  } catch {
    throw new FacePrecheckError('native_unavailable', 'The on-device liveness check is unavailable. Rebuild the Android app.');
  }
  if (faces.length !== 1 || !faces[0]) {
    throw new FacePrecheckError(
      faces.length > 1 ? 'multiple_faces' : 'no_face',
      faces.length > 1 ? 'Only one person can complete face login.' : 'Keep your face inside the oval.',
    );
  }

  const face = faces[0];
  if (photo.width < 480 || photo.height < 480 || face.frame.width / photo.width < 0.18) {
    throw new FacePrecheckError('low_quality', 'Move closer and take a clearer challenge photo.');
  }
  const completed = action === 'BLINK'
    ? face.leftEyeOpenProbability !== undefined && face.rightEyeOpenProbability !== undefined
      && face.leftEyeOpenProbability < 0.35 && face.rightEyeOpenProbability < 0.35
    : action === 'TURN_LEFT'
      ? (face.rotationY ?? 0) >= 18
      : action === 'TURN_RIGHT'
        ? (face.rotationY ?? 0) <= -18
        : (face.smilingProbability ?? 0) >= 0.65;
  if (!completed) {
    const instruction = action === 'BLINK' ? 'close both eyes' : action === 'TURN_LEFT' ? 'turn your head left' : action === 'TURN_RIGHT' ? 'turn your head right' : 'smile';
    throw new FacePrecheckError('head_pose', `Please ${instruction} and take the photo while holding that position.`);
  }
}
