import type { LoginResponse, SessionUser } from '../api/auth';
import type { StorageBackend } from './backends';

const TOKEN_KEY = 'littlenet.auth.token';
const USER_KEY = 'littlenet.auth.user';
const PENDING_DEST_KEY = 'littlenet.quiz.pending_destination';

export interface PersistedSession {
  token: string;
  user: SessionUser;
}

export type InitialRoute = 'auth' | 'child' | 'child_face' | 'child_quiz' | 'parent' | 'admin';

/** Where the child wanted to go before a mandatory quiz interrupted them. */
export async function savePendingDestination(storage: StorageBackend, destination: string): Promise<void> {
  await storage.setItem(PENDING_DEST_KEY, destination);
}

export async function loadPendingDestination(storage: StorageBackend): Promise<string | null> {
  return storage.getItem(PENDING_DEST_KEY);
}

export async function clearPendingDestination(storage: StorageBackend): Promise<void> {
  await storage.removeItem(PENDING_DEST_KEY);
}

export async function persistSession(storage: StorageBackend, response: LoginResponse): Promise<PersistedSession> {
  const session: PersistedSession = { token: response.token, user: response.user };
  await storage.setItem(TOKEN_KEY, session.token);
  await storage.setItem(USER_KEY, JSON.stringify(session.user));
  return session;
}

export async function restoreSession(storage: StorageBackend): Promise<PersistedSession | null> {
  const [token, rawUser] = await Promise.all([storage.getItem(TOKEN_KEY), storage.getItem(USER_KEY)]);
  if (!token || !rawUser) return null;
  try {
    const user = JSON.parse(rawUser) as SessionUser;
    if (typeof user.user_id !== 'number' || typeof user.role !== 'string') return null;
    return { token, user };
  } catch {
    return null;
  }
}

export async function clearSession(storage: StorageBackend): Promise<void> {
  await Promise.all([storage.removeItem(TOKEN_KEY), storage.removeItem(USER_KEY), storage.removeItem(PENDING_DEST_KEY)]);
}

/**
 * Cold-start routing from a restored session plus the login payload gates.
 * Server state is authoritative; this only restores the last-known route so a
 * relaunch preserves face/quiz gates instead of dropping the child at home.
 */
export function decideInitialRoute(session: PersistedSession | null, onboarding?: { face_required: boolean; quiz_required: boolean }): InitialRoute {
  if (!session) return 'auth';
  if (session.user.role === 'PARENT') return 'parent';
  if (session.user.role === 'ADMIN') return 'admin';
  if (onboarding?.face_required) return 'child_face';
  if (onboarding?.quiz_required || session.user.quiz_required) return 'child_quiz';
  return 'child';
}
