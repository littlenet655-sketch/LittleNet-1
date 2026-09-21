import { ApiError } from '../api/errors';
import type { GateKind } from '../api/errors';
import type { OnboardingState } from '../api/auth';

export type ChildRoute =
  | 'FaceEnroll' | 'Quiz' | 'KidsTabs'
  | 'FeedTab' | 'DiscoverTab' | 'CreateTab' | 'ReelsTab' | 'ProfileTab'
  | 'Stories' | 'NotificationsTab' | 'Conversations' | 'Chat'
  | 'ChatDetails' | 'NewMessage' | 'SavedContent' | 'EditProfile' | 'Connections'
  | 'PostDetail' | 'OtherProfile' | 'ProcessingStatus' | 'SafetyCentre' | 'ReportHistory';

/** Face gate always wins: a child without enrollment must never reach quiz or home. */
export function childNextRoute(faceRequired: boolean, quizRequired: boolean): ChildRoute {
  if (faceRequired) return 'FaceEnroll';
  if (quizRequired) return 'Quiz';
  return 'KidsTabs';
}

/** Map a backend gate to the screen that resolves it, if any. */
export function screenForGate(gate: GateKind): 'FaceEnroll' | 'Quiz' | 'OtpVerify' | null {
  if (gate === 'face') return 'FaceEnroll';
  if (gate === 'quiz') return 'Quiz';
  if (gate === 'parent_verification' || gate === 'email_verification') return 'OtpVerify';
  return null;
}

/**
 * Should a 428 onboarding gate from the server trigger an authoritative
 * onboarding refresh (which routes the child to FaceEnroll or Quiz)?
 * Only when the gate is NEW relative to the last known session gates, so a
 * stably gated session never re-fetches in a loop.
 */
export function shouldRefreshOnboardingForGate(
  error: unknown,
  onboarding: OnboardingState | null | undefined,
): boolean {
  if (!(error instanceof ApiError)) return false;
  if (error.status !== 428) return false;
  if (error.gate === 'face') return onboarding?.face_required !== true;
  if (error.gate === 'quiz') return onboarding?.quiz_required !== true;
  return false;
}

/**
 * Server-authoritative display state for the kid self-reset card. Until the
 * server confirms the count, the client must never guess "2 left".
 */
export type ResetsDisplay = 'unknown' | 'available' | 'exhausted';

export function resetsDisplayState(resetsRemaining: number | null): ResetsDisplay {
  if (resetsRemaining === null) return 'unknown';
  return resetsRemaining > 0 ? 'available' : 'exhausted';
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
  current: ChildRoute = 'KidsTabs',
): ChildRoute {
  if (!onboarding) return 'FaceEnroll';
  if (onboarding.face_required) return 'FaceEnroll';
  if (onboarding.quiz_required) return 'Quiz';
  return current === 'FaceEnroll' || current === 'Quiz' ? 'KidsTabs' : current;
}
