import { useEffect, useRef, useState } from 'react';
import { Alert, FlatList, Image, Pressable, RefreshControl, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { useVideoPlayer } from 'expo-video';
import { useIsFocused } from '@react-navigation/native';
import type { FeedItem } from '../../api/kidsFeed';
import { recordFeedImpression, refreshReelPlayback } from '../../api/kidsFeed';
import { ApiError } from '../../api/client';
import { submitRecommendationAction } from '../../api/recommendation';
import { submitReport, toggleSave } from '../../api/kidsSocial';
import { useAuth } from '../../auth/AuthProvider';
import { PostCard } from '../../kids/PostCard';
import { shouldLoadReel, shouldPlayReel, socialPostTarget, socialProfileTarget } from '../../kids/social';
import { useFeed } from '../../kids/useFeed';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsForeground } from '../../query/client';
import { BrandHeader, Button, DisabledFeature, EmptyState, ErrorState, GateNotice, Screen, Skeleton } from '../../ui/components';
import { NativeVideoView } from '../../ui/nativeViews';
import { colors, radius, spacing } from '../../ui/tokens';

function ReelVideo({
  item,
  active,
  nearby,
  paused,
  onToggle,
  token,
}: {
  item: FeedItem;
  active: boolean;
  nearby: boolean;
  paused: boolean;
  onToggle: () => void;
  token?: string;
}) {
  const [currentSource, setCurrentSource] = useState<string | null>(item.media_url ?? null);
  const player = useVideoPlayer(null, (instance) => { instance.loop = true; });
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const sourceRef = useRef<string | null>(null);

  useEffect(() => {
    setCurrentSource(item.media_url ?? null);
  }, [item.media_url]);

  useEffect(() => {
    const subscription = player.addListener('statusChange', ({ status, error: playbackError }) => {
      if (status === 'error') {
        const postId = item.post_id || item.source_id;
        if (token && typeof postId === 'number') {
          void refreshReelPlayback(token, postId).then((res) => {
            if (res.ok && res.playback_url) {
              setCurrentSource(res.playback_url);
              void player.replaceAsync(res.playback_url).then(() => {
                if (active && !paused) player.play();
              });
              return;
            }
            setError(playbackError?.message ?? 'This reel could not play.');
          }).catch(() => {
            setError(playbackError?.message ?? 'This reel could not play.');
          });
        } else {
          setError(playbackError?.message ?? 'This reel could not play.');
        }
      }
    });
    return () => subscription.remove();
  }, [player, token, item.post_id, item.source_id, active, paused]);

  useEffect(() => {
    const next = nearby ? currentSource : null;
    if (sourceRef.current === next) return;
    sourceRef.current = next;
    setReady(false);
    setError(null);
    void player.replaceAsync(next).catch((reason: unknown) => {
      setError(reason instanceof Error ? reason.message : 'This reel could not play.');
    });
  }, [nearby, player, currentSource]);

  useEffect(() => {
    if (active && nearby && currentSource && !error && !paused) player.play();
    else player.pause();
  }, [active, error, nearby, paused, player, currentSource]);

  async function retry() {
    setError(null);
    setReady(false);
    const postId = item.post_id || item.source_id;
    if (token && typeof postId === 'number') {
      try {
        const res = await refreshReelPlayback(token, postId);
        if (res.ok && res.playback_url) {
          setCurrentSource(res.playback_url);
          await player.replaceAsync(res.playback_url);
          if (active) player.play();
          return;
        }
      } catch {}
    }
    if (!currentSource) return;
    try {
      await player.replaceAsync(currentSource);
      if (active) player.play();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'This reel could not play.');
    }
  }

  if (!currentSource) return <ErrorState message="This reel has no playable video." />;
  return (
    <View style={styles.videoShell}>
        {nearby ? <Pressable style={styles.videoTouch} onPress={onToggle}><NativeVideoView player={player} style={styles.video} contentFit="cover" nativeControls={false} onFirstFrameRender={() => setReady(true)} /></Pressable> : null}
      {!ready && item.poster_url ? <Image source={{ uri: item.poster_url }} style={styles.posterOverlay} /> : null}
       {active && paused && !error ? <View pointerEvents="none" style={styles.paused}><Text style={styles.pauseGlyph}>Ⅱ</Text><Text style={styles.pauseLabel}>Paused</Text></View> : null}
      {error ? <View style={styles.errorOverlay}><Text style={styles.errorText}>Playback failed.</Text><Button label="Retry" onPress={() => void retry()} /></View> : null}
    </View>
  );
}

