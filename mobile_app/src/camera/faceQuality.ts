export interface DetectedFaceLike {
  frame: { width: number; height: number; left: number; top: number };
  rotationX?: number;
  rotationY?: number;
  rotationZ?: number;
}

export type FaceQualityFailure =
  | 'low_quality'
  | 'no_face'
  | 'multiple_faces'
  | 'face_too_small'
  | 'off_center'
  | 'head_pose';

export interface FaceQualityResult {
  ok: boolean;
  failure?: FaceQualityFailure;
  message?: string;
}

/**
 * Cheap, deterministic capture checks. These only decide whether an image is
 * suitable to send to the server; they never establish identity or liveness.
 */
export function evaluateFaceQuality(
  image: { width: number; height: number },
  faces: readonly DetectedFaceLike[],
): FaceQualityResult {
  if (image.width < 480 || image.height < 480) {
    return { ok: false, failure: 'low_quality', message: 'Move to better light and take a clearer photo.' };
  }
  if (faces.length === 0) {
    return { ok: false, failure: 'no_face', message: 'Move into the frame so we can see your face.' };
  }
  if (faces.length > 1) {
    return { ok: false, failure: 'multiple_faces', message: 'Only one person in frame.' };
  }

  const face = faces[0];
  if (!face) return { ok: false, failure: 'no_face', message: 'Move into the frame so we can see your face.' };

  const faceWidthRatio = face.frame.width / image.width;
  if (!Number.isFinite(faceWidthRatio) || faceWidthRatio < 0.18) {
    return { ok: false, failure: 'face_too_small', message: 'Move closer.' };
  }

  const centerX = face.frame.left + face.frame.width / 2;
  const centerY = face.frame.top + face.frame.height / 2;
  if (Math.abs(centerX / image.width - 0.5) > 0.22 || Math.abs(centerY / image.height - 0.5) > 0.28) {
    return { ok: false, failure: 'off_center', message: 'Center your face in the oval.' };
  }

  if (
    Math.abs(face.rotationX ?? 0) > 25 ||
    Math.abs(face.rotationY ?? 0) > 25 ||
    Math.abs(face.rotationZ ?? 0) > 30
  ) {
    return { ok: false, failure: 'head_pose', message: 'Look straight at the camera.' };
  }

  return { ok: true };
}