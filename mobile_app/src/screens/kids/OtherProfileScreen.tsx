import { useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { ApiError } from '../../api/client';
import { fetchOtherProfile } from '../../api/kidsProfiles';
import { blockUser, muteUser, submitReport, toggleFollow, type PostDetail } from '../../api/kidsSocial';
import { useAuth } from '../../auth/AuthProvider';
import { canMessageRelationship } from '../../kids/social';
import type { ChildScreenProps } from '../../navigation/types';
import { invalidateSocialCaches } from '../../query/keys';
import { Avatar } from '../../ui/social';
import { BrandHeader, Button, Card, EmptyState, ErrorState, GateNotice, LoadingState, Screen } from '../../ui/components';
import { colors, type } from '../../ui/tokens';

export function OtherProfileScreen({ route, navigation }: ChildScreenProps<'OtherProfile'>) {
  const { session } = useAuth();
  const targetId = Number((route.params as { targetId?: number } | undefined)?.targetId ?? 0);
  const [profile, setProfile] = useState<Record<string, unknown> | null>(null);
  const [posts, setPosts] = useState<PostDetail[]>([]);
  const [rel, setRel] = useState({ connected: false, pending: false, can_message: false });
  const [error, setError] = useState<unknown>(null);
  const [busy, setBusy] = useState(false);
  const nav = navigation as unknown as { navigate: (r: string, p: object) => void };

  async function load() {
    if (!session || !targetId) return;
    try {
      const res = await fetchOtherProfile(session.token, targetId);
      setProfile(res.profile);
      setPosts(res.posts ?? []);
      if (res.relationship) setRel(res.relationship);
      setError(null);
    } catch (err) {
      setError(err);
    }
  }

  useEffect(() => { void load(); }, [session?.token, targetId]);

  async function act(fn: (t: string) => Promise<unknown>) {
    if (!session) return;
    setBusy(true);
    try {
      await fn(session.token);
      await invalidateSocialCaches();
      await load();
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  }

  if (error instanceof ApiError && error.status === 404) return <Screen><EmptyState title="Profile unavailable" body="This profile cannot be shown." /></Screen>;
  if (error && !profile) return <Screen><GateNotice error={error} /><ErrorState message="Could not load this profile." onRetry={() => void load()} /></Screen>;
  if (!profile) return <Screen><LoadingState message="Loading profile…" /></Screen>;

  return (
    <Screen>
      <ScrollView>
        <BrandHeader title={String(profile.full_name ?? 'Friend')} subtitle="Friend profile" />
        {error ? <GateNotice error={error} /> : null}
        <Card>
          <Avatar uri={typeof profile.avatar_url === 'string' ? profile.avatar_url : null} name={String(profile.full_name ?? 'F')} size={64} />
          {typeof profile.bio === 'string' && profile.bio ? <Text style={styles.bio}>{profile.bio}</Text> : null}
          <Text style={styles.rel}>{rel.connected ? 'Connected' : rel.pending ? 'Request pending' : 'Not connected'}</Text>
          <View style={styles.btns}>
            <Button label={rel.connected || rel.pending ? 'Unfollow' : 'Follow'} disabled={busy} onPress={() => void act((t) => toggleFollow(t, targetId))} />
            <Button label="Message" variant="secondary" disabled={!canMessageRelationship(rel)} onPress={() => nav.navigate('Chat', { peerId: targetId })} />
          </View>
          {!canMessageRelationship(rel) ? <Text style={styles.rel}>Messaging is available after the friendship is approved.</Text> : null}
          <View style={styles.btns}>
            <Button label="Mute" variant="secondary" disabled={busy} onPress={() => void act((t) => muteUser(t, targetId, 'mute'))} />
            <Button label="Block" variant="secondary" disabled={busy} onPress={() => void act((t) => blockUser(t, targetId, 'block'))} />
          </View>
          <Button label="Report" variant="secondary" disabled={busy} onPress={() => void act((t) => submitReport(t, 'USER', targetId, 'Unsafe behavior'))} />
        </Card>
        {posts.map((p) => (
          <Pressable key={p.post_id} onPress={() => nav.navigate('PostDetail', { postId: p.post_id })}>
            <Card><Text style={styles.bio}>{p.caption || `Post ${p.post_id}`}</Text></Card>
          </Pressable>
        ))}
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  bio: { marginTop: 8, color: colors.ink, fontSize: type.body, lineHeight: 20 },
  rel: { marginTop: 6, color: colors.muted, fontSize: 12 },
  btns: { flexDirection: 'row', gap: 8, marginTop: 8, flex: 1 },
});
