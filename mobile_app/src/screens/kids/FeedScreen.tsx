import { FlatList, Pressable, RefreshControl, StyleSheet, Text, View, type ViewToken } from 'react-native';
import { useRef, useState } from 'react';
import { useIsFocused } from '@react-navigation/native';
import { ApiError } from '../../api/client';
import { submitRecommendationAction } from '../../api/recommendation';
import { useAuth } from '../../auth/AuthProvider';
import { PostCard } from '../../kids/PostCard';
import { useFeed } from '../../kids/useFeed';
import { socialPostTarget, socialProfileTarget, feedKey } from '../../kids/social';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsForeground, useIsOnline } from '../../query/client';
import type { FeedItem } from '../../api/kidsFeed';
import { BrandHeader, DisabledFeature, EmptyState, ErrorState, GateNotice, LoadingState, OfflineBanner, Screen, Skeleton } from '../../ui/components';

export function FeedScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const online = useIsOnline();
  const focused = useIsFocused();
  const foreground = useIsForeground();
  const { session } = useAuth();
  const [tab, setTab] = useState<'For You' | 'Friends' | 'Learn'>('For You');
  const [hiddenKeys, setHiddenKeys] = useState<Set<string>>(new Set());
  const [activeVideoKey, setActiveVideoKey] = useState<string | null>(null);
  const viewabilityConfig = useRef({ itemVisiblePercentThreshold: 60, minimumViewTime: 250 }).current;
  const onViewableItemsChanged = useRef(({ viewableItems }: { viewableItems: ViewToken[] }) => {
    const visibleVideo = viewableItems.find((entry) => {
      const item = entry.item as FeedItem | undefined;
      return Boolean(entry.isViewable && item?.media_type?.toUpperCase() === 'VIDEO');
    });
    const item = visibleVideo?.item as FeedItem | undefined;
    setActiveVideoKey(item ? `${item.source_type}:${item.source_id}` : null);
  }).current;
  const feedMode = tab === 'Friends' ? 'friends' : tab === 'Learn' ? 'learn' : 'for_you';
  const feed = useFeed('feed', 10, feedMode);

  async function notInterested(sourceType: 'SOCIAL' | 'CURATED', sourceId: number) {
    if (!session) return;
    const key = `${sourceType}:${sourceId}`;
    setHiddenKeys((current) => {
      const next = new Set(current);
      next.add(key);
      return next;
    });
    try {
      await submitRecommendationAction(session.token, {
        source_type: sourceType,
        source_id: sourceId,
        action: 'NOT_INTERESTED',
      });
    } catch {
      setHiddenKeys((current) => {
        const next = new Set(current);
        next.delete(key);
        return next;
      });
    }
  }

  if (feed.loading) return <Screen><BrandHeader title="LittleNet" /><Skeleton lines={5} /><LoadingState message="Loading your feed…" /></Screen>;
  if (feed.error instanceof ApiError && feed.error.code === 'disabled_by_parent') return <Screen><DisabledFeature feature="Feed" /></Screen>;
  if (feed.error && feed.items.length === 0) return <Screen><OfflineBanner online={online} /><GateNotice error={feed.error} /><ErrorState message="Could not load your feed." onRetry={feed.retry} /></Screen>;

  return (
    <Screen>
      <FlatList
        data={feed.items.filter((it) => !hiddenKeys.has(feedKey(it)))}
        keyExtractor={(it) => feedKey(it)}
        refreshControl={<RefreshControl refreshing={feed.refreshing} onRefresh={feed.refresh} />}
        ListHeaderComponent={<><BrandHeader title="LittleNet" subtitle="Kind posts from friends." /><View style={styles.tabs}>{(['For You', 'Friends', 'Learn'] as const).map((item) => <Pressable key={item} onPress={() => { setActiveVideoKey(null); setTab(item); }}><Text style={[styles.tab, tab === item && styles.active]}>{item}</Text></Pressable>)}</View><OfflineBanner online={online} />{feed.error ? <GateNotice error={feed.error} /> : null}</>}
        ListEmptyComponent={<EmptyState title="Nothing here yet" body="When friends share kind posts, they will appear here." />}
        renderItem={({ item }) => {
          const post = socialPostTarget(item);
          const profile = socialProfileTarget(item);
          const nav = navigation as unknown as { navigate: (r: string, p: object) => void };
          const key = feedKey(item);
          return <PostCard
            item={item}
            onOpen={post ? () => nav.navigate('PostDetail', post) : undefined}
            onProfile={profile ? () => nav.navigate('OtherProfile', profile) : undefined}
            onNotInterested={tab === 'Friends' ? undefined : () => void notInterested(item.source_type, item.source_id)}
            inlineVideoPlayback
            videoActive={focused && foreground && activeVideoKey === key}
          />;
        }}
        onViewableItemsChanged={onViewableItemsChanged}
        viewabilityConfig={viewabilityConfig}
        windowSize={5}
        maxToRenderPerBatch={4}
        initialNumToRender={4}
        removeClippedSubviews
        onEndReached={feed.loadMore}
        onEndReachedThreshold={0.5}
      />
    </Screen>
  );
}

const styles = StyleSheet.create({ tabs: { flexDirection: 'row', justifyContent: 'space-around', paddingVertical: 12, borderBottomWidth: 1, borderColor: '#DBDBDB' }, tab: { color: '#737373', fontWeight: '700' }, active: { color: '#262626', borderBottomWidth: 2, borderBottomColor: '#0095F6', paddingBottom: 6 } });
