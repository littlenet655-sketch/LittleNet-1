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