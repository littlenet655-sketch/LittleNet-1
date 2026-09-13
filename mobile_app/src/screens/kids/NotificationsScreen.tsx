import { useEffect, useState } from 'react';
import { FlatList, Pressable, RefreshControl, StyleSheet, Text } from 'react-native';
import { fetchNotifications, markNotificationsRead, type NotificationItem } from '../../api/kidsChat';
import { useAuth } from '../../auth/AuthProvider';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsForeground } from '../../query/client';
import { Avatar } from '../../ui/social';
import { BrandHeader, EmptyState, ErrorState, GateNotice, LoadingState, OfflineBanner, Screen } from '../../ui/components';
import { useIsOnline } from '../../query/client';
import { colors } from '../../ui/tokens';

export function NotificationsScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const { session } = useAuth();
  const online = useIsOnline();
  const foreground = useIsForeground();
  const [items, setItems] = useState<NotificationItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const nav = navigation as unknown as { navigate: (r: string, p: object) => void };

  async function load(mode: 'first' | 'refresh') {
    if (!session) return;
    if (mode === 'first') setLoading(true);
    else setRefreshing(true);
    try {
      const res = await fetchNotifications(session.token);
      setItems(res.notifications ?? []);
      setError(null);
    } catch (err) {
      setError(err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }

  useEffect(() => { void load('first'); }, [session?.token, foreground]);
  if (loading) return <Screen><LoadingState message="Loading notifications…" /></Screen>;
  if (error && !items.length) return <Screen><GateNotice error={error} /><ErrorState message="Could not load notifications." onRetry={() => void load('first')} /></Screen>;

  function openTarget(item: NotificationItem) {
    const url = item.target_url ?? '';
    const postMatch = url.match(/\/post\/(\d+)/);
    if (postMatch?.[1]) {
      nav.navigate('PostDetail', { postId: Number(postMatch[1]) });
      return;
    }
    const chatMatch = url.match(/\/chat\/(\d+)/);
    if (chatMatch?.[1]) {
      nav.navigate('Chat', { peerId: Number(chatMatch[1]) });
      return;
    }
  }

  return (
    <Screen>
      <FlatList
        data={items}
        keyExtractor={(n) => `n:${n.notification_id}`}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void load('refresh')} />}
        ListHeaderComponent={<><BrandHeader title="Notifications" /><OfflineBanner online={online} />{error ? <GateNotice error={error} /> : null}</>}
        ListEmptyComponent={<EmptyState title="No notifications" body="Likes, comments and friend updates will appear here." />}
        renderItem={({ item }) => (
          <Pressable
            style={[styles.row, !item.is_read && styles.unread]}
            onPress={() => {
              openTarget(item);
              if (session && !item.is_read) {
                markNotificationsRead(session.token, [item.notification_id]).then(() => {
                  setItems((prev) => prev.map((n) => (n.notification_id === item.notification_id ? { ...n, is_read: true } : n)));
                }).catch(() => undefined);
              }
            }}
          >
            <Avatar uri={item.actor_avatar_url} name={item.actor_name} />
            <Text style={styles.msg}>{item.message ?? item.notification_type}</Text>
            {!item.is_read ? <Text style={styles.dot}>•</Text> : null}
          </Pressable>
        )}
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: colors.line },
  unread: { backgroundColor: '#FFF4EC' },
  msg: { flex: 1, color: colors.ink },
  dot: { color: colors.brandDark, fontWeight: '800' },
});
