import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { FlatList, Keyboard, KeyboardAvoidingView, Platform, Pressable, RefreshControl, StyleSheet, Text, TextInput, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { useIsFocused } from '@react-navigation/native';
import { fetchChat, sendChatText, sharePostToChat, type ChatMessage } from '../../api/kidsChat';
import { ApiError } from '../../api/client';
import { useAuth } from '../../auth/AuthProvider';
import { CHAT_BLOCKED_COPY, dedupeChat, isChatMessagePending } from '../../kids/social';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsForeground, useIsOnline } from '../../query/client';
import { Button, DisabledFeature, EmptyState, ErrorState, GateNotice, LoadingState, Notice, OfflineBanner, Screen } from '../../ui/components';
import { colors, radius } from '../../ui/tokens';

const PAGE_SIZE = 30;

type Row =
  | { kind: 'day'; key: string; label: string }
  | { kind: 'msg'; key: string; message: ChatMessage };

function dayKey(iso?: string): string {
  const t = iso ? Date.parse(iso) : Number.NaN;
  if (Number.isNaN(t)) return 'unknown';
  const d = new Date(t);
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

function dayLabel(iso?: string): string {
  const t = iso ? Date.parse(iso) : Number.NaN;
  if (Number.isNaN(t)) return '';
  const d = new Date(t);
  const now = new Date();
  const sameDay = (a: Date, b: Date) =>
    a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (sameDay(d, now)) return 'Today';
  if (sameDay(d, yesterday)) return 'Yesterday';
  return d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
}

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

  // Insert centered date-divider pills wherever the calendar day changes.
  const rows = useMemo<Row[]>(() => {
    const out: Row[] = [];
    let lastDay = '';
    for (const m of messages) {
      const day = dayKey(m.sent_at);
      if (day !== lastDay) {
        const label = dayLabel(m.sent_at);
        if (label) out.push({ kind: 'day', key: `d:${day}`, label });
        lastDay = day;
      }
      out.push({ kind: 'msg', key: `m:${m.child_message_id}`, message: m });
    }
    return out;
  }, [messages]);

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
      const newRows = res.messages ?? [];
      setMessages((prev) => (mode === 'more' ? dedupeChat([...newRows, ...prev]) : dedupeChat(newRows)));
      if (mode === 'more' || mode === 'first') setHasMore(newRows.length >= PAGE_SIZE);
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
          data={rows}
          keyExtractor={(r) => r.key}
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
            if (item.kind === 'day') {
              return (
                <View style={styles.dayDivider}>
                  <Text style={styles.dayLabel}>{item.label}</Text>
                </View>
              );
            }
            const m = item.message;
            const isOwn = ownId !== 0 && m.sender_child_id === ownId;
            const pending = isChatMessagePending(m, isOwn);
            return (
              <View style={[styles.row, isOwn && styles.rowOwn]}>
                <View style={[styles.bubble, isOwn ? styles.bubbleOwn : styles.bubblePeer]}>
                  {m.message_type === 'SHARED_POST' ? (
                    <Text style={[styles.msg, isOwn && styles.msgOwn]}>Shared a post (#{m.shared_post_id ?? ''})</Text>
                  ) : (
                    <Text style={[styles.msg, isOwn && styles.msgOwn, pending && styles.pendingMsg]}>
                      {m.message_text}
                    </Text>
                  )}
                </View>
                {pending ? (
                  <View style={styles.pendingBadge}>
                    <Feather name="clock" size={11} color="#B45309" />
                    <Text style={styles.pendingText}>Waiting for safety check</Text>
                  </View>
                ) : null}
              </View>
            );
          }}
        />
        <View style={styles.inputRow}>
          <TextInput
            style={styles.chatInput}
            value={text}
            onChangeText={setText}
            placeholder="Message…"
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
            <Feather name="send" size={17} color="#FFFFFF" />
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
  listContent: { paddingHorizontal: 12, paddingBottom: 16, paddingTop: 8, flexGrow: 1 },
  dayDivider: {
    alignSelf: 'center',
    backgroundColor: '#EFEFEF',
    borderRadius: radius.pill,
    paddingHorizontal: 12,
    paddingVertical: 5,
    marginVertical: 10,
  },
  dayLabel: {
    fontSize: 12,
    color: colors.muted,
    fontWeight: '700',
  },
  row: {
    alignItems: 'flex-start',
    marginVertical: 2,
  },
  rowOwn: {
    alignItems: 'flex-end',
  },
  bubble: {
    maxWidth: '75%',
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 18,
  },
  bubblePeer: {
    backgroundColor: '#EFEFEF',
    borderBottomLeftRadius: 4,
  },
  bubbleOwn: {
    backgroundColor: colors.brand,
    borderBottomRightRadius: 4,
  },
  msg: {
    color: '#262626',
    fontSize: 14,
    fontWeight: '400',
    lineHeight: 20,
  },
  msgOwn: {
    color: '#FFFFFF',
  },
  pendingMsg: { color: colors.muted, fontStyle: 'italic' },
  pendingBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: '#FEF3C7',
    borderRadius: 10,
    paddingHorizontal: 8,
    paddingVertical: 3,
    marginTop: 4,
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
    backgroundColor: '#EFEFEF',
    borderRadius: 24,
    paddingHorizontal: 16,
    paddingVertical: 10,
    fontSize: 14,
    color: colors.ink,
  },
  sendButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: colors.brand,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sendButtonDisabled: {
    opacity: 0.5,
  },
});
