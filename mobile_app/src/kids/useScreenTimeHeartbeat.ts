import { useEffect, useRef } from 'react';
import { AppState, type AppStateStatus } from 'react-native';
import { useQueryClient } from '@tanstack/react-query';
import { sendHeartbeat } from '../api/kidsFeed';
import { ApiError } from '../api/client';
import { useAuth } from '../auth/AuthProvider';
import { useIsOnline } from '../query/client';
import { kidsKeys } from '../query/keys';

const HEARTBEAT_INTERVAL_MS = 30000;

export function useScreenTimeHeartbeat(onLock?: (gate: string) => void): void {
  const { session } = useAuth();
  const online = useIsOnline();
  const queryClient = useQueryClient();
  const token = session?.token;
  const isChild = session?.user?.role === 'CHILD';
  const appStateRef = useRef<AppStateStatus>(AppState.currentState);

  useEffect(() => {
    if (!token || !isChild || !online) return;

    let timer: ReturnType<typeof setInterval> | null = null;
    let abortController: AbortController | null = null;

    async function tick() {
      if (appStateRef.current !== 'active') return;
      abortController = new AbortController();
      try {
        const res = await sendHeartbeat(token!, abortController.signal);
        if (res.locked) {
          onLock?.('screen_time');
          void queryClient.invalidateQueries({ queryKey: kidsKeys.home });
        }
      } catch (err) {
        if (err instanceof ApiError) {
          if (err.status === 423 || err.gate === 'screen_time' || err.gate === 'quiet_hours') {
            onLock?.(err.gate ?? 'screen_time');
            void queryClient.invalidateQueries({ queryKey: kidsKeys.home });
          }
        }
      }
    }

    // Initial heartbeat on active
    void tick();

    timer = setInterval(() => {
      void tick();
    }, HEARTBEAT_INTERVAL_MS);

    const subscription = AppState.addEventListener('change', (nextState: AppStateStatus) => {
      const prev = appStateRef.current;
      appStateRef.current = nextState;
      if (prev !== 'active' && nextState === 'active') {
        void tick();
      }
    });

    return () => {
      if (timer) clearInterval(timer);
      if (abortController) abortController.abort();
      subscription.remove();
    };
  }, [token, isChild, online, queryClient, onLock]);
}
