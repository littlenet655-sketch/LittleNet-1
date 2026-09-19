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

export type FaceChallengeAction = 'BLINK' | 'TURN_LEFT' | 'TURN_RIGHT';

/** Additional on-device proof for the server-selected liveness action. */
export async function precheckFaceChallenge(photo: CapturedPhoto, action: FaceChallengeAction): Promise<void> {
  if (Platform.OS === 'web') {
    throw new FacePrecheckError('native_unavailable', 'Face login requires the Android app.');
  }
  if (!photo.uri) {
    throw new FacePrecheckError('missing_image', 'The camera image could not be checked. Please retake it.');
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
      : (face.rotationY ?? 0) <= -18;
  if (!completed) {
    const instruction = action === 'BLINK' ? 'close both eyes' : action === 'TURN_LEFT' ? 'turn your head left' : 'turn your head right';
    throw new FacePrecheckError('head_pose', `Please ${instruction} and take the photo while holding that position.`);
  }
}
