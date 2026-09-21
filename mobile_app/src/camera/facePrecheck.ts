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
  if (photo.livenessVerified) return;
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

export type LivenessStage =
  | 'WAITING_FOR_OPEN'
  | 'WAITING_FOR_BLINK'
  | 'WAITING_FOR_REOPEN'
  | 'WAITING_FOR_TURN'
  | 'WAITING_FOR_RETURN'
  | 'WAITING_FOR_SMILE'
  | 'VERIFIED';

export type BlinkStage = LivenessStage;

export interface LivenessProgress {
  action: FaceChallengeAction;
  step: 1 | 2 | 3;
  statusText: string;
  detailText: string;
  isAligned: boolean;
  isComplete: boolean;
  ovalColor: string;
  stage: LivenessStage;
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

/**
 * Strict variant for the live scanner: resolves with detected faces, or
 * rejects when the native detector itself fails. Lets the caller distinguish
 * "no face in frame" (empty array) from "detector unavailable" (throw) so a
 * broken native module surfaces an actionable error instead of an endless
 * "Looking for face…" state.
 */
export async function detectFacesOrThrow(uri: string): Promise<Face[]> {
  if (Platform.OS === 'web' || !uri) return [];
  if (typeof FaceDetection?.detect !== 'function') {
    throw new Error('FaceDetection.detect is not available');
  }
  return FaceDetection.detect(uri, {
    performanceMode: 'fast',
    classificationMode: 'all',
    minFaceSize: 0.15,
  });
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
 * Signed head-turn threshold in degrees of ML Kit rotationY.
 *
 * ML Kit reports positive rotationY when the face turns toward the RIGHT side
 * of the image being processed. The front camera stores the sensor frame
 * unmirrored, so a user turning their head to their OWN left turns toward the
 * right side of that image (positive), and their own right is negative.
 * Each challenge therefore accepts one sign only: a turn in the opposite
 * direction must never verify. Confirm the sign on a physical device if the
 * camera sensor pipeline ever changes.
 */
export const TURN_YAW_THRESHOLD_DEGREES = 15;

/** +1 when TURN_LEFT expects positive rotationY, -1 when TURN_RIGHT expects negative, 0 otherwise. */
function expectedTurnSign(action: FaceChallengeAction): 1 | -1 | 0 {
  if (action === 'TURN_LEFT') return 1;
  if (action === 'TURN_RIGHT') return -1;
  return 0;
}

/** Stage the scanner rests at while no usable face is tracked. */
function waitingStageFor(action: FaceChallengeAction): LivenessStage {
  if (action === 'BLINK') return 'WAITING_FOR_OPEN';
  if (action === 'SMILE') return 'WAITING_FOR_SMILE';
  return 'WAITING_FOR_TURN';
}

/**
 * Real-time liveness state evaluator.
 * Evaluates face alignment, centering, and interactive action progress (e.g. eye blink sequence or head turn).
 */
export function evaluateLivenessFrame(
  photo: { width: number; height: number },
  faces: readonly Face[],
  action: FaceChallengeAction = 'BLINK',
  currentStage: LivenessStage = 'WAITING_FOR_OPEN',
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
      stage: waitingStageFor(action),
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
      stage: waitingStageFor(action),
    };
  }

  const face = faces[0]!;
  // Normalize dimensions so low-res camera preview frame does not fail the resolution gate
  const normalizedPhoto = { width: Math.max(photo.width, 480), height: Math.max(photo.height, 480) };
  const quality = evaluateFaceQuality(normalizedPhoto, [face]);

  // For head turns, non-zero Y rotation and slight displacement are expected while turning
  const isHeadTurnAction = action === 'TURN_LEFT' || action === 'TURN_RIGHT';
  const qualityOk =
    quality.ok ||
    (isHeadTurnAction && (quality.failure === 'head_pose' || quality.failure === 'off_center'));

