import { useEffect, useState } from 'react';
import { FlatList, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { fetchChat, sendChatText, sharePostToChat, type ChatMessage } from '../../api/kidsChat';
import { ApiError } from '../../api/client';
import { useAuth } from '../../auth/AuthProvider';
import { CHAT_BLOCKED_COPY, dedupeChat } from '../../kids/social';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsForeground } from '../../query/client';
import { Button, Card, DisabledFeature, EmptyState, ErrorState, Field, GateNotice, LoadingState, Notice, Screen } from '../../ui/components';
import { colors } from '../../ui/tokens';

export function ChatScreen({ route, navigation }: ChildScreenProps<'Chat'>) {
  const { session } = useAuth();
  const foreground = useIsForeground();
  const peerId = Number((route.params as { peerId?: number } | undefined)?.peerId ?? 0);
  const postId = (route.params as { postId?: number } | undefined)?.postId;
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [peer, setPeer] = useState<Record<string, unknown>>({});
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [sendError, setSendError] = useState('');
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);

  async function load(mode: 'first' | 'more' | 'refresh', beforeId?: number) {
    if (!session || !peerId || !foreground) return;
    if (mode === 'first') setLoading(true);
    if (mode === 'refresh') setRefreshing(true);
    try {
      const res = await fetchChat(session.token, peerId, 30, beforeId);
      setPeer(res.peer ?? {});
      setMessages((prev) => (mode === 'more' ? dedupeChat([...(res.messages ?? []), ...prev]) : dedupeChat(res.messages ?? [])));
      setError(null);
    } catch (err) {
      setError(err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }

  useEffect(() => { void load('first'); }, [session?.token, peerId, foreground]);

  async function onSend() {
    if (!session || !text.trim()) return;
    setSending(true);
    setSendError('');
    try {
      const res = await sendChatText(session.token, peerId, text.trim());
      setText('');
      if (res.status === 'REVIEW') setSendError('Your message is waiting for a safety check.');
      else await load('refresh');
    } catch (err) {
      setSendError(err instanceof ApiError && err.code.includes('blocked') ? CHAT_BLOCKED_COPY : 'Could not send. Try again.');
    } finally {
      setSending(false);
    }
  }

  useEffect(() => {
    if (session && peerId && postId) {
      sharePostToChat(session.token, peerId, postId).then(() => load('refresh')).catch((err: unknown) => setError(err));
    }
  }, [session?.token, peerId, postId]);

  if (loading) return <Screen><LoadingState message="Loading chat…" /></Screen>;
  if (error instanceof ApiError && error.code === 'disabled_by_parent') return <Screen><DisabledFeature feature="Messages" /></Screen>;
  if (error instanceof ApiError && error.status === 403) return <Screen><EmptyState title="Chat unavailable" body="You can message after both parents approve this friendship." /></Screen>;
  if (error && !messages.length) return <Screen><GateNotice error={error} /><ErrorState message="Could not load this chat." onRetry={() => void load('first')} /></Screen>;

  return (
    <Screen>
      <View style={styles.peerRow}><Text style={styles.peer}>{String(peer.full_name ?? peer.username ?? 'Chat')}</Text><Button label="Details" variant="secondary" onPress={() => navigation.navigate('ChatDetails', { peerId })} /></View>
      {error ? <GateNotice error={error} /> : null}
      {sendError ? <Notice message={sendError} /> : null}
      <FlatList
        data={messages}
        keyExtractor={(m) => `m:${m.child_message_id}`}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void load('refresh')} />}
        ListEmptyComponent={<EmptyState title="Say hello kindly" body="Messages appear here in order." />}
        onEndReached={() => {
          const oldest = messages[0]?.child_message_id;
          if (oldest) void load('more', oldest);
        }}
        renderItem={({ item }) => (
          <Card>
            <Text style={styles.msg}>{item.message_type === 'SHARED_POST' ? `Shared a post (#${item.shared_post_id ?? ''})` : item.message_text}</Text>
            {item.sender_child_id !== peerId ? null : <Text style={styles.meta}>Friend</Text>}
          </Card>
        )}
      />
      <View style={styles.row}>
        <Field label="Message" value={text} onChangeText={setText} placeholder="Write kindly…" />
        <Button label={sending ? '…' : 'Send'} disabled={sending || !text.trim()} onPress={() => void onSend()} />
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  peerRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', borderBottomWidth: 1, borderBottomColor: colors.line, backgroundColor: colors.surface },
  peer: { flex: 1, fontWeight: '700', color: colors.ink, fontSize: 18, paddingHorizontal: 12, paddingVertical: 12 },
  msg: { color: colors.ink, fontSize: 14, lineHeight: 20 },
  meta: { color: colors.muted, marginTop: 4 },
  row: { marginTop: 8, paddingHorizontal: 12, paddingBottom: 8, backgroundColor: colors.surface },
});
