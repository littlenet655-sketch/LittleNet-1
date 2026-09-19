import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, FlatList, Pressable, RefreshControl, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { recordImpressionBatch } from '../../api/kidsFeed';
import { ApiError } from '../../api/client';
import { submitRecommendationAction } from '../../api/recommendation';
import { submitReport, toggleSave } from '../../api/kidsSocial';
import { useAuth } from '../../auth/AuthProvider';
import { PostCard } from '../../kids/PostCard';
import { shouldLoadReel, shouldPlayReel, socialPostTarget, socialProfileTarget } from '../../kids/social';
import { useFeed } from '../../kids/useFeed';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsForeground } from '../../query/client';
import { BrandHeader, DisabledFeature, EmptyState, ErrorState, GateNotice, Screen, Skeleton } from '../../ui/components';
import { colors, radius, spacing } from '../../ui/tokens';
import { ReelPlayer } from '../../video/ReelPlayer';
import type { ImpressionEventPayload } from '../../video/types';

export function ReelsScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const { session } = useAuth();
  const { height } = useWindowDimensions();
  const focused = useIsFocused();
  const feed = useFeed('reels', 8);
  const foreground = useIsForeground();
  const [activeIndex, setActiveIndex] = useState(0);
  const [paused, setPaused] = useState(false);
  const impressionBatchRef = useRef<ImpressionEventPayload[]>([]);
  const viewabilityConfig = useRef({ itemVisiblePercentThreshold: 60 }).current;
  const onViewableItemsChanged = useRef(({ viewableItems }: { viewableItems: Array<{ index: number | null }> }) => {
    const first = viewableItems.find((row) => typeof row.index === 'number')?.index;
    if (typeof first === 'number') { setActiveIndex(first); setPaused(false); }
  }).current;

  // Flush batched impressions to server
  const flushBatch = useCallback(async () => {
    if (!session?.token || impressionBatchRef.current.length === 0) return;
    const events = [...impressionBatchRef.current];
    impressionBatchRef.current = [];
    try {
      await recordImpressionBatch(session.token, events);
    } catch {
      // Non-blocking telemetry
    }
  }, [session?.token]);

  // Buffer impression events emitted by ReelPlayer
  const handleMetricsFlush = useCallback((payload: ImpressionEventPayload) => {
    if (feed.sessionId && !payload.session_id) {
      payload.session_id = feed.sessionId;
    }
    impressionBatchRef.current.push(payload);
    if (impressionBatchRef.current.length >= 5) {
      void flushBatch();
    }
  }, [feed.sessionId, flushBatch]);

  // Flush on app backgrounding or screen blur
  useEffect(() => {
    if (!foreground || !focused) {
      void flushBatch();
    }
  }, [foreground, focused, flushBatch]);

  // Flush on unmount
  useEffect(() => {
    return () => {
      void flushBatch();
    };
  }, [flushBatch]);

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
             <View style={styles.videoShell}>
               <ReelPlayer
                 item={item}
                 active={shouldPlayReel(index, activeIndex, foreground && focused)}
                 nearby={shouldLoadReel(index, activeIndex)}
                 paused={paused}
                 onTogglePlay={() => index === activeIndex && setPaused((value) => !value)}
                 token={session?.token}
                 onMetricsFlush={handleMetricsFlush}
               />
             </View>
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
  quickActions: { flexDirection: 'row', flexWrap: 'wrap', gap: 10, paddingVertical: spacing.sm },
  quickText: { color: colors.brandDark, fontWeight: '800', paddingVertical: 6 },
});
