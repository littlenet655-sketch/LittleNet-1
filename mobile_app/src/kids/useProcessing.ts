import { useCallback, useEffect, useRef, useState } from 'react';
import { fetchProcessingStatus } from '../api/kidsUpload';
import { useAuth } from '../auth/AuthProvider';
import { MAX_POLL_ATTEMPTS, MAX_POLL_DURATION_MS, isTerminalStage, processingStage } from './social';

/** Foreground-only bounded processing polling with a manual refresh escape hatch. */
export function useProcessingStatus(postId: number | null, active: boolean) {
  const { session } = useAuth();
  const [status, setStatus] = useState('PROCESSING');
  const [moderation, setModeration] = useState<string | null>(null);
  const [retryable, setRetryable] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [attempts, setAttempts] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const attemptsRef = useRef(0);
  const startedAtRef = useRef(Date.now());
  const stage = processingStage(status, moderation, retryable);

  useEffect(() => {
    attemptsRef.current = 0;
    startedAtRef.current = Date.now();
    setAttempts(0);
    setStatus('PROCESSING');
    setModeration(null);
    setRetryable(false);
    setError(null);
  }, [postId]);

  const fetchOnce = useCallback(async () => {
    if (!session || !postId) return null;
    const result = await fetchProcessingStatus(session.token, postId);
    setStatus(result.status);
    setModeration(result.moderation_status ?? null);
    setRetryable(Boolean(result.retryable));
    setError(result.error ?? null);
    return result;
  }, [postId, session?.token]);

  useEffect(() => {
    if (!postId || !active || !session || isTerminalStage(stage)) return;
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout> | null = null;

    async function tick() {
      if (cancelled) return;
      if (attemptsRef.current >= MAX_POLL_ATTEMPTS || Date.now() - startedAtRef.current >= MAX_POLL_DURATION_MS) return;
      attemptsRef.current += 1;
      setAttempts(attemptsRef.current);
      try {
        const result = await fetchOnce();
        if (cancelled || !result) return;
        const nextStage = processingStage(result.status, result.moderation_status, Boolean(result.retryable));
        if (isTerminalStage(nextStage)) return;
      } catch (reason) {
        if (cancelled) return;
        setError(reason);
      }
      if (attemptsRef.current < MAX_POLL_ATTEMPTS && Date.now() - startedAtRef.current < MAX_POLL_DURATION_MS) {
        timer = setTimeout(tick, Math.min(2000 + attemptsRef.current * 500, 8000));
      }
    }

    void tick();
    return () => {
      cancelled = true;
      if (timer) clearTimeout(timer);
    };
  }, [active, fetchOnce, postId, session?.token, stage]);

  const refresh = useCallback(async () => {
    setRefreshing(true);
    try { await fetchOnce(); } catch (reason) { setError(reason); } finally { setRefreshing(false); }
  }, [fetchOnce]);

  return { status, moderation, error, attempts, stage, refreshing, refresh };
}
