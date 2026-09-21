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
import { BrandHeader, Button, Card, EmptyState, ErrorState, GateNotice, LoadingState, Notice, Screen } from '../../ui/components';
import { colors, type } from '../../ui/tokens';

export function OtherProfileScreen({ route, navigation }: ChildScreenProps<'OtherProfile'>) {
  const { session } = useAuth();
  const targetId = Number((route.params as { targetId?: number } | undefined)?.targetId ?? 0);
  const [profile, setProfile] = useState<Record<string, unknown> | null>(null);
  const [posts, setPosts] = useState<PostDetail[]>([]);
  const [rel, setRel] = useState({ connected: false, pending: false, can_message: false });
  const [error, setError] = useState<unknown>(null);
  const [busy, setBusy] = useState(false);
  const [info, setInfo] = useState('');
  // After the viewer blocks this profile the backend hides it (404); keep a
  // local blocked state so the child can still unblock from here.
  const [blocked, setBlocked] = useState(false);
  const [muted, setMuted] = useState(false);
  const nav = navigation as unknown as { navigate: (r: string, p: object) => void; goBack: () => void };

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

  async function act(fn: (t: string) => Promise<unknown>, done?: string) {
    if (!session) return;
    setBusy(true);
    setInfo('');
    try {
      await fn(session.token);
      await invalidateSocialCaches();
      if (done) setInfo(done);
      await load();
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  }

  async function onBlockToggle() {
    if (!session) return;
    setBusy(true);
    setInfo('');
    try {
      const res = await blockUser(session.token, targetId, blocked ? 'unblock' : 'block');
      await invalidateSocialCaches();
      if (res.blocked) {
        // Blocked profiles disappear from every surface; leave this screen so
        // stale profile data is never shown.
        setBlocked(true);
        setInfo('Blocked. Their posts and profile are hidden from you.');
      } else {
        setBlocked(false);
        setInfo('Unblocked.');
        await load();
      }
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  }

  async function onMuteToggle() {
    if (!session) return;
    setBusy(true);
    setInfo('');
    try {
      const res = await muteUser(session.token, targetId, muted ? 'unmute' : 'mute');
      setMuted(res.muted);
      await invalidateSocialCaches();
      setInfo(res.muted ? 'Muted. Their posts will not appear in your feed.' : 'Unmuted.');
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  }

  if (blocked) {
    return (
      <Screen>
        <ScrollView>
          <BrandHeader title="Friend profile" subtitle="Blocked" />
          <Card>
            <Text style={styles.bio}>You blocked this account. Their posts, profile and messages are hidden.</Text>
            <View style={styles.btns}>
              <Button label={busy ? 'Working…' : 'Unblock'} disabled={busy} onPress={() => void onBlockToggle()} />
              <Button label="Back" variant="secondary" onPress={() => nav.goBack()} />
            </View>
            {info ? <Notice tone="info" message={info} /> : null}
            {error ? <GateNotice error={error} /> : null}
          </Card>
        </ScrollView>
      </Screen>
    );
  }

  if (error instanceof ApiError && error.status === 404) {
    return (
      <Screen>
        <EmptyState
          title="Profile unavailable"
          body="This profile cannot be shown. It may have been removed, or you may have blocked this account."
        />
        <Button label="Back" variant="secondary" onPress={() => nav.goBack()} />
      </Screen>
    );
  }
  if (error && !profile) return <Screen><GateNotice error={error} /><ErrorState message="Could not load this profile." onRetry={() => void load()} /></Screen>;
  if (!profile) return <Screen><LoadingState message="Loading profile…" /></Screen>;

  return (
    <Screen>
      <ScrollView>
        <BrandHeader title={String(profile.full_name ?? 'Friend')} subtitle="Friend profile" />
        {error ? <GateNotice error={error} /> : null}
        {info ? <Notice tone="info" message={info} /> : null}
        <Card>
          <Avatar uri={typeof profile.avatar_url === 'string' ? profile.avatar_url : null} name={String(profile.full_name ?? 'F')} size={64} />
          {typeof profile.bio === 'string' && profile.bio ? <Text style={styles.bio}>{profile.bio}</Text> : null}
          <Text style={styles.rel}>{rel.connected ? 'Connected' : rel.pending ? 'Request pending — needs parent approval' : 'Not connected'}</Text>
          <View style={styles.btns}>
            <Button
              label={rel.connected || rel.pending ? 'Unfollow' : 'Follow'}
              disabled={busy}
              onPress={() => void act(
                (t) => toggleFollow(t, targetId),
                rel.connected || rel.pending ? 'Removed.' : 'Request sent! A parent needs to approve it.',
              )}
            />
            <Button label="Message" variant="secondary" disabled={!canMessageRelationship(rel)} onPress={() => nav.navigate('Chat', { peerId: targetId })} />
          </View>
          {!canMessageRelationship(rel) ? <Text style={styles.rel}>Messaging is available after the friendship is approved.</Text> : null}
          <View style={styles.btns}>
            <Button label={muted ? 'Unmute' : 'Mute'} variant="secondary" disabled={busy} onPress={() => void onMuteToggle()} />
            <Button label="Block" variant="secondary" disabled={busy} onPress={() => void onBlockToggle()} />
          </View>
          <Button label="Report" variant="secondary" disabled={busy} onPress={() => void act((t) => submitReport(t, 'USER', targetId, 'Unsafe behavior'), 'Report sent for safety review.')} />
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
