import { useInfiniteQuery, type InfiniteData } from '@tanstack/react-query';
import { fetchFeedV2, fetchReelsV2, type FeedPage } from '../api/kidsFeed';
import { useAuth } from '../auth/AuthProvider';
import { kidsKeys } from '../query/keys';
import { mergeFeedPages } from './social';

type PageParam = { cursor: number; sessionId?: string };

/** One authoritative TanStack Query cache for cursor-paginated feed and reels. */
export function useFeed(kind: 'feed' | 'reels', limit = 10, mode: 'for_you' | 'friends' | 'learn' = 'for_you') {
  const { session } = useAuth();
  const query = useInfiniteQuery<FeedPage, Error, InfiniteData<FeedPage, PageParam>, readonly unknown[], PageParam>({
    queryKey: [...(kind === 'feed' ? [...kidsKeys.feed, mode] : kidsKeys.reels), session?.token ?? 'signed-out'],
    enabled: Boolean(session),
    initialPageParam: { cursor: 0 },
    queryFn: ({ pageParam, signal }) => {
      if (!session) throw new Error('Sign in required.');
      if (kind === 'feed') {
        return fetchFeedV2(session.token, pageParam.cursor, limit, pageParam.sessionId, mode, signal);
      }
      return fetchReelsV2(session.token, pageParam.cursor, limit, pageParam.sessionId, signal);
    },
    getNextPageParam: (last) => last.has_more
      ? { cursor: last.next_cursor, sessionId: last.session_id || undefined }
      : undefined,
  });

  return {
    items: mergeFeedPages(query.data?.pages.map((page) => page.items) ?? []),
    sessionId: query.data?.pages[0]?.session_id,
    loading: query.isPending,
    loadingMore: query.isFetchingNextPage,
    refreshing: query.isRefetching && !query.isFetchingNextPage,
    error: query.error,
    hasMore: query.hasNextPage,
    loadMore: () => { if (query.hasNextPage && !query.isFetchingNextPage) void query.fetchNextPage(); },
    refresh: () => void query.refetch(),
    retry: () => void query.refetch(),
  };
}

