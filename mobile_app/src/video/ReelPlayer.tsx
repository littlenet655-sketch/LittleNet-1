import { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Image,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { Feather } from '@expo/vector-icons';
import type { FeedItem } from '../api/kidsFeed';
import { NativeVideoView } from '../ui/nativeViews';
import { colors, radius, spacing } from '../ui/tokens';
import type { ImpressionEventPayload, PlaybackPolicy } from './types';
import { useReelPlayback } from './useReelPlayback';

interface ReelPlayerProps {
  item: FeedItem;
  active: boolean;
  nearby: boolean;
  paused: boolean;
  onTogglePlay: () => void;
  token?: string;
  policy?: PlaybackPolicy;
  onMetricsFlush?: (payload: ImpressionEventPayload) => void;
}

export function ReelPlayer({
  item,
  active,
  nearby,
  paused,
  onTogglePlay,
  token,
  policy = 'NORMAL',
  onMetricsFlush,
}: ReelPlayerProps) {
  const [showPlayStateFeedback, setShowPlayStateFeedback] = useState(false);
  const feedbackTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const {
    player,
    playbackState,
    firstFrameRendered,
    isDebouncedBuffering,
    errorMessage,
    retry,
    handleFirstFrameRender,
  } = useReelPlayback({
    item,
    active,
    nearby,
    paused,
    token,
    policy,
    onMetricsFlush,
  });

  const posterUri = item.poster_url ?? null;
  const showPoster = !firstFrameRendered && Boolean(posterUri);

  const handlePress = () => {
    onTogglePlay();
    setShowPlayStateFeedback(true);
    if (feedbackTimerRef.current) clearTimeout(feedbackTimerRef.current);
    feedbackTimerRef.current = setTimeout(() => {
      setShowPlayStateFeedback(false);
      feedbackTimerRef.current = null;
    }, 600);
  };

  useEffect(() => () => {
    if (feedbackTimerRef.current) clearTimeout(feedbackTimerRef.current);
  }, []);

  return (
    <Pressable style={styles.container} onPress={handlePress} accessibilityLabel="Toggle video playback">
      {/* Underlying Native Video Player */}
      <NativeVideoView
        player={player}
        style={StyleSheet.absoluteFill}
        contentFit="cover"
        nativeControls={false}
        onFirstFrameRender={handleFirstFrameRender}
      />

      {/* Poster overlay: rendered until first video frame is decoded */}
      {showPoster && posterUri ? (
        <Image
          source={{ uri: posterUri }}
          style={StyleSheet.absoluteFill}
          resizeMode="cover"
          accessibilityLabel="Reel poster"
        />
      ) : null}

      {/* Debounced Buffering Indicator (shown only after 300ms stall) */}
      {isDebouncedBuffering && !errorMessage ? (
        <View style={styles.bufferingOverlay} pointerEvents="none">
          <View style={styles.bufferingPill}>
            <ActivityIndicator size="small" color="#FFFFFF" />
            <Text style={styles.bufferingText}>Loading…</Text>
          </View>
        </View>
      ) : null}

      {/* Tap Feedback Icon (Play / Pause) */}
      {showPlayStateFeedback ? (
        <View style={styles.feedbackOverlay} pointerEvents="none">
          <View style={styles.feedbackCircle}>
            <Feather
              name={paused ? 'play' : 'pause'}
              size={32}
              color="#FFFFFF"
            />
          </View>
        </View>
      ) : null}

      {/* Error & Controlled Retry Overlay */}
      {errorMessage ? (
        <View style={styles.errorOverlay}>
          <View style={styles.errorCard}>
            <Feather name="alert-circle" size={28} color="#EF4444" />
            <Text style={styles.errorTitle}>Could not play reel</Text>
            <Text style={styles.errorDescription}>{errorMessage}</Text>
            <Pressable style={styles.retryButton} onPress={retry}>
              <Feather name="refresh-cw" size={16} color="#FFFFFF" />
              <Text style={styles.retryText}>Retry</Text>
            </Pressable>
          </View>
        </View>
      ) : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000000',
    overflow: 'hidden',
  },
  bufferingOverlay: {
    ...StyleSheet.absoluteFill,
    justifyContent: 'center',
    alignItems: 'center',
  },
  bufferingPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: 'rgba(0, 0, 0, 0.65)',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 24,
  },
  bufferingText: {
    color: '#FFFFFF',
    fontSize: 13,
    fontWeight: '600',
  },
  feedbackOverlay: {
    ...StyleSheet.absoluteFill,
    justifyContent: 'center',
    alignItems: 'center',
  },
  feedbackCircle: {
    width: 64,
    height: 64,
    borderRadius: 32,
    backgroundColor: 'rgba(0, 0, 0, 0.55)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  errorOverlay: {
    ...StyleSheet.absoluteFill,
    backgroundColor: 'rgba(0, 0, 0, 0.75)',
    justifyContent: 'center',
    alignItems: 'center',
    padding: spacing.lg,
  },
  errorCard: {
    backgroundColor: colors.surface,
    padding: spacing.lg,
    borderRadius: radius.md,
    alignItems: 'center',
    maxWidth: 320,
    gap: 8,
  },
  errorTitle: {
    fontSize: 16,
    fontWeight: '800',
    color: colors.ink,
  },
  errorDescription: {
    fontSize: 13,
    color: colors.muted,
    textAlign: 'center',
    lineHeight: 18,
  },
  retryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: colors.brand,
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 20,
    marginTop: 4,
  },
  retryText: {
    color: '#FFFFFF',
    fontWeight: '700',
    fontSize: 14,
  },
});
