import { useEffect, useRef, useState } from 'react';
import { FlatList, Keyboard, KeyboardAvoidingView, Platform, Pressable, RefreshControl, StyleSheet, Text, TextInput, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { fetchChat, sendChatText, sharePostToChat, type ChatMessage } from '../../api/kidsChat';
import { ApiError } from '../../api/client';
import { useAuth } from '../../auth/AuthProvider';
import { CHAT_BLOCKED_COPY, dedupeChat } from '../../kids/social';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsForeground } from '../../query/client';
import { Button, Card, DisabledFeature, EmptyState, ErrorState, GateNotice, LoadingState, Notice, Screen } from '../../ui/components';
import { colors, radius, spacing } from '../../ui/tokens';

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
  const flatListRef = useRef<FlatList>(null);

  useEffect(() => {
    const showSub = Keyboard.addListener(
      Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow',
      () => {
        setTimeout(() => flatListRef.current?.scrollToEnd({ animated: true }), 100);
      }
    );
    return () => {
      showSub.remove();
    };
  }, []);

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

  useEffect(() => {
    if (messages.length > 0) {
      setTimeout(() => flatListRef.current?.scrollToEnd({ animated: false }), 50);
    }
  }, [messages.length]);

  async function onSend() {
    if (!session || !peerId || !text.trim() || sending) return;
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
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'padding'}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 90 : 60}
        style={styles.keyboardWrap}
      >
        <View style={styles.peerRow}>
          <Text style={styles.peer}>{String(peer.full_name ?? peer.username ?? 'Chat')}</Text>
          <Button label="Details" variant="secondary" onPress={() => navigation.navigate('ChatDetails', { peerId })} />
        </View>
        {error ? <GateNotice error={error} /> : null}
        {sendError ? <Notice message={sendError} /> : null}

        <FlatList
          ref={flatListRef}
          data={messages}
          keyExtractor={(m) => `m:${m.child_message_id}`}
          keyboardDismissMode="on-drag"
          keyboardShouldPersistTaps="handled"
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void load('refresh')} />}
          ListEmptyComponent={<EmptyState title="Say hello kindly" body="Messages appear here in order." />}
          onEndReached={() => {
            const oldest = messages[0]?.child_message_id;
            if (oldest) void load('more', oldest);
          }}
          contentContainerStyle={styles.listContent}
          renderItem={({ item }) => (
            <Card>
              <Text style={styles.msg}>{item.message_type === 'SHARED_POST' ? `Shared a post (#${item.shared_post_id ?? ''})` : item.message_text}</Text>
              {item.sender_child_id !== peerId ? null : <Text style={styles.meta}>Friend</Text>}
            </Card>
          )}
        />
        <View style={styles.inputRow}>
          <TextInput
            style={styles.chatInput}
            value={text}
            onChangeText={setText}
            placeholder="Write kindly…"
            placeholderTextColor={colors.muted}
            multiline={false}
            returnKeyType="send"
            onSubmitEditing={() => void onSend()}
            onFocus={() => {
              setTimeout(() => flatListRef.current?.scrollToEnd({ animated: true }), 100);
            }}
          />
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Send message"
            style={[styles.sendButton, (!text.trim() || sending) && styles.sendButtonDisabled]}
            disabled={sending || !text.trim()}
            onPress={() => void onSend()}
          >
            <Feather name="send" size={16} color="#FFFFFF" />
          </Pressable>
        </View>
      </KeyboardAvoidingView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  peerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: colors.surface,
    borderBottomWidth: 1,
    borderBottomColor: '#EFEFEF',
  },
  peer: { flex: 1, fontWeight: '800', color: colors.ink, fontSize: 17 },
  keyboardWrap: { flex: 1 },
  listContent: { paddingBottom: 16, flexGrow: 1 },
  msg: { color: colors.ink, fontSize: 14, lineHeight: 20 },
  meta: { color: colors.muted, marginTop: 4, fontSize: 12 },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 12,
    paddingVertical: 10,
    backgroundColor: colors.surface,
    borderTopWidth: 1,
    borderTopColor: '#EFEFEF',
  },
  chatInput: {
    flex: 1,
    backgroundColor: '#F8F9FA',
    borderWidth: 1,
    borderColor: '#E5E7EB',
    borderRadius: radius.pill,
    paddingHorizontal: 16,
    paddingVertical: 10,
    fontSize: 14,
    color: colors.ink,
  },
  sendButton: {
    backgroundColor: colors.brand,
    borderRadius: radius.pill,
    paddingHorizontal: 16,
    paddingVertical: 10,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sendButtonDisabled: {
    opacity: 0.5,
  },
  sendButtonText: {
    color: '#FFFFFF',
    fontWeight: '800',
    fontSize: 13,
  },
});
