import type { GateKind } from '../api/errors';

export type ChildRoute = 'FaceEnroll' | 'Quiz' | 'KidsHome';

/** Face gate always wins: a child without enrollment must never reach quiz or home. */
export function childNextRoute(faceRequired: boolean, quizRequired: boolean): ChildRoute {
  if (faceRequired) return 'FaceEnroll';
  if (quizRequired) return 'Quiz';
  return 'KidsHome';
}

/** Map a backend gate to the screen that resolves it, if any. */
export function screenForGate(gate: GateKind): 'FaceEnroll' | 'Quiz' | 'OtpVerify' | null {
  if (gate === 'face') return 'FaceEnroll';
  if (gate === 'quiz') return 'Quiz';
  if (gate === 'parent_verification' || gate === 'email_verification') return 'OtpVerify';
  return null;
}
