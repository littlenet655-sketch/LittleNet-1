import { useEffect, useState } from 'react';
import { Image, ScrollView, StyleSheet, Text, View } from 'react-native';
import { addComment, fetchPostDetail, toggleLike, toggleSave, type CommentItem, type PostDetail } from '../../api/kidsSocial';
import { useAuth } from '../../auth/AuthProvider';
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

  return (
    <Screen>
      <ScrollView>
        <Card>
          <View style={styles.row}>
            <Avatar uri={post.avatar_url} name={post.full_name} />
            <Text style={styles.name}>{post.full_name ?? 'Friend'}</Text>
          </View>
          {post.caption ? <Text style={styles.caption}>{post.caption}</Text> : null}
          {post.media_url ? <Image source={{ uri: post.media_url }} style={styles.media} /> : null}
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
        </Card>
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
});