export function ReelsScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const { session } = useAuth();
  const { height } = useWindowDimensions();
  const focused = useIsFocused();
  const feed = useFeed('reels', 8);
  const foreground = useIsForeground();
  const [activeIndex, setActiveIndex] = useState(0);
  const [paused, setPaused] = useState(false);
  const watchStartRef = useRef<number>(Date.now());
  const activeIndexRef = useRef<number>(activeIndex);
  const viewabilityConfig = useRef({ itemVisiblePercentThreshold: 60 }).current;
  const onViewableItemsChanged = useRef(({ viewableItems }: { viewableItems: Array<{ index: number | null }> }) => {
    const first = viewableItems.find((row) => typeof row.index === 'number')?.index;
    if (typeof first === 'number') { setActiveIndex(first); setPaused(false); }
  }).current;

  // Track aggregated watch duration telemetry on reel change or unmount
  useEffect(() => {
    const prevIndex = activeIndexRef.current;
    const prevItem = feed.items[prevIndex];
    const watchedMs = Date.now() - watchStartRef.current;
    if (session?.token && prevItem && watchedMs >= 1000) {
      const sourceId = prevItem.post_id ?? prevItem.source_id;
      if (typeof sourceId === 'number') {
        void recordFeedImpression(session.token, {
          session_id: feed.sessionId,
          source_type: prevItem.source_type ?? 'REEL',
          source_id: sourceId,
          surface: 'REELS',
          watched_ms: watchedMs,
          completed: watchedMs >= 10000,
        }).catch(() => {});
      }
    }
    activeIndexRef.current = activeIndex;
    watchStartRef.current = Date.now();
  }, [activeIndex, feed.items, feed.sessionId, session?.token]);

  if (feed.loading) return <Screen><Skeleton lines={4} /></Screen>;
  if (feed.error instanceof ApiError && feed.error.code === 'disabled_by_parent') return <Screen><DisabledFeature feature="Reels" /></Screen>;
  if (feed.error && !feed.items.length) return <Screen><GateNotice error={feed.error} /><ErrorState message="Could not load reels." onRetry={feed.retry} /></Screen>;

  return (
    <Screen>
       <View style={styles.headerOverlay}><BrandHeader title="Reels" subtitle={foreground && focused ? 'Tap a video to pause.' : 'Paused while the app is inactive.'} /></View>
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
           return <View style={[styles.page, { height }]}>
             <ReelVideo
               item={item}
               active={shouldPlayReel(index, activeIndex, foreground && focused)}
               nearby={shouldLoadReel(index, activeIndex)}
               paused={paused}
               onToggle={() => index === activeIndex && setPaused((value) => !value)}
               token={session?.token}
             />
            <PostCard
              item={item}
              onOpen={post ? () => nav.navigate('PostDetail', post) : undefined}
              onProfile={profile ? () => nav.navigate('OtherProfile', profile) : undefined}
            />
             {post && session ? <View style={styles.quickActions}>
               <Pressable onPress={() => void toggleSave(session.token, post.postId)}><Text style={styles.quickText}>Save</Text></Pressable>
               <Pressable onPress={() => nav.navigate('PostDetail', post)}><Text style={styles.quickText}>Comments</Text></Pressable>
               <Pressable onPress={() => profile ? nav.navigate('OtherProfile', profile) : undefined}><Text style={styles.quickText}>Profile</Text></Pressable>
               <Pressable onPress={() => void submitRecommendationAction(session.token, { source_type: 'SOCIAL', source_id: post.postId, action: 'NOT_INTERESTED' })}><Text style={styles.quickText}>Not interested</Text></Pressable>
               <Pressable onPress={() => Alert.alert('Report reel?', 'Send this reel to LittleNet safety review?', [{ text: 'Cancel', style: 'cancel' }, { text: 'Report', style: 'destructive', onPress: () => void submitReport(session.token, 'post', post.postId, 'inappropriate') }])}><Text style={styles.quickText}>Report</Text></Pressable>
             </View> : null}
          </View>;
        }}
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  headerOverlay: { position: 'absolute', zIndex: 2, top: 0, left: 0, right: 0 },
  page: { marginBottom: 0, padding: spacing.sm, justifyContent: 'center' },
  videoShell: { width: '100%', flex: 1, borderRadius: radius.md, overflow: 'hidden', backgroundColor: colors.ink },
  videoTouch: { flex: 1 },
  video: { width: '100%', height: '100%' },
  posterOverlay: { ...StyleSheet.absoluteFill, width: '100%', height: '100%' },
  errorOverlay: { ...StyleSheet.absoluteFill, alignItems: 'center', justifyContent: 'center', gap: spacing.sm, backgroundColor: 'rgba(0,0,0,0.72)' },
  errorText: { color: colors.surface, fontWeight: '700' },
  paused: { ...StyleSheet.absoluteFill, alignItems: 'center', justifyContent: 'center' },
  pauseGlyph: { color: colors.surface, fontSize: 44, fontWeight: '800' },
  pauseLabel: { color: colors.surface, fontWeight: '700' },
  quickActions: { flexDirection: 'row', flexWrap: 'wrap', gap: 10, paddingVertical: spacing.sm },
  quickText: { color: colors.brandDark, fontWeight: '800', paddingVertical: 6 },
});
