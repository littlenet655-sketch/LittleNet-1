import { useEffect, useState } from 'react';
import { Image, ScrollView, StyleSheet, Text, View } from 'react-native';
import { addComment, blockUser, fetchPostDetail, muteUser, submitReport, toggleLike, toggleSave, type CommentItem, type PostDetail } from '../../api/kidsSocial';
import { useAuth } from '../../auth/AuthProvider';
import { VideoMedia } from '../../kids/VideoMedia';
import type { ChildScreenProps } from '../../navigation/types';
import { invalidateSocialCaches } from '../../query/keys';
import { Avatar } from '../../ui/social';
import { Button, Card, Field, GateNotice, LoadingState, Notice, Screen } from '../../ui/components';
import { colors } from '../../ui/tokens';

export function PostDetailScreen({ route }: ChildScreenProps<'PostDetail'>) {
  const { session } = useAuth();
  const postId = Number((route.params as { postId?: number } | undefined)?.postId ?? 0);
  const [post, setPost] = useState<PostDetail | null>(null);
  const [comments, setComments] = useState<CommentItem[]>([]);
  const [text, setText] = useState('');
  const [info, setInfo] = useState('');
  const [error, setError] = useState<unknown>(null);
  const [busy, setBusy] = useState(false);
  const [safetyOpen, setSafetyOpen] = useState(false);
  const [safetyBusy, setSafetyBusy] = useState(false);
  const [safetyError, setSafetyError] = useState('');
  const [hidden, setHidden] = useState(false);
  const [reason, setReason] = useState('');
  const reasons = ['Unsafe or unkind', 'Personal information', 'Something else'];

  async function load() {
    if (!session || !postId) return;
    try {
      const res = await fetchPostDetail(session.token, postId);
      setPost(res.post);
      setComments(res.comments ?? []);
      setError(null);
    } catch (err) {
      setError(err);
    }
  }

  useEffect(() => { void load(); }, [session?.token, postId]);
  if (!post) return <Screen><LoadingState message="Loading post…" /></Screen>;
  if (hidden) return <Screen><Notice tone="ok" message="This post is hidden on this device." /><Button label="Back to post" variant="secondary" onPress={() => setHidden(false)} /></Screen>;

  async function onLike() {
    if (!session || !post) return;
    try {
      const res = await toggleLike(session.token, postId);
      setPost({ ...post, viewer_liked: res.liked, likes: res.likes });
      await invalidateSocialCaches([postId]);
    } catch (err) {
      setError(err);
    }
  }

  async function onComment() {
    if (!session || !text.trim()) return;
    setBusy(true);
    setInfo('');
    try {
      const res = await addComment(session.token, postId, text.trim());
      setText('');
      if (res.status === 'REVIEW') setInfo('Your comment is waiting for a safety check.');
      else await load();
      await invalidateSocialCaches([postId]);
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  }

  async function safetyAction(action: 'report' | 'block' | 'mute') {
    const creatorId = post?.child_id;
    if (!session || !creatorId) return;
    if (action === 'report' && !reason) {
      setSafetyError('Choose a report reason before sending.');
      return;
    }
    setSafetyBusy(true);
    setSafetyError('');
    try {
      if (action === 'report') await submitReport(session.token, 'POST', postId, reason);
      if (action === 'block') await blockUser(session.token, creatorId, 'BLOCK');
      if (action === 'mute') await muteUser(session.token, creatorId, 'MUTE');
      await invalidateSocialCaches([postId]);
      setSafetyOpen(false);
      setInfo(action === 'report' ? 'Report sent for safety review.' : action === 'block' ? 'Creator blocked.' : 'Creator muted.');
    } catch (err) {
      setSafetyError(err instanceof Error ? err.message : 'Safety action failed. Try again.');
    } finally {
      setSafetyBusy(false);
    }
  }

  return (
    <Screen>
      <ScrollView>
        <Card>
          <View style={styles.row}>
            <Avatar uri={post.avatar_url} name={post.full_name} />
            <Text style={styles.name}>{post.full_name ?? 'Friend'}</Text>
          </View>
          {post.caption ? <Text style={styles.caption}>{post.caption}</Text> : null}
          {post.media_url && post.media_type?.toUpperCase() === 'VIDEO' ? <VideoMedia source={post.media_url} posterUrl={post.poster_url} height={320} /> : null}
          {post.media_url && post.media_type?.toUpperCase() !== 'VIDEO' ? <Image source={{ uri: post.media_url }} style={styles.media} /> : null}
          <View style={styles.row}>
            <Button label={post.viewer_liked ? 'Liked' : 'Like'} onPress={() => void onLike()} />
            <Button label={post.viewer_saved ? 'Saved' : 'Save'} variant="secondary" onPress={() => {
              if (!session) return;
              toggleSave(session.token, postId).then((r) => {
                setPost({ ...post, viewer_saved: r.saved });
                void invalidateSocialCaches([postId]);
              }).catch((err: unknown) => setError(err));
            }} />
          </View>
          <Button label="Safety actions" variant="secondary" onPress={() => { setSafetyOpen((value) => !value); setSafetyError(''); }} />
        </Card>
        {safetyOpen ? <Card>
          <Text style={styles.safetyTitle}>What would you like to do?</Text>
          <Button label="Hide this post" variant="secondary" disabled={safetyBusy} onPress={() => { setHidden(true); setSafetyOpen(false); }} />
          <Button label="Block creator" variant="secondary" disabled={safetyBusy} onPress={() => void safetyAction('block')} />
          <Button label="Mute creator" variant="secondary" disabled={safetyBusy} onPress={() => void safetyAction('mute')} />
          <Text style={styles.reasonLabel}>Report reason</Text>
          {reasons.map((item) => <Button key={item} label={reason === item ? `Selected: ${item}` : item} variant={reason === item ? 'primary' : 'secondary'} disabled={safetyBusy} onPress={() => setReason(item)} />)}
          <Button label={safetyBusy ? 'Sending…' : 'Send report'} disabled={safetyBusy || !reason} onPress={() => void safetyAction('report')} />
          {safetyError ? <Notice message={safetyError} /> : null}
        </Card> : null}
        {error ? <GateNotice error={error} /> : null}
        {info ? <Notice tone="info" message={info} /> : null}
        <Card>
          <Field label="Add a kind comment" value={text} onChangeText={setText} multiline placeholder="Say something kind…" />
          <Button label={busy ? 'Sending…' : 'Comment'} disabled={busy || !text.trim()} onPress={() => void onComment()} />
        </Card>
        {comments.map((c) => (
          <Card key={c.comment_id}>
            <View style={styles.row}>
              <Avatar uri={c.avatar_url} name={c.full_name} size={28} />
              <Text style={styles.name}>{c.full_name ?? 'Friend'}</Text>
            </View>
            <Text style={styles.caption}>{c.comment_text}</Text>
          </Card>
        ))}
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 8 },
  name: { fontWeight: '800', color: colors.ink },
  caption: { marginTop: 8, color: colors.ink },
  media: { marginTop: 10, width: '100%', height: 320, borderRadius: 12, backgroundColor: colors.line },
  safetyTitle: { color: colors.ink, fontSize: 17, fontWeight: '700' },
  reasonLabel: { color: colors.muted, fontSize: 12, fontWeight: '700', marginTop: 12, marginBottom: 2 },
});
