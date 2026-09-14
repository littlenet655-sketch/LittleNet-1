import { useEffect, useState } from 'react';
import { Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { fetchOwnProfile, updateOwnProfile } from '../../api/kidsProfiles';
import { fetchSaved } from '../../api/kidsSocial';
import { useAuth } from '../../auth/AuthProvider';
import type { ChildScreenProps } from '../../navigation/types';
import { queryClient } from '../../query/client';
import { invalidateSocialCaches, kidsKeys } from '../../query/keys';
import { Avatar } from '../../ui/social';
import { BrandHeader, Button, Card, EmptyState, ErrorState, Field, GateNotice, LoadingState, Notice, Screen } from '../../ui/components';
import { colors, type } from '../../ui/tokens';

type Tab = 'posts' | 'saved' | 'edit';

export function OwnProfileScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const { session } = useAuth();
  const [tab, setTab] = useState<Tab>('posts');
  const [bio, setBio] = useState('');
  const [name, setName] = useState('');
  const [saving, setSaving] = useState(false);
  const [savedMsg, setSavedMsg] = useState('');
  const [saveError, setSaveError] = useState<unknown>(null);
  const nav = navigation as unknown as { navigate: (r: string, p: object) => void };
  const profileQuery = useQuery({
    queryKey: [...kidsKeys.ownProfile, session?.token ?? 'signed-out'],
    enabled: Boolean(session),
    queryFn: () => fetchOwnProfile(session!.token),
  });
  const savedQuery = useQuery({
    queryKey: [...kidsKeys.saved, session?.token ?? 'signed-out'],
    enabled: Boolean(session),
    queryFn: () => fetchSaved(session!.token),
  });
  const profile = profileQuery.data?.profile ?? null;
  const posts = profileQuery.data?.posts ?? [];
  const counts = profileQuery.data?.counts ?? {};
  const saved = [...(savedQuery.data?.posts ?? []), ...(savedQuery.data?.reels ?? [])];
  const error = profileQuery.error ?? savedQuery.error ?? saveError;

  useEffect(() => {
    if (!profile) return;
    setBio(String(profile.bio ?? ''));
    setName(String(profile.full_name ?? ''));
  }, [profile]);

  if (profileQuery.isPending || savedQuery.isPending) return <Screen><LoadingState message="Loading your profile…" /></Screen>;
  if (profileQuery.error && !profile) return <Screen><GateNotice error={profileQuery.error} /><ErrorState message="Could not load your profile." onRetry={() => void profileQuery.refetch()} /></Screen>;

  const list = tab === 'saved' ? saved : posts;
  return (
    <Screen>
      <ScrollView refreshControl={undefined}>
        <BrandHeader title={String(profile?.full_name ?? 'Your profile')} subtitle="Your kind posts live here." />
        {error ? <GateNotice error={error} /> : null}
        <Card>
          <View style={styles.head}>
            <Avatar uri={typeof profile?.avatar_url === 'string' ? profile.avatar_url : null} name={String(profile?.full_name ?? 'Y')} size={64} />
            <Text style={styles.counts}>{`Posts ${posts.length} • Followers ${Number(counts.followers ?? 0)}`}</Text>
          </View>
          {typeof profile?.bio === 'string' && profile.bio ? <Text style={styles.bio}>{profile.bio}</Text> : null}
        </Card>
        <View style={styles.tabs}>
          {(['posts', 'saved', 'edit'] as Tab[]).map((t) => (
            <Pressable key={t} onPress={() => setTab(t)}><Text style={[styles.tab, tab === t && styles.tabActive]}>{t.toUpperCase()}</Text></Pressable>
          ))}
        </View>
        {tab === 'edit' ? (
          <Card>
            <Field label="Full name" value={name} onChangeText={setName} />
            <Field label="Bio" value={bio} onChangeText={setBio} multiline />
            {savedMsg ? <Notice tone="ok" message={savedMsg} /> : null}
            <Button label={saving ? 'Saving…' : 'Save changes'} disabled={saving} onPress={() => {
              if (!session) return;
              setSaving(true);
              setSaveError(null);
              updateOwnProfile(session.token, { full_name: name, bio }).then((updated) => {
                queryClient.setQueryData([...kidsKeys.ownProfile, session.token], updated);
                setSavedMsg('Profile updated.');
                void invalidateSocialCaches();
              }).catch((reason: unknown) => setSaveError(reason)).finally(() => setSaving(false));
            }} />
          </Card>
        ) : null}
        {tab !== 'edit' && !list.length ? <EmptyState title="Nothing here" body="Posts you create will appear here." /> : null}
        {list.map((post) => (
          <Pressable key={post.post_id} onPress={() => nav.navigate('PostDetail', { postId: post.post_id })}>
            <Card>
              {post.media_type?.toUpperCase() === 'VIDEO' && post.poster_url ? <Image source={{ uri: post.poster_url }} style={styles.thumb} /> : null}
              {post.media_url && post.media_type?.toUpperCase() !== 'VIDEO' ? <Image source={{ uri: post.media_url }} style={styles.thumb} /> : null}
              <Text style={styles.caption}>{post.caption || `Post ${post.post_id}`}</Text>
            </Card>
          </Pressable>
        ))}
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  head: { flexDirection: 'row', alignItems: 'center', gap: 18, paddingVertical: 8 },
  counts: { color: colors.ink, flex: 1, fontWeight: '600', lineHeight: 22 },
  bio: { marginTop: 8, color: colors.ink, fontSize: type.body },
  tabs: { flexDirection: 'row', justifyContent: 'space-around', marginVertical: 12, paddingVertical: 12, borderTopWidth: 1, borderBottomWidth: 1, borderColor: colors.line },
  tab: { color: colors.muted, fontWeight: '700', fontSize: 12 },
  tabActive: { color: colors.ink },
  thumb: { width: '100%', height: 180, borderRadius: 0, backgroundColor: colors.line },
  caption: { marginTop: 6, color: colors.ink },
});
