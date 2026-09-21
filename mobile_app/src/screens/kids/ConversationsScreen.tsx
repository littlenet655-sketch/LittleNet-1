import { useEffect, useState } from 'react';
import { FlatList, Pressable, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { fetchConversations, type ConversationItem } from '../../api/kidsChat';
import { useAuth } from '../../auth/AuthProvider';
import { dedupeConversations, isConversationUnread } from '../../kids/social';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsForeground } from '../../query/client';
import { Avatar, TimeAgo } from '../../ui/social';
import { BrandHeader, Button, DisabledFeature, EmptyState, ErrorState, GateNotice, LoadingState, Screen } from '../../ui/components';
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
      // Backend returns the full conversation list (no cursor params); dedupe
      // defensively so repeats never render twice.
      setItems(dedupeConversations(res.conversations ?? []));
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
        ListHeaderComponent={<><BrandHeader title="Messages" subtitle="Only approved friends can message." /><Button label="New message" onPress={() => nav.navigate('NewMessage', {})} /></>}
        ListEmptyComponent={<EmptyState title="No conversations" body="Make an approved friend to start chatting." />}
        renderItem={({ item }) => {
          const unread = isConversationUnread(item);
          return (
            <Pressable
              style={({ pressed }) => [styles.row, pressed && styles.rowPressed]}
              onPress={() => nav.navigate('Chat', { peerId: item.peer_id })}
            >
              <Avatar uri={item.peer_avatar_url} name={item.peer_name} size={56} />
              <View style={styles.textCol}>
                <View style={styles.topRow}>
                  <Text style={[styles.name, unread && styles.nameUnread]} numberOfLines={1}>
                    {item.peer_name ?? 'Friend'}
                  </Text>
                  <TimeAgo value={item.last_message?.sent_at} />
                </View>
                <View style={styles.bottomRow}>
                  <Text style={[styles.preview, unread && styles.previewUnread]} numberOfLines={1}>
                    {item.last_message?.message_text ?? ''}
                  </Text>
                  {unread ? <View style={styles.unreadDot} /> : null}
                </View>
              </View>
            </Pressable>
          );
        }}
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 12,
    height: 76,
    backgroundColor: colors.surface,
  },
  rowPressed: {
    backgroundColor: '#F5F5F5',
  },
  textCol: {
    flex: 1,
    justifyContent: 'center',
  },
  topRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  name: {
    flex: 1,
    fontSize: 15,
    fontWeight: '700',
    color: colors.ink,
  },
  nameUnread: {
    fontWeight: '800',
  },
  preview: {
    flex: 1,
    fontSize: 14,
    color: colors.muted,
  },
  previewUnread: {
    color: colors.ink,
    fontWeight: '700',
  },
  bottomRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 3,
  },
  unreadDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: colors.brand,
  },
});
