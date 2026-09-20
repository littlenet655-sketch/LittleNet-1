import { useEffect, useRef, useState } from 'react';
import { Image, StyleSheet, Text, View } from 'react-native';
import { useVideoPlayer } from 'expo-video';
import { useIsForeground } from '../query/client';
import { Button } from '../ui/components';
import { NativeVideoView } from '../ui/nativeViews';
import { colors, radius, spacing } from '../ui/tokens';

export function VideoMedia({
  source,
  posterUrl,
  active = true,
  height = 380,
  onComplete,
  nativeControls = true,
  loop = false,
}: {
  source: string;
  posterUrl?: string | null;
  active?: boolean;
  height?: number;
  onComplete?: () => void;
  nativeControls?: boolean;
  loop?: boolean;
}) {
  const foreground = useIsForeground();
  const player = useVideoPlayer(null);
  const sourceRef = useRef<string | null>(null);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const playableSource = active && foreground ? source : null;

  useEffect(() => {
    player.loop = loop;
  }, [loop, player]);

  useEffect(() => {
    const subscription = player.addListener('statusChange', ({ status, error: playbackError }) => {
      if (status === 'error') setError(playbackError?.message ?? 'This video could not play.');
    });
    const completeSub = player.addListener('playToEnd', () => {
      onComplete?.();
    });
    return () => {
      subscription.remove();
      completeSub.remove();
    };
  }, [player, onComplete]);

  useEffect(() => {
    if (sourceRef.current === playableSource) return;
    sourceRef.current = playableSource;
    setReady(false);
    setError(null);
    void player.replaceAsync(playableSource).then(() => {
      if (playableSource && sourceRef.current === playableSource) player.play();
    }).catch((reason: unknown) => {
      setError(reason instanceof Error ? reason.message : 'This video could not play.');
    });
  }, [playableSource, player]);

  useEffect(() => {
    if (playableSource && !error) player.play();
    else player.pause();
  }, [error, playableSource, player]);

  useEffect(() => () => player.pause(), [player]);

  async function retry() {
    if (!playableSource) return;
    setError(null);
    setReady(false);
    try {
      await player.replaceAsync(playableSource);
      if (sourceRef.current === playableSource) player.play();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'This video could not play.');
    }
  }

  return (
    <View style={[styles.shell, { height }]}>
      <NativeVideoView player={player} style={styles.video} contentFit="cover" nativeControls={nativeControls} onFirstFrameRender={() => setReady(true)} />
      {!ready && posterUrl ? <Image source={{ uri: posterUrl }} style={styles.overlay} /> : null}
      {!ready && !posterUrl && !error ? <View style={styles.overlayCenter}><Text style={styles.loading}>Loading video…</Text></View> : null}
      {error ? <View style={styles.overlayCenter}><Text style={styles.error}>Playback failed.</Text><Button label="Retry" onPress={() => void retry()} /></View> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  shell: { width: '100%', borderRadius: radius.lg, overflow: 'hidden', backgroundColor: colors.ink },
  video: { width: '100%', height: '100%' },
  overlay: { ...StyleSheet.absoluteFill, width: '100%', height: '100%' },
  overlayCenter: { ...StyleSheet.absoluteFill, alignItems: 'center', justifyContent: 'center', gap: spacing.sm, backgroundColor: 'rgba(0,0,0,0.68)' },
  loading: { color: colors.surface, fontWeight: '700' },
  error: { color: colors.surface, fontWeight: '700' },
});