  if (!qualityOk) {
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
      stage: waitingStageFor(action),
    };
  }

  // Head turn verification: the challenge accepts the correct direction ONLY.
  // A turn past the threshold in the opposite direction is explicitly
  // rejected with corrective guidance instead of silently ignored.
  const turnSign = expectedTurnSign(action);
  if (turnSign !== 0) {
    const rotY = face.rotationY ?? 0;
    const signedYaw = rotY * turnSign;
    const turned = signedYaw >= TURN_YAW_THRESHOLD_DEGREES;
    const wrongWay = signedYaw <= -TURN_YAW_THRESHOLD_DEGREES;
    const turnLabel = action === 'TURN_LEFT' ? 'left ⬅️' : 'right ➡️';
    if (turned) {
      return {
        action,
        step: 3,
        statusText: 'Position Verified!',
        detailText: 'Hold steady, capturing photo…',
        isAligned: true,
        isComplete: true,
        ovalColor: '#10B981',
        stage: 'VERIFIED',
      };
    }
    return {
      action,
      step: 2,
      statusText: wrongWay ? 'Wrong Direction' : action === 'TURN_LEFT' ? 'Turn Head Left' : 'Turn Head Right',
      detailText: wrongWay
        ? `That's the other way — turn your head to your ${turnLabel}`
        : `Turn your head slightly to the ${turnLabel}`,
      isAligned: true,
      isComplete: false,
      ovalColor: wrongWay ? '#F59E0B' : '#38BDF8',
      stage: 'WAITING_FOR_TURN',
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
      ovalColor: smiling ? '#10B981' : '#38BDF8',
      stage: smiling ? 'VERIFIED' : 'WAITING_FOR_SMILE',
    };
  }

  // Default: BLINK verification.
  // The full OPEN -> CLOSED -> OPEN sequence is required: starting with eyes
  // closed, or reopening without a detected close, never advances the stage.
  // Losing the face (or alignment) resets the stage to WAITING_FOR_OPEN, so a
  // partial sequence can never be resumed and reused.
  const leftEye = face.leftEyeOpenProbability;
  const rightEye = face.rightEyeOpenProbability;

  // If eye classification is available from ML Kit:
  if (leftEye !== undefined && rightEye !== undefined) {
    // ML Kit eye probabilities fluctuate slightly even when a user is looking
    // straight at the camera. A lower open threshold removes unnecessary waiting
    // while the closed threshold remains strict enough to require a real blink.
    const eyesOpen = leftEye >= 0.45 && rightEye >= 0.45;
    const eyesClosed = leftEye <= 0.35 && rightEye <= 0.35;

    let nextStage: LivenessStage = currentStage;
    if (currentStage === 'WAITING_FOR_OPEN' || currentStage === 'WAITING_FOR_TURN') {
      if (eyesOpen) nextStage = 'WAITING_FOR_BLINK';
    } else if (currentStage === 'WAITING_FOR_BLINK') {
      if (eyesClosed) nextStage = 'WAITING_FOR_REOPEN';
    } else if (currentStage === 'WAITING_FOR_REOPEN') {
      if (eyesOpen) nextStage = 'VERIFIED';
    }

    if (nextStage === 'VERIFIED') {
      return {
        action,
        step: 3,
        statusText: 'Blink Verified!',
        detailText: 'Liveness confirmed. Capturing photo…',
        isAligned: true,
        isComplete: true,
        ovalColor: '#10B981',
        stage: 'VERIFIED',
      };
    }

    if (nextStage === 'WAITING_FOR_REOPEN') {
      return {
        action,
        step: 2,
        statusText: 'Reopen Eyes',
        detailText: 'Eyes closed detected. Now open your eyes 👀',
        isAligned: true,
        isComplete: false,
        ovalColor: '#06B6D4',
        stage: 'WAITING_FOR_REOPEN',
      };
    }

    // nextStage can only be WAITING_FOR_OPEN or WAITING_FOR_BLINK here.
    // Crucially the stage is never advanced without its entry condition:
    // eyes must be seen OPEN before the user is asked to blink, otherwise a
    // CLOSED -> OPEN partial sequence would verify.
    if (nextStage === 'WAITING_FOR_OPEN') {
      return {
        action,
        step: 2,
        statusText: 'Open Your Eyes',
        detailText: 'Look at the camera with both eyes open 👀',
        isAligned: true,
        isComplete: false,
        ovalColor: '#06B6D4',
        stage: 'WAITING_FOR_OPEN',
      };
    }

    return {
      action,
      step: 2,
      statusText: 'Blink Both Eyes',
      detailText: 'Please blink both eyes naturally 👀',
      isAligned: true,
      isComplete: false,
      ovalColor: '#06B6D4',
      stage: 'WAITING_FOR_BLINK',
    };
  }

  // Fallback if eye probabilities unavailable on device:
  return {
    action,
    step: 2,
    statusText: 'Hold Still',
    detailText: 'Face centered. Hold still to capture…',
    isAligned: true,
    isComplete: false,
    ovalColor: '#38BDF8',
    stage: 'WAITING_FOR_BLINK',
  };
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
  const rotY = face.rotationY ?? 0;
  // Direction-strict, matching the live scanner: TURN_LEFT needs positive
  // rotationY, TURN_RIGHT needs negative. A wrong-direction turn never passes.
  const completed = action === 'BLINK'
    ? face.leftEyeOpenProbability !== undefined && face.rightEyeOpenProbability !== undefined
      && face.leftEyeOpenProbability < 0.40 && face.rightEyeOpenProbability < 0.40
    : action === 'TURN_LEFT'
      ? rotY >= TURN_YAW_THRESHOLD_DEGREES
      : action === 'TURN_RIGHT'
        ? rotY <= -TURN_YAW_THRESHOLD_DEGREES
        : (face.smilingProbability ?? 0) >= 0.65;
  if (!completed) {
    const instruction = action === 'BLINK' ? 'close both eyes' : action === 'TURN_LEFT' ? 'turn your head left' : action === 'TURN_RIGHT' ? 'turn your head right' : 'smile';
    throw new FacePrecheckError('head_pose', `Please ${instruction} and take the photo while holding that position.`);
  }
}
