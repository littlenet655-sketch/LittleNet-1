import { FlatList, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View, type ViewToken } from 'react-native';
import { useEffect, useRef, useState } from 'react';
import { useIsFocused } from '@react-navigation/native';
import { Feather } from '@expo/vector-icons';
import { ApiError } from '../../api/client';
import { fetchKidsHome, type StoryItem } from '../../api/kidsFeed';
import { submitRecommendationAction } from '../../api/recommendation';
import { useAuth } from '../../auth/AuthProvider';
import { PostCard } from '../../kids/PostCard';
import { useFeed } from '../../kids/useFeed';
import { socialPostTarget, socialProfileTarget, feedKey } from '../../kids/social';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsForeground, useIsOnline } from '../../query/client';
import type { FeedItem } from '../../api/kidsFeed';
import { Avatar, StoryRing } from '../../ui/social';
import { colors, spacing } from '../../ui/tokens';
import { BrandHeader, DisabledFeature, EmptyState, ErrorState, GateNotice, LoadingState, OfflineBanner, Screen, Skeleton } from '../../ui/components';

/**
 * Server sends more than the base StoryItem declares: owner id and whether the
 * viewer already saw the story.
 */
interface TrayStory extends StoryItem {
  child_id?: number;
  viewed?: boolean;
}

/**
 * Instagram-style horizontal stories tray for the feed header. Visual only —
 * taps open the existing Stories viewer at its own start.
 */
function StoriesTray({
  token,
  myId,
  myName,
  onOpen,
}: {
  token?: string;
  myId?: number;
  myName?: string;
  onOpen: () => void;
}) {
  const [stories, setStories] = useState<TrayStory[]>([]);

  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    fetchKidsHome(token)
      .then((home) => {
        if (!cancelled) setStories((home.stories ?? []) as TrayStory[]);
      })
      .catch(() => {
        // Tray is a bonus — the feed below still works without it.
      });
    return () => {
      cancelled = true;
    };
  }, [token]);

  const myStories = myId != null ? stories.filter((s) => s.child_id === myId) : [];
  const own = myStories[0];
  const ownSeen = myStories.length > 0 && myStories.every((s) => s.viewed);

  // One ring per friend, preserving server order; ring is grey only when every
  // story from that friend was viewed.
  const friendOrder = new Map<number, TrayStory[]>();
  for (const story of stories) {
    if (story.child_id == null || story.child_id === myId) continue;
    const group = friendOrder.get(story.child_id) ?? [];
    group.push(story);
    friendOrder.set(story.child_id, group);
  }
  const friends = [...friendOrder.values()].map((group) => group[0]).filter(Boolean) as TrayStory[];

  return (
    <View style={styles.trayWrap}>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.trayContent}
      >
        <Pressable
          onPress={onOpen}
          style={styles.trayCell}
          accessibilityRole="button"
          accessibilityLabel="Your story"
        >
          <View>
            <StoryRing size={68} seen={ownSeen}>
              <Avatar uri={own?.avatar_url} name={myName} size={56} />
            </StoryRing>
            <View style={styles.plusBadge} pointerEvents="none">
              <Feather name="plus" size={14} color="#FFFFFF" />
            </View>
          </View>
          <Text style={styles.trayName} numberOfLines={1}>
            Your story
          </Text>
        </Pressable>
        {friends.map((story) => (
          <Pressable
            key={`tray-${story.post_id}`}
            onPress={onOpen}
            style={styles.trayCell}
            accessibilityRole="button"
            accessibilityLabel={`${story.full_name ?? 'Friend'}'s story`}
          >
            <StoryRing size={68} seen={Boolean(story.viewed)}>
              <Avatar uri={story.avatar_url} name={story.full_name ?? 'Friend'} size={56} />
            </StoryRing>
            <Text style={styles.trayName} numberOfLines={1}>
              {story.full_name ?? 'Friend'}
            </Text>
          </Pressable>
        ))}
      </ScrollView>
    </View>
  );
}

export function FeedScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const online = useIsOnline();
  const focused = useIsFocused();
  const foreground = useIsForeground();
  const { session } = useAuth();
  const nav = navigation as unknown as { navigate: (r: string, p: object) => void };
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
        ListHeaderComponent={<><BrandHeader title="LittleNet" subtitle="Kind posts from friends." /><StoriesTray token={session?.token} myId={session?.user.user_id} myName={session?.user.full_name} onOpen={() => nav.navigate('Stories', {})} /><View style={styles.tabs}>{(['For You', 'Friends', 'Learn'] as const).map((item) => (
          <Pressable
            key={item}
            onPress={() => { setActiveVideoKey(null); setTab(item); }}
            style={styles.tabHit}
            accessibilityRole="tab"
            accessibilityState={{ selected: tab === item }}
          >
            <Text style={[styles.tabLabel, tab === item && styles.tabLabelActive]}>{item}</Text>
            <View style={[styles.tabIndicator, tab === item && styles.tabIndicatorActive]} />
          </Pressable>
        ))}</View><OfflineBanner online={online} />{feed.error ? <GateNotice error={feed.error} /> : null}</>}
        ListEmptyComponent={<EmptyState title="Nothing here yet" body="When friends share kind posts, they will appear here." />}
        renderItem={({ item }) => {
          const post = socialPostTarget(item);
          const profile = socialProfileTarget(item);
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

const styles = StyleSheet.create({
  trayWrap: { marginTop: spacing.xs, marginBottom: spacing.sm },
  trayContent: { gap: 12, paddingHorizontal: spacing.md, paddingVertical: spacing.sm },
  trayCell: { alignItems: 'center', width: 72 },
  trayName: { marginTop: 5, fontSize: 12, color: colors.muted, fontWeight: '600', maxWidth: 72, textAlign: 'center' },
  plusBadge: {
    position: 'absolute',
    right: 2,
    bottom: 2,
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: colors.brand,
    borderWidth: 2,
    borderColor: colors.surface,
    alignItems: 'center',
    justifyContent: 'center',
  },
  tabs: {
    flexDirection: 'row',
    borderBottomWidth: 1,
    borderColor: colors.line,
    paddingHorizontal: spacing.md,
    marginTop: spacing.xs,
    backgroundColor: colors.surface,
  },
  tabHit: { flex: 1, minHeight: 44, alignItems: 'center', justifyContent: 'center', gap: 4 },
  tabLabel: { color: colors.muted, fontWeight: '700', fontSize: 14 },
  tabLabelActive: { color: colors.ink, fontWeight: '800' },
  tabIndicator: { height: 2, width: '64%', borderRadius: 1, backgroundColor: 'transparent' },
  tabIndicatorActive: { backgroundColor: colors.brand },
});
