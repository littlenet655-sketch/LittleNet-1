import { FlatList, RefreshControl } from 'react-native';
import { ApiError } from '../../api/client';
import { PostCard } from '../../kids/PostCard';
import { useFeed } from '../../kids/useFeed';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsOnline } from '../../query/client';
import { BrandHeader, DisabledFeature, EmptyState, ErrorState, GateNotice, LoadingState, OfflineBanner, Screen, Skeleton } from '../../ui/components';

export function FeedScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const online = useIsOnline();
  const feed = useFeed('feed');

  if (feed.loading) return <Screen><BrandHeader title="LittleNet" /><Skeleton lines={5} /><LoadingState message="Loading your feed…" /></Screen>;
  if (feed.error instanceof ApiError && feed.error.code === 'disabled_by_parent') return <Screen><DisabledFeature feature="Feed" /></Screen>;
  if (feed.error && feed.items.length === 0) return <Screen><OfflineBanner online={online} /><GateNotice error={feed.error} /><ErrorState message="Could not load your feed." onRetry={feed.retry} /></Screen>;

  return (
    <Screen>
      <FlatList
        data={feed.items}
        keyExtractor={(it) => `${it.source_type}:${it.source_id}`}
        refreshControl={<RefreshControl refreshing={feed.refreshing} onRefresh={feed.refresh} />}
        ListHeaderComponent={<><BrandHeader title="LittleNet" subtitle="Kind posts from friends." /><OfflineBanner online={online} />{feed.error ? <GateNotice error={feed.error} /> : null}</>}
        ListEmptyComponent={<EmptyState title="Nothing here yet" body="When friends share kind posts, they will appear here." />}
        renderItem={({ item }) => (
          <PostCard
            item={item}
            onOpen={() => (navigation as unknown as { navigate: (r: string, p: object) => void }).navigate('PostDetail', { postId: item.post_id })}
            onProfile={() => (navigation as unknown as { navigate: (r: string, p: object) => void }).navigate('OtherProfile', { targetId: item.child_id ?? 0 })}
          />
        )}
        onEndReached={feed.loadMore}
        onEndReachedThreshold={0.5}
      />
    </Screen>
  );
}
