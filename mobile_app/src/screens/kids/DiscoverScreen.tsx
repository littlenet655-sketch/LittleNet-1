import { useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, Image, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { searchDiscover, type KidSummary } from '../../api/kidsProfiles';
import { useAuth } from '../../auth/AuthProvider';
import type { PostDetail } from '../../api/kidsSocial';
import type { ChildScreenProps } from '../../navigation/types';
import { Avatar } from '../../ui/social';
import { DisabledFeature, EmptyState, ErrorState, GateNotice, OfflineBanner, Skeleton } from '../../ui/components';
import { ApiError } from '../../api/client';
import { useIsOnline } from '../../query/client';
import { useDebouncedSearch } from '../../kids/useSearch';
import { colors, radius } from '../../ui/tokens';

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
        if (debounced.trim() && !res.pii_warning) {
          setRecent((old) => [debounced.trim(), ...old.filter((item) => item !== debounced.trim())].slice(0, 5));
        }
        setError(null);
      } catch (err) {
        if (!cancelled) setError(err);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
      controller.abort();
    };
  }, [session, debounced]);

  if (error instanceof ApiError && error.code === 'disabled_by_parent') {
    return <DisabledFeature feature="Discover" />;
  }

  const filteredPosts = posts.filter((p) => {
    if (kind === 'Learn') return String(p.content_category ?? '').toLowerCase().includes('learn');
    if (kind === 'Reels') return Boolean(p.is_reel);
    return true;
  });

  return (
    <View style={styles.container}>
      <OfflineBanner online={online} />

      {/* Modern Instagram Search Bar */}
      <View style={styles.searchContainer}>
        <View style={styles.searchBar}>
          <Feather name="search" size={17} color="#94A3B8" />
          <TextInput
            style={styles.searchInput}
            placeholder="Search friends, topics, posts…"
            placeholderTextColor="#94A3B8"
            value={raw}
            onChangeText={setRaw}
            autoCapitalize="none"
            autoCorrect={false}
            returnKeyType="search"
          />
          {raw ? (
            <Pressable onPress={() => setRaw('')} hitSlop={8}>
              <Feather name="x-circle" size={16} color="#94A3B8" />
            </Pressable>
          ) : null}
        </View>
      </View>

      {/* Recent Searches Pills */}
      {!raw && recent.length > 0 ? (
        <View style={styles.recentSection}>
          <Text style={styles.recentTitle}>RECENT</Text>
          <View style={styles.recentRow}>
            {recent.map((item) => (
              <Pressable key={item} onPress={() => setRaw(item)} style={styles.recentPill}>
                <Feather name="clock" size={11} color="#64748B" />
                <Text style={styles.recentText}>{item}</Text>
              </Pressable>
            ))}
          </View>
        </View>
      ) : null}

      {/* Filter Tabs */}
      <View style={styles.filterTabs}>
        {(['People', 'Posts', 'Reels', 'Learn'] as const).map((item) => {
          const active = kind === item;
          const icon = item === 'People' ? 'users' : item === 'Posts' ? 'grid' : item === 'Reels' ? 'film' : 'book-open';
          return (
            <Pressable
              key={item}
              onPress={() => setKind(item)}
              style={[styles.filterBtn, active && styles.filterBtnActive]}
            >
              <Feather name={icon} size={13} color={active ? '#FFFFFF' : '#64748B'} />
              <Text style={[styles.filterText, active && styles.filterTextActive]}>{item}</Text>
            </Pressable>
          );
        })}
      </View>

      {error ? <GateNotice error={error} /> : null}
      {pii ? (
        <GateNotice error={new ApiError(200, 'pii_warning', 'That search cannot be shown. Try different words.')} />
      ) : null}

      {loading && !kids.length && !posts.length ? (
        <View style={styles.loadingCenter}>
          <ActivityIndicator size="large" color={colors.brand} />
        </View>
      ) : null}

      {!loading && !error && !kids.length && !posts.length ? (
        <EmptyState
          icon="search"
          title="No results found"
          body={raw ? 'Try another name, subject, or friendly topic.' : 'Explore safe learning, friends, and creative ideas.'}
        />
      ) : null}

      {error && !kids.length && !posts.length ? (
        <ErrorState message="Search is currently unavailable." />
      ) : null}

      {/* People Mode: Vertical list of clean friend cards */}
      {kind === 'People' && kids.length > 0 ? (
        <FlatList
          data={kids}
          keyExtractor={(k) => `kid:${k.user_id}`}
          contentContainerStyle={styles.peopleList}
          showsVerticalScrollIndicator={false}
          renderItem={({ item }) => {
            const displayName = item.full_name || item.username;
            const statusLabel = item.is_following ? 'Following' : item.is_pending ? 'Requested' : 'Connect';
            return (
              <Pressable
                style={styles.personCard}
                onPress={() => nav.navigate('OtherProfile', { targetId: item.user_id })}
              >
                <Avatar uri={item.avatar_url} name={displayName} size={48} />
                <View style={styles.personMeta}>
                  <Text style={styles.personName} numberOfLines={1}>
                    {displayName}
                  </Text>
                  <Text style={styles.personSub} numberOfLines={1}>
                    @{item.username || 'friend'}
                  </Text>
                </View>
                <View style={[styles.personActionBtn, item.is_following && styles.personActionBtnMuted]}>
                  <Text style={[styles.personActionText, item.is_following && styles.personActionTextMuted]}>
                    {statusLabel}
                  </Text>
                </View>
              </Pressable>
            );
          }}
        />
      ) : null}

      {/* Posts / Reels / Learn Mode: 2-column visual grid */}
      {kind !== 'People' && filteredPosts.length > 0 ? (
        <FlatList
          data={filteredPosts}
          keyExtractor={(p) => `post:${p.post_id}`}
          numColumns={2}
          contentContainerStyle={styles.gridContainer}
          columnWrapperStyle={styles.gridRow}
          showsVerticalScrollIndicator={false}
          renderItem={({ item: p }) => {
            const hasVideo = p.media_type?.toUpperCase() === 'VIDEO' || p.is_reel;
            const imgUri = hasVideo ? p.poster_url || p.media_url : p.media_url;
            return (
              <Pressable
                style={styles.gridItem}
                onPress={() => nav.navigate('PostDetail', { postId: p.post_id })}
              >
                {imgUri ? (
                  <Image source={{ uri: imgUri }} style={styles.gridThumb} resizeMode="cover" />
                ) : (
                  <View style={styles.gridPlaceholder}>
                    <Feather name={hasVideo ? 'film' : 'file-text'} size={24} color="#94A3B8" />
                  </View>
                )}
                {hasVideo ? (
                  <View style={styles.videoBadge}>
                    <Feather name="play" size={11} color="#FFFFFF" />
                  </View>
                ) : null}
                <View style={styles.gridCaptionWrap}>
                  <Text style={styles.gridCaption} numberOfLines={2}>
                    {p.caption || `Post #${p.post_id}`}
                  </Text>
                </View>
              </Pressable>
            );
          }}
        />
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  searchContainer: {
    paddingHorizontal: 16,
    paddingTop: 10,
    paddingBottom: 8,
    backgroundColor: colors.surface,
  },
  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: '#F1F5F9',
    borderRadius: 12,
    paddingHorizontal: 12,
    height: 40,
  },
  searchInput: {
    flex: 1,
    fontSize: 14,
    color: colors.ink,
    paddingVertical: 0,
  },
  recentSection: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    backgroundColor: colors.surface,
    borderBottomWidth: 1,
    borderBottomColor: '#F0F0F0',
  },
  recentTitle: {
    fontSize: 10,
    fontWeight: '800',
    color: '#94A3B8',
    letterSpacing: 0.8,
    marginBottom: 6,
  },
  recentRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  recentPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: '#F1F5F9',
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 14,
  },
  recentText: {
    fontSize: 12,
    color: '#475569',
    fontWeight: '600',
  },
  filterTabs: {
    flexDirection: 'row',
    paddingHorizontal: 16,
    paddingVertical: 10,
    backgroundColor: colors.surface,
    borderBottomWidth: 1,
    borderBottomColor: '#F0F0F0',
    gap: 8,
  },
  filterBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 18,
    backgroundColor: '#F1F5F9',
  },
  filterBtnActive: {
    backgroundColor: colors.brand,
  },
  filterText: {
    fontSize: 12,
    fontWeight: '700',
    color: '#64748B',
  },
  filterTextActive: {
    color: '#FFFFFF',
  },
  loadingPadding: {
    padding: 16,
  },
  peopleList: {
    padding: 16,
    gap: 10,
  },
  personCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    padding: 12,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: '#F0F0F0',
    gap: 12,
  },
  personMeta: {
    flex: 1,
  },
  personName: {
    fontSize: 15,
    fontWeight: '700',
    color: colors.ink,
    marginBottom: 2,
  },
  personSub: {
    fontSize: 12,
    color: colors.muted,
  },
  personActionBtn: {
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderRadius: 16,
    backgroundColor: colors.brand,
  },
  personActionBtnMuted: {
    backgroundColor: '#F1F5F9',
  },
  personActionText: {
    fontSize: 12,
    fontWeight: '700',
    color: '#FFFFFF',
  },
  personActionTextMuted: {
    color: '#64748B',
  },
  gridContainer: {
    padding: 12,
    gap: 10,
  },
  gridRow: {
    gap: 10,
  },
  gridItem: {
    flex: 1,
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
  videoBadge: {
    position: 'absolute',
    top: 8,
    right: 8,
    backgroundColor: 'rgba(0,0,0,0.6)',
    width: 24,
    height: 24,
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
  },
  gridCaptionWrap: {
    padding: 10,
  },
  gridCaption: {
    fontSize: 12,
    color: colors.ink,
    fontWeight: '600',
    lineHeight: 16,
  },
  loadingCenter: {
    paddingVertical: 50,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
