import { useEffect, useRef, useState } from 'react';
import { FlatList, Image, Pressable, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { useVideoPlayer, VideoView } from 'expo-video';
import type { FeedItem } from '../../api/kidsFeed';
import { ApiError } from '../../api/client';
import { PostCard } from '../../kids/PostCard';
import { shouldLoadReel, shouldPlayReel, socialPostTarget, socialProfileTarget } from '../../kids/social';
import { useFeed } from '../../kids/useFeed';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsForeground } from '../../query/client';
import { BrandHeader, Button, DisabledFeature, EmptyState, ErrorState, GateNotice, Screen, Skeleton } from '../../ui/components';
import { colors, radius, spacing } from '../../ui/tokens';

function ReelVideo({ item, active, nearby }: { item: FeedItem; active: boolean; nearby: boolean }) {
  const source = item.media_url ?? null;
  const player = useVideoPlayer(null, (instance) => { instance.loop = true; });
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const sourceRef = useRef<string | null>(null);

  useEffect(() => {
    const subscription = player.addListener('statusChange', ({ status, error: playbackError }) => {
      if (status === 'error') setError(playbackError?.message ?? 'This reel could not play.');
    });
    return () => subscription.remove();
  }, [player]);

  useEffect(() => {
    const next = nearby ? source : null;
    if (sourceRef.current === next) return;
    sourceRef.current = next;
    setReady(false);
    setError(null);
    void player.replaceAsync(next).catch((reason: unknown) => {
      setError(reason instanceof Error ? reason.message : 'This reel could not play.');
    });
  }, [nearby, player, source]);

  useEffect(() => {
    if (active && nearby && source && !error) player.play();
    else player.pause();
  }, [active, error, nearby, player, source]);

  async function retry() {
    if (!source) return;
    setError(null);
    setReady(false);
    try {
      await player.replaceAsync(source);
      if (active) player.play();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'This reel could not play.');
    }
  }

  if (!source) return <ErrorState message="This reel has no playable video." />;
  return (
    <View style={styles.videoShell}>
      {nearby ? <VideoView player={player} style={styles.video} contentFit="cover" nativeControls={active} onFirstFrameRender={() => setReady(true)} /> : null}
      {!ready && item.poster_url ? <Image source={{ uri: item.poster_url }} style={styles.posterOverlay} /> : null}
      {error ? <View style={styles.errorOverlay}><Text style={styles.errorText}>Playback failed.</Text><Button label="Retry" onPress={() => void retry()} /></View> : null}
    </View>
  );
}

export function ReelsScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const feed = useFeed('reels', 8);
  const foreground = useIsForeground();
  const [activeIndex, setActiveIndex] = useState(0);
  const viewabilityConfig = useRef({ itemVisiblePercentThreshold: 60 }).current;
  const onViewableItemsChanged = useRef(({ viewableItems }: { viewableItems: Array<{ index: number | null }> }) => {
    const first = viewableItems.find((row) => typeof row.index === 'number')?.index;
    if (typeof first === 'number') setActiveIndex(first);
  }).current;

  if (feed.loading) return <Screen><Skeleton lines={4} /></Screen>;
  if (feed.error instanceof ApiError && feed.error.code === 'disabled_by_parent') return <Screen><DisabledFeature feature="Reels" /></Screen>;
  if (feed.error && !feed.items.length) return <Screen><GateNotice error={feed.error} /><ErrorState message="Could not load reels." onRetry={feed.retry} /></Screen>;

  return (
    <Screen>
      <BrandHeader title="Reels" subtitle={foreground ? 'One reel plays at a time.' : 'Paused while the app is in the background.'} />
      {feed.error ? <GateNotice error={feed.error} /> : null}
      <FlatList
        data={feed.items}
        keyExtractor={(it) => `reel:${it.source_id}`}
        pagingEnabled
        refreshControl={<RefreshControl refreshing={feed.refreshing} onRefresh={feed.refresh} />}
        ListEmptyComponent={<EmptyState title="No reels yet" body="Short videos from friends will appear here." />}
        onViewableItemsChanged={onViewableItemsChanged}
        viewabilityConfig={viewabilityConfig}
        onEndReached={feed.loadMore}
        onEndReachedThreshold={0.6}
        windowSize={3}
        maxToRenderPerBatch={3}
        initialNumToRender={2}
        removeClippedSubviews
        renderItem={({ item, index }) => {
          const post = socialPostTarget(item);
          const profile = socialProfileTarget(item);
          const nav = navigation as unknown as { navigate: (r: string, p: object) => void };
          return <View style={styles.page}>
            <ReelVideo item={item} active={shouldPlayReel(index, activeIndex, foreground)} nearby={shouldLoadReel(index, activeIndex)} />
            <PostCard
              item={item}
              onOpen={post ? () => nav.navigate('PostDetail', post) : undefined}
              onProfile={profile ? () => nav.navigate('OtherProfile', profile) : undefined}
            />
            <Pressable onPress={() => setActiveIndex(index)}><Text style={styles.tap}>Play this reel</Text></Pressable>
          </View>;
        }}
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  page: { marginBottom: spacing.lg, borderWidth: 1, borderColor: colors.line, borderRadius: radius.lg, padding: spacing.sm },
  videoShell: { width: '100%', height: 360, borderRadius: radius.md, overflow: 'hidden', backgroundColor: colors.ink },
  video: { width: '100%', height: '100%' },
  posterOverlay: { ...StyleSheet.absoluteFill, width: '100%', height: '100%' },
  errorOverlay: { ...StyleSheet.absoluteFill, alignItems: 'center', justifyContent: 'center', gap: spacing.sm, backgroundColor: 'rgba(0,0,0,0.72)' },
  errorText: { color: colors.surface, fontWeight: '700' },
  tap: { color: colors.brandDark, fontWeight: '700', marginTop: 4 },
});
