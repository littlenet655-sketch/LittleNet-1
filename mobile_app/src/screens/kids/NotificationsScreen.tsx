import { useState } from 'react';
import { FlatList, Pressable, RefreshControl, StyleSheet, Text } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { fetchNotifications, markNotificationsRead, type NotificationItem } from '../../api/kidsChat';
import { ApiError } from '../../api/client';
import { useAuth } from '../../auth/AuthProvider';
import { notificationDestination } from '../../kids/social';
import type { ChildScreenProps } from '../../navigation/types';
import { queryClient, useIsForeground, useIsOnline } from '../../query/client';
import { kidsKeys } from '../../query/keys';
import { Avatar } from '../../ui/social';
import { BrandHeader, Button, DisabledFeature, EmptyState, ErrorState, GateNotice, LoadingState, OfflineBanner, Screen } from '../../ui/components';
import { colors } from '../../ui/tokens';

/**
 * Maps a server target_url to an app destination. The backend only ever
 * creates /chat/<id>/ and /child/dashboard/ style URLs for kids (plus parent
 * control alerts); anything unrecognized is ignored instead of crashing.
 * (Implementation lives in src/kids/social.ts so it stays unit-testable.)
 */

export function NotificationsScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const { session } = useAuth();
  const online = useIsOnline();
  const foreground = useIsForeground();
  const [markingAll, setMarkingAll] = useState(false);
  const nav = navigation as unknown as { navigate: (r: string, p: object) => void };
  const token = session?.token ?? 'signed-out';
  const queryKey = [...kidsKeys.notifications, token];

  const query = useQuery({
    queryKey,
    enabled: Boolean(session) && foreground,
    staleTime: 30_000,
    queryFn: () => fetchNotifications(session!.token),
  });
  const items = query.data?.notifications ?? [];
  const unread = items.filter((n) => !n.is_read).length;

  async function markRead(ids?: number[]) {
    if (!session) return;
    try {
      await markNotificationsRead(session.token, ids);
      const markedIds = new Set(ids);
      queryClient.setQueryData<{ ok: boolean; notifications: NotificationItem[] }>(queryKey, (old) =>
        old
          ? {
              ...old,
              notifications: old.notifications.map((n) =>
                ids === undefined || markedIds.has(n.notification_id) ? { ...n, is_read: true } : n,
              ),
            }
          : old,
      );
    } catch {
      // Mark-read is best-effort; the server stays authoritative.
    }
  }

  function openTarget(item: NotificationItem) {
    const dest = notificationDestination(item.target_url);
    if (dest) nav.navigate(dest.route, dest.params);
    if (session && !item.is_read) void markRead([item.notification_id]);
  }

  if (query.isPending) return <Screen><LoadingState message="Loading notifications…" /></Screen>;
  if (query.error instanceof ApiError && query.error.code === 'disabled_by_parent') return <Screen><DisabledFeature feature="Notifications" /></Screen>;
  if (query.error && !items.length) {
    return (
      <Screen>
        <GateNotice error={query.error} />
        <ErrorState message="Could not load notifications." onRetry={() => void query.refetch()} />
      </Screen>
    );
  }

  return (
    <Screen>
      <FlatList
        data={items}
        keyExtractor={(n) => `n:${n.notification_id}`}
        refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={() => void query.refetch()} />}
        ListHeaderComponent={
          <>
            <BrandHeader title="Notifications" subtitle={unread > 0 ? `${unread} unread` : undefined} />
            <OfflineBanner online={online} />
            {query.error ? <GateNotice error={query.error} /> : null}
            {unread > 0 ? (
              <Button
                label={markingAll ? 'Marking…' : 'Mark all read'}
                variant="secondary"
                disabled={markingAll || !online}
                onPress={() => {
                  setMarkingAll(true);
                  markRead().finally(() => setMarkingAll(false));
                }}
              />
            ) : null}
            <Button label="Open Safety Centre" variant="secondary" onPress={() => nav.navigate('SafetyCentre', {})} />
          </>
        }
        ListEmptyComponent={<EmptyState title="No notifications" body="Messages, parent alerts and safety updates will appear here." />}
        renderItem={({ item }) => (
          <Pressable
            style={[styles.row, !item.is_read && styles.unread]}
            onPress={() => openTarget(item)}
          >
            <Avatar uri={item.actor_avatar_url} name={item.actor_name} />
            <Text style={[styles.msg, !item.is_read && styles.unreadText]}>{item.message ?? item.notification_type}</Text>
            {!item.is_read ? <Text style={styles.dot}>•</Text> : null}
          </Pressable>
        )}
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 12, paddingVertical: 13, borderBottomWidth: 1, borderBottomColor: colors.line, backgroundColor: colors.surface },
  unread: { backgroundColor: '#F0F8FD' },
  msg: { flex: 1, color: colors.ink },
  unreadText: { fontWeight: '700' },
  dot: { color: colors.brandDark, fontWeight: '800' },
});
