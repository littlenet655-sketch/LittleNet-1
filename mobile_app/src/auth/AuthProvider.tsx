import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { fetchMe, logout as apiLogout } from '../api/auth';
import type { LoginResponse, SessionUser } from '../api/auth';
import { ApiError, setUnauthorizedHandler } from '../api/client';
import { clearSession, persistSession, restoreSession } from './session';
import type { PersistedSession } from './session';
import { secureStoreBackend } from './storage';

interface AuthState {
  status: 'loading' | 'signedOut' | 'signedIn';
  session: PersistedSession | null;
  onboarding: { face_required: boolean; quiz_required: boolean } | null;
  signIn: (response: LoginResponse) => Promise<void>;
  signOut: () => Promise<void>;
  refreshMe: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<AuthState['status']>('loading');
  const [session, setSession] = useState<PersistedSession | null>(null);
  const [onboarding, setOnboarding] = useState<AuthState['onboarding']>(null);

  const signOut = useCallback(async () => {
    const token = session?.token;
    setSession(null);
    setOnboarding(null);
    setStatus('signedOut');
    try {
      if (token) await apiLogout(token);
    } catch {
      // Logout is best-effort; local tokens are already cleared.
    }
    await clearSession(secureStoreBackend);
  }, [session?.token]);

  // Centralized 401 -> safe return to login.
  useEffect(() => {
    setUnauthorizedHandler(() => {
      void signOut();
    });
    return () => setUnauthorizedHandler(null);
  }, [signOut]);

  // Cold-start restoration: tokens + cached user, then server revalidation.
  useEffect(() => {
    let active = true;
    (async () => {
      const restored = await restoreSession(secureStoreBackend);
      if (!active) return;
      if (!restored) {
        setStatus('signedOut');
        return;
      }
      setSession(restored);
      setStatus('signedIn');
      try {
        const me = await fetchMe(restored.token);
        if (!active) return;
        setSession({ token: restored.token, user: me.user });
        await persistSession(secureStoreBackend, { ok: true, token: restored.token, auth_method: 'RESTORED', user: me.user });
      } catch (error) {
        if (!active) return;
        if (error instanceof ApiError && error.status === 401) {
          await clearSession(secureStoreBackend);
          setSession(null);
          setStatus('signedOut');
        }
        // Other failures keep the cached session (offline launch).
      }
    })();
    return () => {
      active = false;
    };
  }, []);

  const signIn = useCallback(async (response: LoginResponse) => {
    const next = await persistSession(secureStoreBackend, response);
    setSession(next);
    setOnboarding(response.onboarding ?? null);
    setStatus('signedIn');
  }, []);

  const refreshMe = useCallback(async () => {
    if (!session) return;
    const me = await fetchMe(session.token);
    const next: PersistedSession = { token: session.token, user: me.user };
    setSession(next);
    await persistSession(secureStoreBackend, { ok: true, token: next.token, auth_method: 'REFRESH', user: next.user });
  }, [session]);

  const value = useMemo<AuthState>(
    () => ({ status, session, onboarding, signIn, signOut, refreshMe }),
    [status, session, onboarding, signIn, signOut, refreshMe],
  );
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}

export function useSessionUser(): SessionUser | null {
  return useAuth().session?.user ?? null;
}
