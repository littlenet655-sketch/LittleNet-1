import { useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { fetchKidsHome, fetchFeedV2, fetchReelsV2 } from '../api/kidsFeed';
import { fetchOwnProfile, searchDiscover } from '../api/kidsProfiles';
import { fetchNotifications } from '../api/kidsChat';
import { useAuth } from '../auth/AuthProvider';
import { kidsKeys } from '../query/keys';
import { useIsOnline } from '../query/client';

interface PageParam {
  cursor: number;
  sessionId?: string;
}

/**
 * Warm the first screenful of every Kids surface after the gates clear.
 * Each screen still owns its loading/error UI; this only removes the blank
 * tab-to-tab waterfall on first entry.
 */
export function useKidsHydration(): void {
  const { session } = useAuth();
  const online = useIsOnline();
  const queryClient = useQueryClient();
  const token = session?.token;

  useEffect(() => {
    if (!token || !online) return;
    let cancelled = false;

    const feedQuery = {
      initialPageParam: { cursor: 0 } as PageParam,
      queryFn: ({ pageParam, signal }: { pageParam: PageParam; signal: AbortSignal }) =>
        fetchFeedV2(token, pageParam.cursor, 10, pageParam.sessionId, signal),
      getNextPageParam: (last: { has_more: boolean; next_cursor: number; session_id?: string }) =>
        last.has_more ? { cursor: last.next_cursor, sessionId: last.session_id || undefined } : undefined,
    };
    const reelsQuery = {
      initialPageParam: { cursor: 0 } as PageParam,
      queryFn: ({ pageParam, signal }: { pageParam: PageParam; signal: AbortSignal }) =>
        fetchReelsV2(token, pageParam.cursor, 8, pageParam.sessionId, signal),
      getNextPageParam: (last: { has_more: boolean; next_cursor: number; session_id?: string }) =>
        last.has_more ? { cursor: last.next_cursor, sessionId: last.session_id || undefined } : undefined,
    };

    void Promise.allSettled([
      queryClient.prefetchQuery({ queryKey: [...kidsKeys.home, token], queryFn: () => fetchKidsHome(token) }),
      queryClient.prefetchInfiniteQuery({ queryKey: [...kidsKeys.feed, token], ...feedQuery }),
      queryClient.prefetchInfiniteQuery({ queryKey: [...kidsKeys.reels, token], ...reelsQuery }),
      queryClient.prefetchQuery({ queryKey: [...kidsKeys.discover(''), token], queryFn: () => searchDiscover(token, '') }),
      queryClient.prefetchQuery({ queryKey: [...kidsKeys.ownProfile, token], queryFn: () => fetchOwnProfile(token) }),
      queryClient.prefetchQuery({ queryKey: [...kidsKeys.notifications, token], queryFn: () => fetchNotifications(token) }),
    ]).finally(() => {
      if (cancelled) return;
    });

    return () => {
      cancelled = true;
    };
  }, [online, queryClient, token]);
}