import type { GateKind } from '../api/errors';
import type { OnboardingState } from '../api/auth';

export type ChildRoute =
  | 'FaceEnroll' | 'Quiz' | 'KidsHome' | 'KidsTabs'
  | 'FeedTab' | 'DiscoverTab' | 'CreateTab' | 'ReelsTab' | 'ProfileTab'
  | 'Stories' | 'NotificationsTab' | 'Conversations' | 'Chat'
  | 'ChatDetails' | 'NewMessage' | 'SavedContent' | 'EditProfile' | 'Connections'
  | 'PostDetail' | 'OtherProfile' | 'ProcessingStatus' | 'SafetyCentre' | 'ReportHistory';

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

/**
 * Reactive child route from authoritative gates.
 * Order: face -> quiz -> home. Unknown/missing onboarding ALWAYS fails
 * closed to FaceEnroll: a stale cached quiz flag must never bypass unknown
 * face-enrollment state.
 */
export function resolveChildRoute(
  onboarding: OnboardingState | null | undefined,
  _fallbackQuizRequired: boolean,
  current: ChildRoute = 'KidsHome',
): ChildRoute {
  if (!onboarding) return 'FaceEnroll';
  if (onboarding.face_required) return 'FaceEnroll';
  if (onboarding.quiz_required) return 'Quiz';
  return current === 'FaceEnroll' || current === 'Quiz' ? 'KidsTabs' : current;
}
