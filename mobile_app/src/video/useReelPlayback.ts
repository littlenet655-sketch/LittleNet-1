import { useCallback, useEffect, useRef, useState } from 'react';
import { useVideoPlayer } from 'expo-video';
import type { FeedItem } from '../api/kidsFeed';
import { refreshCuratedReelPlayback, refreshReelPlayback } from '../api/kidsFeed';
import { getBufferOptions } from './playbackPolicy';
import { ReelMetricsTracker } from './reelPlaybackMetrics';
import type { ImpressionEventPayload, PlaybackPolicy, PlaybackState } from './types';

const BUFFERING_DEBOUNCE_MS = 300;
const PREEMPTIVE_REFRESH_WINDOW_SEC = 45;

export function useReelPlayback({
  item,
  active,
  nearby,
  paused,
  token,
  policy = 'NORMAL',
  onMetricsFlush,
}: {
  item: FeedItem;
  active: boolean;
  nearby: boolean;
  paused: boolean;
  token?: string;
  policy?: PlaybackPolicy;
  onMetricsFlush?: (payload: ImpressionEventPayload) => void;
}) {
  const [playbackState, setPlaybackState] = useState<PlaybackState>('IDLE');
  const [currentSource, setCurrentSource] = useState<string | null>(item.media_url ?? null);
  const [currentExpiryAt, setCurrentExpiryAt] = useState<number | null>(item.playback_expires_at ?? null);
  const [firstFrameRendered, setFirstFrameRendered] = useState(false);
  const [isDebouncedBuffering, setIsDebouncedBuffering] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const sourceRef = useRef<string | null>(null);
  const metricsRef = useRef<ReelMetricsTracker>(new ReelMetricsTracker(item, 'REELS'));
  const bufferingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isMountedRef = useRef(true);
  const playbackStartedRef = useRef(false);
  const sourceFetchInFlightRef = useRef(false);
  const onMetricsFlushRef = useRef(onMetricsFlush);

  useEffect(() => {
    onMetricsFlushRef.current = onMetricsFlush;
  }, [onMetricsFlush]);

  const player = useVideoPlayer(null, (instance) => {
    instance.loop = true;
    try {
      instance.bufferOptions = getBufferOptions(policy);
    } catch {
      // BufferOptions gracefully handled if platform restricts
    }
  });

  // Keep source up to date when item updates
  useEffect(() => {
    setCurrentSource(item.media_url ?? null);
    setCurrentExpiryAt(item.playback_expires_at ?? null);
    playbackStartedRef.current = false;
    sourceFetchInFlightRef.current = false;
    metricsRef.current = new ReelMetricsTracker(item, 'REELS');
  }, [item.source_type, item.source_id, item.post_id, item.media_url, item.playback_expires_at]);

  const requestFreshPlayback = useCallback(async () => {
    if (!token || sourceFetchInFlightRef.current) return null;
    const postId = item.post_id || item.source_id;
    if (typeof postId !== 'number') return null;

    sourceFetchInFlightRef.current = true;
    try {
      const res = item.source_type === 'CURATED'
        ? await refreshCuratedReelPlayback(token, postId)
        : await refreshReelPlayback(token, postId);
      if (res.ok && res.playback_url && isMountedRef.current) {
        setCurrentSource(res.playback_url);
        setCurrentExpiryAt(res.playback_expires_at ?? null);
        metricsRef.current.onCredentialRefreshed();
        return res.playback_url;
      }
      return null;
    } catch (error) {
      if (isMountedRef.current && active) {
        const message = error instanceof Error ? error.message : 'Could not prepare this reel.';
        setErrorMessage(message);
        setPlaybackState('ERROR');
        setIsDebouncedBuffering(false);
      }
      return null;
    } finally {
      sourceFetchInFlightRef.current = false;
    }
  }, [active, item.post_id, item.source_id, item.source_type, token]);

  // Both social and curated Reels use just-in-time playback credentials so the
  // list request stays fast and only the active window touches R2.
  useEffect(() => {
    if (nearby && !currentSource) {
      void requestFreshPlayback();
    }
  }, [nearby, currentSource, requestFreshPlayback]);

  // Preemptive Credential Expiry Check
  const checkCredentialExpiry = useCallback(async () => {
    if (item.source_type !== 'SOCIAL' || !currentExpiryAt || !token) return;
    const nowSec = Math.floor(Date.now() / 1000);
    const remainingSec = currentExpiryAt - nowSec;
    if (remainingSec <= PREEMPTIVE_REFRESH_WINDOW_SEC) {
      const postId = item.post_id || item.source_id;
      try {
        const res = await refreshReelPlayback(token, postId);
        if (res.ok && res.playback_url && isMountedRef.current) {
          setCurrentSource(res.playback_url);
          setCurrentExpiryAt(res.playback_expires_at ?? null);
          metricsRef.current.onCredentialRefreshed();
          if (sourceRef.current) {
            sourceRef.current = res.playback_url;
            await player.replaceAsync(res.playback_url);
            if (active && !paused) {
              player.play();
            }
          }
        }
      } catch {
        // Will retry on error listener if needed
      }
    }
  }, [currentExpiryAt, item.post_id, item.source_id, item.source_type, token, active, paused, player]);

  // Check credential expiry on active transition and periodically
  useEffect(() => {
    if (active) {
      void checkCredentialExpiry();
      const interval = setInterval(() => {
        void checkCredentialExpiry();
      }, 20000);
      return () => clearInterval(interval);
    }
  }, [active, checkCredentialExpiry]);

  // Manage player listeners
  useEffect(() => {
    const statusSub = player.addListener('statusChange', ({ status, error }) => {
      if (!isMountedRef.current) return;

      if (status === 'error') {
        setPlaybackState('ERROR');
        const msg = error?.message ?? 'This reel could not play.';
        setErrorMessage(msg);
        metricsRef.current.onError(msg);
        setIsDebouncedBuffering(false);

        // Refresh an expired/invalid credential for both social and curated
        // Reels. Updating currentSource drives the single replaceAsync path.
        void requestFreshPlayback();
        return;
      }

      if (status === 'loading') {
        setPlaybackState(playbackStartedRef.current ? 'BUFFERING' : 'PREPARING');
        if (playbackStartedRef.current) {
          metricsRef.current.onBufferingStarted();
        }
        if (!bufferingTimerRef.current) {
          bufferingTimerRef.current = setTimeout(() => {
            if (isMountedRef.current) {
              setIsDebouncedBuffering(true);
            }
          }, BUFFERING_DEBOUNCE_MS);
        }
        return;
      }

      if (status === 'readyToPlay') {
        if (bufferingTimerRef.current) {
          clearTimeout(bufferingTimerRef.current);
          bufferingTimerRef.current = null;
        }
        setIsDebouncedBuffering(false);
        setPlaybackState('READY');
        // readyToPlay means the decoder can begin; keep the poster visible until
        // the native VideoView confirms an actual first frame was rendered.
        setErrorMessage(null);
        if (active && !paused) player.play();
      }
    });

    const playingSub = player.addListener('playingChange', ({ isPlaying }) => {
      if (!isMountedRef.current) return;
      if (isPlaying) {
        playbackStartedRef.current = true;
        setPlaybackState('PLAYING');
        setIsDebouncedBuffering(false);
        metricsRef.current.onPlayingStarted();
      } else {
        setPlaybackState('PAUSED');
        metricsRef.current.onPlayingPaused();
      }
    });

    const timeSub = player.addListener('timeUpdate', ({ currentTime }) => {
      metricsRef.current.onTimeUpdate(currentTime, player.duration);
    });

    const endSub = player.addListener('playToEnd', () => {
      metricsRef.current.onPlayToEnd();
    });

    return () => {
      statusSub.remove();
      playingSub.remove();
      timeSub.remove();
      endSub.remove();
      if (bufferingTimerRef.current) {
        clearTimeout(bufferingTimerRef.current);
        bufferingTimerRef.current = null;
      }
    };
  }, [player, active, paused, requestFreshPlayback]);

  // Window loading logic: only load source if active or immediate neighbor (nearby)
  useEffect(() => {
    const nextSource = nearby ? currentSource : null;
    if (sourceRef.current === nextSource) return;
    sourceRef.current = nextSource;

    if (!nextSource) {
      setFirstFrameRendered(false);
      setPlaybackState('IDLE');
      setIsDebouncedBuffering(false);
      setErrorMessage(null);
      void player.replaceAsync(null).catch(() => {});
      return;
    }

    setFirstFrameRendered(false);
    setPlaybackState('PREPARING');
    setErrorMessage(null);
    metricsRef.current.onPlayRequested();

    void player.replaceAsync(nextSource).catch((err: unknown) => {
      if (!isMountedRef.current) return;
      const msg = err instanceof Error ? err.message : 'Failed to prepare video.';
      setErrorMessage(msg);
      setPlaybackState('ERROR');
    });
  }, [nearby, player, currentSource]);

  // Active playing control: strictly current reel plays
  useEffect(() => {
    if (active && nearby && currentSource && !errorMessage && !paused) {
      player.play();
    } else {
      player.pause();
    }
  }, [active, nearby, currentSource, errorMessage, paused, player]);

  // Manual retry handler
  const retry = useCallback(async () => {
    setErrorMessage(null);
    setFirstFrameRendered(false);
    setPlaybackState('PREPARING');
    const postId = item.post_id || item.source_id;
    if (token && typeof postId === 'number') {
      try {
        const res = item.source_type === 'CURATED'
          ? await refreshCuratedReelPlayback(token, postId)
          : await refreshReelPlayback(token, postId);
        if (res.ok && res.playback_url && isMountedRef.current) {
          setCurrentSource(res.playback_url);
          setCurrentExpiryAt(res.playback_expires_at ?? null);
          metricsRef.current.onCredentialRefreshed();
          await player.replaceAsync(res.playback_url);
          if (active && !paused) player.play();
          return;
        }
      } catch {
        // Fall back to existing source attempt
      }
    }
    if (currentSource) {
      await player.replaceAsync(currentSource);
      if (active && !paused) player.play();
    }
  }, [item.post_id, item.source_id, item.source_type, token, currentSource, player, active, paused]);

  // Flush once on unmount. The callback is kept in a ref so a parent render
  // cannot accidentally trigger effect cleanup and duplicate an impression.
  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
      const payload = metricsRef.current.toImpressionPayload();
      if (payload.watched_ms && payload.watched_ms > 250) {
        onMetricsFlushRef.current?.(payload);
      }
    };
  }, []);

  // Flush when a Reel leaves the active slot, then reset the tracker so later
  // re-entry produces a new delta rather than resending cumulative watch time.
  const prevActiveRef = useRef(active);
  useEffect(() => {
    if (prevActiveRef.current && !active) {
      const payload = metricsRef.current.toImpressionPayload();
      if (payload.watched_ms && payload.watched_ms > 250) {
        onMetricsFlushRef.current?.(payload);
      }
      metricsRef.current = new ReelMetricsTracker(item, 'REELS');
      playbackStartedRef.current = false;
    }
    prevActiveRef.current = active;
  }, [active, item.source_type, item.source_id, item.post_id]);

  const handleFirstFrameRender = useCallback(() => {
    setFirstFrameRendered(true);
    metricsRef.current.onFirstFrame();
    setErrorMessage(null);
  }, []);

  return {
    player,
    playbackState,
    firstFrameRendered,
    isDebouncedBuffering,
    errorMessage,
    retry,
    handleFirstFrameRender,
  };
}
