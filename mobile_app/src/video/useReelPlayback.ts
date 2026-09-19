import { useCallback, useEffect, useRef, useState } from 'react';
import { useVideoPlayer } from 'expo-video';
import type { FeedItem } from '../api/kidsFeed';
import { refreshReelPlayback } from '../api/kidsFeed';
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
  const [firstFrameRendered, setFirstFrameRendered] = useState(false);
  const [isDebouncedBuffering, setIsDebouncedBuffering] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const sourceRef = useRef<string | null>(null);
  const metricsRef = useRef<ReelMetricsTracker>(new ReelMetricsTracker(item, 'REELS'));
  const bufferingTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isMountedRef = useRef(true);

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
    if (item.media_url && item.media_url !== currentSource) {
      setCurrentSource(item.media_url);
    }
  }, [item.media_url]);

  // Preemptive Credential Expiry Check
  const checkCredentialExpiry = useCallback(async () => {
    if (!item.playback_expires_at || !token) return;
    const nowSec = Math.floor(Date.now() / 1000);
    const remainingSec = item.playback_expires_at - nowSec;
    if (remainingSec <= PREEMPTIVE_REFRESH_WINDOW_SEC) {
      const postId = item.post_id || item.source_id;
      try {
        const res = await refreshReelPlayback(token, postId);
        if (res.ok && res.playback_url && isMountedRef.current) {
          setCurrentSource(res.playback_url);
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
  }, [item.playback_expires_at, item.post_id, item.source_id, token, active, paused, player]);

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

        // Auto-refresh credential on error
        const postId = item.post_id || item.source_id;
        if (token && typeof postId === 'number') {
          void refreshReelPlayback(token, postId).then((res) => {
            if (res.ok && res.playback_url && isMountedRef.current) {
              setCurrentSource(res.playback_url);
              metricsRef.current.onCredentialRefreshed();
              void player.replaceAsync(res.playback_url).then(() => {
                if (active && !paused) player.play();
              });
            }
          }).catch(() => {});
        }
        return;
      }

      if (status === 'loading') {
        setPlaybackState('PREPARING');
        metricsRef.current.onBufferingStarted();
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
        setFirstFrameRendered(true);
        metricsRef.current.onFirstFrame();
        setErrorMessage(null);
      }
    });

    const playingSub = player.addListener('playingChange', ({ isPlaying }) => {
      if (!isMountedRef.current) return;
      if (isPlaying) {
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
  }, [player, token, item.post_id, item.source_id, active, paused]);

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
        const res = await refreshReelPlayback(token, postId);
        if (res.ok && res.playback_url && isMountedRef.current) {
          setCurrentSource(res.playback_url);
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
  }, [item.post_id, item.source_id, token, currentSource, player, active, paused]);

  // Flush metrics when active becomes false or on unmount
  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
      const payload = metricsRef.current.toImpressionPayload();
      if (payload.watched_ms && payload.watched_ms > 250) {
        onMetricsFlush?.(payload);
      }
    };
  }, [onMetricsFlush]);

  // Also flush on active transition from true -> false
  const prevActiveRef = useRef(active);
  useEffect(() => {
    if (prevActiveRef.current && !active) {
      const payload = metricsRef.current.toImpressionPayload();
      if (payload.watched_ms && payload.watched_ms > 250) {
        onMetricsFlush?.(payload);
      }
    }
    prevActiveRef.current = active;
  }, [active, onMetricsFlush]);

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
