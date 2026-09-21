import { useCallback, useEffect, useRef, useState } from 'react';
import { FlatList, Keyboard, KeyboardAvoidingView, Platform, Pressable, RefreshControl, StyleSheet, Text, TextInput, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { useIsFocused } from '@react-navigation/native';
import { fetchChat, sendChatText, sharePostToChat, type ChatMessage } from '../../api/kidsChat';
import { ApiError } from '../../api/client';
import { useAuth } from '../../auth/AuthProvider';
import { CHAT_BLOCKED_COPY, dedupeChat, isChatMessagePending } from '../../kids/social';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsForeground, useIsOnline } from '../../query/client';
import { Button, Card, DisabledFeature, EmptyState, ErrorState, GateNotice, LoadingState, Notice, OfflineBanner, Screen } from '../../ui/components';
import { colors, radius } from '../../ui/tokens';

const PAGE_SIZE = 30;

export function ChatScreen({ route, navigation }: ChildScreenProps<'Chat'>) {
  const { session } = useAuth();
  const foreground = useIsForeground();
  const online = useIsOnline();
  const focused = useIsFocused();
  const peerId = Number((route.params as { peerId?: number } | undefined)?.peerId ?? 0);
  const postId = (route.params as { postId?: number } | undefined)?.postId;
  const ownId = session?.user.user_id ?? 0;
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [peer, setPeer] = useState<Record<string, unknown>>({});
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [hasMore, setHasMore] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [info, setInfo] = useState('');
  const [sendError, setSendError] = useState('');
  const [shareNotice, setShareNotice] = useState('');
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const flatListRef = useRef<FlatList>(null);
  const nav = navigation as unknown as { goBack: () => void; navigate: (r: string, p: object) => void };

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

  const load = useCallback(async (mode: 'first' | 'more' | 'refresh' | 'silent', beforeId?: number) => {
    if (!session || !peerId || !foreground) return;
    if (mode === 'more' && (loadingMore || !hasMore)) return;
    if (mode === 'first') setLoading(true);
    if (mode === 'refresh') setRefreshing(true);
    if (mode === 'more') setLoadingMore(true);
    try {
      const res = await fetchChat(session.token, peerId, PAGE_SIZE, beforeId);
      setPeer(res.peer ?? {});
      const rows = res.messages ?? [];
      setMessages((prev) => (mode === 'more' ? dedupeChat([...rows, ...prev]) : dedupeChat(rows)));
      if (mode === 'more' || mode === 'first') setHasMore(rows.length >= PAGE_SIZE);
      setError(null);
    } catch (err) {
      setError(err);
    } finally {
      setLoading(false);
      setRefreshing(false);
      setLoadingMore(false);
    }
  }, [session, peerId, foreground, loadingMore, hasMore]);

  useEffect(() => { void load('first'); }, [session?.token, peerId, foreground]);

  // Pull the latest messages when the screen regains focus.
  useEffect(() => {
    if (focused && foreground && messages.length > 0) void load('silent');
  }, [focused, foreground]);

  useEffect(() => {
    if (messages.length > 0) {
      setTimeout(() => flatListRef.current?.scrollToEnd({ animated: false }), 50);
    }
  }, [messages.length]);

  async function onSend() {
    if (!session || !peerId || !text.trim() || sending) return;
    if (!online) {
      setSendError('You are offline. Reconnect to send messages.');
      return;
    }
    setSending(true);
    setSendError('');
    const outgoing = text.trim();
    try {
      const res = await sendChatText(session.token, peerId, outgoing);
      setText('');
      // Always refresh: the server returns own REVIEW messages to the sender
      // so they render in the pending state below instead of vanishing.
      await load('refresh');
      if (res.status === 'REVIEW') {
        setInfo('Your message is waiting for a safety check. Only you can see it for now.');
      } else {
        setInfo('');
      }
    } catch (err) {
      // Keep the typed text so the child can retry; do not clear it.
      setSendError(err instanceof ApiError && err.code.includes('blocked') ? CHAT_BLOCKED_COPY : 'Could not send. Tap Retry to try again.');
    } finally {
      setSending(false);
    }
  }

  useEffect(() => {
    if (session && peerId && postId) {
      sharePostToChat(session.token, peerId, postId)
        .then(() => {
          setShareNotice('Post sent to this chat.');
          void load('refresh');
        })
        .catch((err: unknown) => {
          setShareNotice(err instanceof ApiError ? err.message : 'Could not share that post here.');
        });
    }
    // Share once per screen mount: postId is fixed for this route instance.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session?.token, peerId, postId]);

  if (loading) return <Screen><LoadingState message="Loading chat…" /></Screen>;
  if (error instanceof ApiError && error.code === 'disabled_by_parent') return <Screen><DisabledFeature feature="Messages" /></Screen>;
  if (error instanceof ApiError && error.status === 403) {
    return (
      <Screen>
        <EmptyState
          title="Chat unavailable"
          body="You can message after both families approve this friendship. If the friendship was removed, this chat is closed."
        />
        <Button label="Back" variant="secondary" onPress={() => nav.goBack()} />
      </Screen>
    );
  }
  if (error && !messages.length) return <Screen><GateNotice error={error} /><ErrorState message="Could not load this chat." onRetry={() => void load('first')} /></Screen>;

  const peerName = String(peer.full_name ?? peer.username ?? 'Chat');

  return (
    <Screen>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'padding'}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 90 : 60}
        style={styles.keyboardWrap}
      >
        <View style={styles.peerRow}>
          <Text style={styles.peer}>{peerName}</Text>
          <Button label="Details" variant="secondary" onPress={() => nav.navigate('ChatDetails', { peerId })} />
        </View>
        {!online ? <OfflineBanner online={online} /> : null}
        {error ? <GateNotice error={error} /> : null}
        {info ? <Notice tone="info" message={info} /> : null}
        {shareNotice ? <Notice tone="info" message={shareNotice} /> : null}
        {sendError ? (
          <View style={styles.sendErrorRow}>
            <Notice message={sendError} />
            {text.trim() ? <Button label="Retry" onPress={() => void onSend()} /> : null}
          </View>
        ) : null}

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
            if (oldest && hasMore && !loadingMore) void load('more', oldest);
          }}
          onEndReachedThreshold={0.4}
          ListFooterComponent={loadingMore ? <Text style={styles.moreLoading}>Loading older messages…</Text> : null}
          contentContainerStyle={styles.listContent}
          renderItem={({ item }) => {
            const isOwn = ownId !== 0 && item.sender_child_id === ownId;
            const pending = isChatMessagePending(item, isOwn);
            return (
              <Card>
                {item.message_type === 'SHARED_POST' ? (
                  <Text style={styles.msg}>Shared a post (#{item.shared_post_id ?? ''})</Text>
                ) : (
                  <Text style={[styles.msg, pending && styles.pendingMsg]}>{item.message_text}</Text>
                )}
                <View style={styles.metaRow}>
                  {!isOwn ? <Text style={styles.meta}>Friend</Text> : null}
                  {pending ? (
                    <View style={styles.pendingBadge}>
                      <Feather name="clock" size={11} color="#B45309" />
                      <Text style={styles.pendingText}>Waiting for safety check</Text>
                    </View>
                  ) : null}
                </View>
              </Card>
            );
          }}
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
            style={[styles.sendButton, (!text.trim() || sending || !online) && styles.sendButtonDisabled]}
            disabled={sending || !text.trim() || !online}
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
  pendingMsg: { color: colors.muted, fontStyle: 'italic' },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 4 },
  meta: { color: colors.muted, fontSize: 12 },
  pendingBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: '#FEF3C7',
    borderRadius: 10,
    paddingHorizontal: 8,
    paddingVertical: 3,
  },
  pendingText: { color: '#B45309', fontSize: 11, fontWeight: '700' },
  moreLoading: { textAlign: 'center', color: colors.muted, paddingVertical: 12, fontSize: 12 },
  sendErrorRow: { paddingHorizontal: 12, paddingTop: 4 },
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
});
