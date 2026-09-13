import { useInfiniteQuery, type InfiniteData } from '@tanstack/react-query';
import { fetchFeedV2, fetchReelsV2, type FeedPage } from '../api/kidsFeed';
import { useAuth } from '../auth/AuthProvider';
import { kidsKeys } from '../query/keys';
import { mergeFeedPages } from './social';

type PageParam = { cursor: number; sessionId?: string };

/** One authoritative TanStack Query cache for cursor-paginated feed and reels. */
export function useFeed(kind: 'feed' | 'reels', limit = 10) {
  const { session } = useAuth();
  const query = useInfiniteQuery<FeedPage, Error, InfiniteData<FeedPage, PageParam>, readonly unknown[], PageParam>({
    queryKey: [...(kind === 'feed' ? kidsKeys.feed : kidsKeys.reels), session?.token ?? 'signed-out'],
    enabled: Boolean(session),
    initialPageParam: { cursor: 0 },
    queryFn: ({ pageParam, signal }) => {
      if (!session) throw new Error('Sign in required.');
      const fetchPage = kind === 'feed' ? fetchFeedV2 : fetchReelsV2;
      return fetchPage(session.token, pageParam.cursor, limit, pageParam.sessionId, signal);
    },
    getNextPageParam: (last) => last.has_more
      ? { cursor: last.next_cursor, sessionId: last.session_id || undefined }
      : undefined,
  });

  return {
    items: mergeFeedPages(query.data?.pages.map((page) => page.items) ?? []),
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
