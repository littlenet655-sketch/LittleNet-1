import { useEffect, useState } from 'react';
import { ActivityIndicator, Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
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
  const { session, signOut } = useAuth();
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

  if (profileQuery.isPending && !profile) {
    return (
      <View style={styles.centerLoading}>
        <ActivityIndicator size="large" color={colors.brand} />
      </View>
    );
  }
  if (profileQuery.error && !profile) return <Screen><GateNotice error={profileQuery.error} /><ErrorState message="Could not load your profile." onRetry={() => void profileQuery.refetch()} /></Screen>;

  const list = tab === 'saved' ? saved : posts;

  return (
    <View style={styles.container}>
      <ScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        {error ? <GateNotice error={error} /> : null}

        {/* Instagram-style Profile Header */}
        <View style={styles.profileCard}>
          <View style={styles.headRow}>
            <Avatar
              uri={typeof profile?.avatar_url === 'string' ? profile.avatar_url : null}
              name={String(profile?.full_name ?? 'Kid')}
              size={72}
            />
            <View style={styles.statsRow}>
              <View style={styles.statItem}>
                <Text style={styles.statNum}>{posts.length}</Text>
                <Text style={styles.statLabel}>Posts</Text>
              </View>
              <Pressable
                style={styles.statItem}
                onPress={() => nav.navigate('Connections', { mode: 'followers' })}
              >
                <Text style={styles.statNum}>{Number(counts.followers ?? 0)}</Text>
                <Text style={styles.statLabel}>Friends</Text>
              </Pressable>
              <View style={styles.statItem}>
                <Text style={styles.statNum}>{saved.length}</Text>
                <Text style={styles.statLabel}>Saved</Text>
              </View>
            </View>
          </View>

          {/* User Name & Bio */}
          <View style={styles.bioSection}>
            <Text style={styles.profileName}>{String(profile?.full_name || 'LittleNet Explorer')}</Text>
            {typeof profile?.bio === 'string' && profile.bio ? (
              <Text style={styles.bioText}>{profile.bio}</Text>
            ) : (
              <Text style={styles.bioPlaceholder}>Learning, sharing kindness, and exploring safely ✨</Text>
            )}
          </View>

          {/* Action Pills Row */}
          <View style={styles.actionsRow}>
            <Pressable
              style={styles.actionPill}
              onPress={() => setTab(tab === 'edit' ? 'posts' : 'edit')}
            >
              <Text style={styles.actionPillText}>{tab === 'edit' ? 'Close Edit' : 'Edit Profile'}</Text>
            </Pressable>
            <Pressable
              style={styles.actionPill}
              onPress={() => nav.navigate('SavedContent', {})}
            >
              <Text style={styles.actionPillText}>Saved</Text>
            </Pressable>
            <Pressable
              style={[styles.actionPill, styles.actionPillDanger]}
              onPress={() => void signOut()}
            >
              <Text style={[styles.actionPillText, styles.actionPillTextDanger]}>Log Out</Text>
            </Pressable>
          </View>
        </View>

        {/* Tab Switcher */}
        <View style={styles.tabBar}>
          {(['posts', 'saved', 'edit'] as Tab[]).map((t) => {
            const active = tab === t;
            const label = t === 'posts' ? 'POSTS' : t === 'saved' ? 'SAVED' : 'EDIT BIO';
            return (
              <Pressable
                key={t}
                onPress={() => setTab(t)}
                style={[styles.tabItem, active && styles.tabItemActive]}
              >
                <Text style={[styles.tabLabel, active && styles.tabLabelActive]}>{label}</Text>
              </Pressable>
            );
          })}
        </View>

        {/* Edit Form */}
        {tab === 'edit' ? (
          <Card style={styles.editCard}>
            <Field label="Full name" value={name} onChangeText={setName} />
            <Field label="Bio" value={bio} onChangeText={setBio} multiline placeholder="Tell your friends what you like…" />
            {savedMsg ? <Notice tone="ok" message={savedMsg} /> : null}
            <Button
              label={saving ? 'Saving…' : 'Save changes'}
              disabled={saving}
              onPress={() => {
                if (!session) return;
                setSaving(true);
                setSaveError(null);
                updateOwnProfile(session.token, { full_name: name, bio })
                  .then((updated) => {
                    queryClient.setQueryData([...kidsKeys.ownProfile, session.token], updated);
                    setSavedMsg('Profile updated!');
                    void invalidateSocialCaches();
                  })
                  .catch((reason: unknown) => setSaveError(reason))
                  .finally(() => setSaving(false));
              }}
            />
          </Card>
        ) : null}

        {/* Empty State */}
        {tab !== 'edit' && !list.length ? (
          <EmptyState
            icon={tab === 'saved' ? 'bookmark' : 'image'}
            title={tab === 'saved' ? 'No saved posts yet' : 'No posts yet'}
            body={tab === 'saved' ? 'Posts and reels you bookmark will appear here.' : 'Share safe moments with friends using the + button!'}
          />
        ) : null}

        {/* 2-Column Media Grid */}
        {tab !== 'edit' && list.length > 0 ? (
          <View style={styles.grid}>
            {list.map((post) => {
              const isVid = post.media_type?.toUpperCase() === 'VIDEO';
              const imgUrl = isVid ? post.poster_url || post.media_url : post.media_url;
              return (
                <Pressable
                  key={post.post_id}
                  style={styles.gridCard}
                  onPress={() => nav.navigate('PostDetail', { postId: post.post_id })}
                >
                  {imgUrl ? (
                    <Image source={{ uri: imgUrl }} style={styles.gridThumb} resizeMode="cover" />
                  ) : (
                    <View style={styles.gridPlaceholder}>
                      <Text style={styles.placeholderIcon}>{isVid ? '🎬' : '🖼️'}</Text>
                    </View>
                  )}
                  {post.caption ? (
                    <View style={styles.captionWrap}>
                      <Text style={styles.gridCaption} numberOfLines={2}>
                        {post.caption}
                      </Text>
                    </View>
                  ) : null}
                </Pressable>
              );
            })}
          </View>
        ) : null}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  centerLoading: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.background,
  },
  scrollContent: {
    paddingBottom: 40,
  },
  profileCard: {
    backgroundColor: colors.surface,
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: '#F0F0F0',
  },
  headRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 20,
  },
  statsRow: {
    flex: 1,
    flexDirection: 'row',
    justifyContent: 'space-around',
    alignItems: 'center',
  },
  statItem: {
    alignItems: 'center',
  },
  statNum: {
    fontSize: 18,
    fontWeight: '800',
    color: colors.ink,
  },
  statLabel: {
    fontSize: 12,
    color: colors.muted,
    marginTop: 2,
  },
  bioSection: {
    marginTop: 12,
  },
  profileName: {
    fontSize: 16,
    fontWeight: '800',
    color: colors.ink,
  },
  bioText: {
    fontSize: 13,
    color: colors.ink,
    marginTop: 4,
    lineHeight: 18,
  },
  bioPlaceholder: {
    fontSize: 12,
    color: colors.muted,
    fontStyle: 'italic',
    marginTop: 3,
  },
  actionsRow: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 14,
  },
  actionPill: {
    flex: 1,
    backgroundColor: '#F1F5F9',
    borderRadius: 10,
    paddingVertical: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  actionPillDanger: {
    backgroundColor: '#FEF2F2',
  },
  actionPillText: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.ink,
  },
  actionPillTextDanger: {
    color: '#DC2626',
  },
  tabBar: {
    flexDirection: 'row',
    backgroundColor: colors.surface,
    borderBottomWidth: 1,
    borderBottomColor: '#F0F0F0',
  },
  tabItem: {
    flex: 1,
    paddingVertical: 12,
    alignItems: 'center',
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  tabItemActive: {
    borderBottomColor: colors.brand,
  },
  tabLabel: {
    fontSize: 12,
    fontWeight: '700',
    color: colors.muted,
    letterSpacing: 0.5,
  },
  tabLabelActive: {
    color: colors.brand,
  },
  editCard: {
    margin: 16,
  },
  grid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    padding: 10,
    gap: 10,
  },
  gridCard: {
    width: '48%',
    backgroundColor: colors.surface,
    borderRadius: 14,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: '#F0F0F0',
  },
  gridThumb: {
    width: '100%',
    height: 140,
    backgroundColor: '#F1F5F9',
  },
  gridPlaceholder: {
    width: '100%',
    height: 140,
    backgroundColor: '#F1F5F9',
    justifyContent: 'center',
    alignItems: 'center',
  },
  placeholderIcon: {
    fontSize: 32,
  },
  captionWrap: {
    padding: 8,
  },
  gridCaption: {
    fontSize: 11,
    fontWeight: '600',
    color: colors.ink,
    lineHeight: 15,
  },
});
