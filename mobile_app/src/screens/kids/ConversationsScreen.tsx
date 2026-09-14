import { useEffect, useState } from 'react';
import { FlatList, Pressable, RefreshControl, StyleSheet, Text } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { fetchConversations, type ConversationItem } from '../../api/kidsChat';
import { useAuth } from '../../auth/AuthProvider';
import { isConversationUnread } from '../../kids/social';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsForeground } from '../../query/client';
import { Avatar, TimeAgo } from '../../ui/social';
import { BrandHeader, DisabledFeature, EmptyState, ErrorState, GateNotice, LoadingState, Screen } from '../../ui/components';
import { ApiError } from '../../api/client';
import { colors } from '../../ui/tokens';

export function ConversationsScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const { session } = useAuth();
  const foreground = useIsForeground();
  const focused = useIsFocused();
  const [items, setItems] = useState<ConversationItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const nav = navigation as unknown as { navigate: (r: string, p: object) => void };

  async function load(mode: 'first' | 'refresh') {
    if (!session || !foreground) return;
    if (mode === 'first') setLoading(true);
    else setRefreshing(true);
    try {
      const res = await fetchConversations(session.token);
      setItems(res.conversations ?? []);
      setError(null);
    } catch (err) {
      setError(err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }

  useEffect(() => {
    if (focused && foreground) void load(loading ? 'first' : 'refresh');
  }, [session?.token, focused, foreground]);
  if (loading) return <Screen><LoadingState message="Loading messages…" /></Screen>;
  if (error instanceof ApiError && error.code === 'disabled_by_parent') return <Screen><DisabledFeature feature="Messages" /></Screen>;
  if (error && !items.length) return <Screen><GateNotice error={error} /><ErrorState message="Could not load messages." onRetry={() => void load('first')} /></Screen>;

  return (
    <Screen>
      <FlatList
        data={items}
        keyExtractor={(c) => `c:${c.conversation_id}`}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void load('refresh')} />}
        ListHeaderComponent={<BrandHeader title="Messages" subtitle="Only approved friends can message." />}
        ListEmptyComponent={<EmptyState title="No conversations" body="Make an approved friend to start chatting." />}
        renderItem={({ item }) => {
          const unread = isConversationUnread(item);
          return <Pressable style={styles.row} onPress={() => nav.navigate('Chat', { peerId: item.peer_id })}>
            <Avatar uri={item.peer_avatar_url} name={item.peer_name} size={48} />
            <Text style={[styles.name, unread && styles.unread]}>{item.peer_name ?? 'Friend'}</Text>
            <Text style={[styles.last, unread && styles.unread]}>{item.last_message?.message_text ?? ''}</Text>
            {unread ? <Text style={styles.dot}>●</Text> : null}
            <TimeAgo value={item.last_message?.sent_at} />
          </Pressable>;
        }}
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 12, paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: colors.line, backgroundColor: colors.surface },
  name: { fontWeight: '800', color: colors.ink },
  last: { flex: 1, color: colors.muted },
  unread: { color: colors.ink, fontWeight: '800' },
  dot: { color: colors.brand, fontSize: 12, marginLeft: 4 },
});
