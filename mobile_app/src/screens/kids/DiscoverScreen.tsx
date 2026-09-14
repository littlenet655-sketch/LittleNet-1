import { useEffect, useState } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { searchDiscover, type KidSummary } from '../../api/kidsProfiles';
import { useAuth } from '../../auth/AuthProvider';
import type { PostDetail } from '../../api/kidsSocial';
import type { ChildScreenProps } from '../../navigation/types';
import { Avatar } from '../../ui/social';
import { BrandHeader, DisabledFeature, EmptyState, ErrorState, Field, GateNotice, OfflineBanner, Screen, Skeleton } from '../../ui/components';
import { ApiError } from '../../api/client';
import { useIsOnline } from '../../query/client';
import { useDebouncedSearch } from '../../kids/useSearch';
import { colors } from '../../ui/tokens';

export function DiscoverScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const { session } = useAuth();
  const online = useIsOnline();
  const { raw, setRaw, debounced } = useDebouncedSearch(300);
  const [kids, setKids] = useState<KidSummary[]>([]);
  const [posts, setPosts] = useState<PostDetail[]>([]);
  const [pii, setPii] = useState(false);
  const [kind, setKind] = useState<'People' | 'Posts' | 'Reels' | 'Learn'>('People');
  const [recent, setRecent] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<unknown>(null);
  const nav = navigation as unknown as { navigate: (r: string, p: object) => void };

  useEffect(() => {
    let cancelled = false;
    const controller = new AbortController();
    (async () => {
      if (!session) return;
      setLoading(true);
      try {
        const res = await searchDiscover(session.token, debounced, controller.signal);
        if (cancelled) return;
        setKids(res.children ?? []);
        setPosts(res.posts ?? []);
       setPii(!!res.pii_warning);
       if (debounced.trim() && !res.pii_warning) setRecent((old) => [debounced.trim(), ...old.filter((item) => item !== debounced.trim())].slice(0, 5));
        setError(null);
      } catch (err) {
        if (!cancelled) setError(err);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; controller.abort(); };
  }, [session, debounced]);

  if (error instanceof ApiError && error.code === 'disabled_by_parent') return <Screen><DisabledFeature feature="Discover" /></Screen>;

  return (
    <Screen>
      <BrandHeader title="Discover" subtitle="Find friends and kind posts." />
      <OfflineBanner online={online} />
      <Field label="Search" placeholder="Search friends or topics" value={raw} onChangeText={setRaw} autoCapitalize="none" />
      {!raw && recent.length ? <View style={styles.recent}><Text style={styles.sub}>Recent searches</Text>{recent.map((item) => <Pressable key={item} onPress={() => setRaw(item)}><Text style={styles.recentItem}>{item}</Text></Pressable>)}</View> : null}
      <View style={styles.filters}>{(['People', 'Posts', 'Reels', 'Learn'] as const).map((item) => <Pressable key={item} onPress={() => setKind(item)}><Text style={[styles.filter, kind === item && styles.filterActive]}>{item}</Text></Pressable>)}</View>
      {error ? <GateNotice error={error} /> : null}
      {pii ? <GateNotice error={new ApiError(200, 'pii_warning', 'That search cannot be shown. Try different words.')} /> : null}
      {loading ? <Skeleton lines={4} /> : null}
      {!loading && !error && !kids.length && !posts.length ? <EmptyState title="No results" body="Try another name or topic." /> : null}
      {error && !kids.length ? <ErrorState message="Search is unavailable." /> : null}
       {kind === 'People' ? <FlatList
        data={kids}
        keyExtractor={(k) => `kid:${k.user_id}`}
        horizontal
        renderItem={({ item }) => (
          <Pressable style={styles.person} onPress={() => nav.navigate('OtherProfile', { targetId: item.user_id })}>
            <Avatar uri={item.avatar_url} name={item.full_name} size={52} />
            <Text style={styles.name}>{item.full_name ?? item.username}</Text>
            <Text style={styles.sub}>{item.is_following ? 'Following' : item.is_pending ? 'Requested' : 'Friend'}</Text>
          </Pressable>
        )}
       /> : <View style={styles.grid}>
         {posts.filter((p) => kind === 'Learn' ? String(p.content_category ?? '').toLowerCase().includes('learn') : kind === 'Reels' ? !!p.is_reel : true).map((p) => (
          <Pressable key={`post:${p.post_id}`} onPress={() => nav.navigate('PostDetail', { postId: p.post_id })}>
            <Text style={styles.post}>{p.caption || `Post ${p.post_id}`}</Text>
          </Pressable>
        ))}
       </View>}
    </Screen>
  );
}

const styles = StyleSheet.create({
  person: { alignItems: 'center', marginRight: 14, width: 78, paddingVertical: 8 },
  name: { fontWeight: '700', color: colors.ink, textAlign: 'center' },
  sub: { color: colors.muted, fontSize: 12, fontWeight: '700' },
  post: { paddingVertical: 14, paddingHorizontal: 12, color: colors.ink, borderBottomWidth: 1, borderBottomColor: colors.line, backgroundColor: colors.surface },
  filters: { flexDirection: 'row', justifyContent: 'space-around', paddingVertical: 12, borderBottomWidth: 1, borderColor: colors.line },
  filter: { color: colors.muted, fontWeight: '700' },
  filterActive: { color: colors.ink, borderBottomWidth: 2, borderBottomColor: colors.brand, paddingBottom: 5 },
  recent: { paddingVertical: 8 },
  recentItem: { color: colors.ink, paddingVertical: 7 },
  grid: { flexDirection: 'row', flexWrap: 'wrap' },
});
