import { useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, Image, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { useQuery } from '@tanstack/react-query';
import { searchDiscover, type KidSummary } from '../../api/kidsProfiles';
import { toggleFollow } from '../../api/kidsSocial';
import { useAuth } from '../../auth/AuthProvider';
import type { ChildScreenProps } from '../../navigation/types';
import { queryClient, useIsOnline } from '../../query/client';
import { kidsKeys } from '../../query/keys';
import { Avatar } from '../../ui/social';
import { DisabledFeature, EmptyState, ErrorState, GateNotice, OfflineBanner } from '../../ui/components';
import { ApiError } from '../../api/client';
import { useDebouncedSearch } from '../../kids/useSearch';
import { colors } from '../../ui/tokens';

export function DiscoverScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const { session } = useAuth();
  const online = useIsOnline();
  const { raw, setRaw, debounced } = useDebouncedSearch(300);
  const [kind, setKind] = useState<'People' | 'Posts' | 'Reels' | 'Learn'>('People');
  const [recent, setRecent] = useState<string[]>([]);
  const [followBusy, setFollowBusy] = useState<number | null>(null);
  const nav = navigation as unknown as { navigate: (r: string, p: object) => void };
  const token = session?.token ?? 'signed-out';
  const queryKey = [...kidsKeys.discover(debounced), token];

  const query = useQuery({
    queryKey,
    enabled: Boolean(session),
    staleTime: 30_000,
    queryFn: ({ signal }) => searchDiscover(session!.token, debounced, signal),
  });
  const kids = query.data?.children ?? [];
  const posts = query.data?.posts ?? [];
  const curated = query.data?.curated ?? [];
  const pii = !!query.data?.pii_warning;
  const loading = query.isPending;
  const error = query.error;

  // Track successful, non-PII searches for the "recent" strip.
  useEffect(() => {
    if (query.data && debounced.trim() && !query.data.pii_warning) {
      const term = debounced.trim();
      setRecent((old) => [term, ...old.filter((item) => item !== term)].slice(0, 5));
    }
  }, [query.data, debounced]);

  /** Follow/unfollow toggle with optimistic label and authoritative rollback. */
  async function onFollowKid(kid: KidSummary) {
    if (!session || followBusy) return;
    setFollowBusy(kid.user_id);
    const wasActive = Boolean(kid.is_following || kid.is_pending);
    // Optimistic: flip to the expected next state instantly.
    queryClient.setQueryData<Awaited<ReturnType<typeof searchDiscover>>>(queryKey, (old) =>
      old
        ? {
            ...old,
            children: old.children.map((c) =>
              c.user_id === kid.user_id
                ? { ...c, is_following: false, is_pending: !wasActive }
                : c,
            ),
          }
        : old,
    );
    try {
      await toggleFollow(session.token, kid.user_id);
    } catch {
      // Roll back to the authoritative server state on failure.
    } finally {
      setFollowBusy(null);
      await queryClient.invalidateQueries({ queryKey: kidsKeys.discover(debounced) });
    }
  }

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

      {!loading && !error && !kids.length && !posts.length && !curated.length ? (
        <EmptyState
          icon="search"
          title="No results found"
          body={raw ? 'Try another name, subject, or friendly topic.' : 'Explore safe learning, friends, and creative ideas.'}
        />
      ) : null}

      {error && !kids.length && !posts.length ? (
        <ErrorState message="Search is currently unavailable." onRetry={() => void query.refetch()} />
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
            const busy = followBusy === item.user_id;
            const statusLabel = busy ? '…' : item.is_following ? 'Following' : item.is_pending ? 'Requested' : 'Connect';
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
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel={item.is_following || item.is_pending ? `Unfollow ${displayName}` : `Follow ${displayName}`}
                  disabled={busy}
                  hitSlop={6}
                  onPress={(e) => {
                    e.stopPropagation();
                    void onFollowKid(item);
                  }}
                  style={[styles.personActionBtn, (item.is_following || item.is_pending) && styles.personActionBtnMuted]}
                >
                  <Text style={[styles.personActionText, (item.is_following || item.is_pending) && styles.personActionTextMuted]}>
                    {statusLabel}
                  </Text>
                </Pressable>
              </Pressable>
            );
          }}
        />
      ) : null}

      {/* Learn Mode: server-curated learning picks (displayed as-is; ranking is server-side) */}
      {kind === 'Learn' && curated.length > 0 ? (
        <View>
          <Text style={styles.sectionTitle}>Recommended for you</Text>
          <FlatList
            data={curated}
            horizontal
            keyExtractor={(c) => `curated:${c.source_id}`}
            contentContainerStyle={styles.curatedRow}
            showsHorizontalScrollIndicator={false}
            renderItem={({ item: c }) => {
              const imgUri = c.poster_url || c.media_url;
              return (
                <View style={styles.curatedCard}>
                  {imgUri ? (
                    <Image source={{ uri: imgUri }} style={styles.curatedThumb} resizeMode="cover" />
                  ) : (
                    <View style={styles.curatedPlaceholder}>
                      <Feather name="book-open" size={24} color="#94A3B8" />
                    </View>
                  )}
                  <Text style={styles.curatedCaption} numberOfLines={2}>{c.title || c.caption || 'Learning pick'}</Text>
                </View>
              );
            }}
          />
        </View>
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
  sectionTitle: {
    fontSize: 14,
    fontWeight: '800',
    color: colors.ink,
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: 8,
  },
  curatedRow: {
    paddingHorizontal: 16,
    gap: 10,
    paddingBottom: 8,
  },
  curatedCard: {
    width: 150,
    backgroundColor: colors.surface,
    borderRadius: 14,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: '#F0F0F0',
  },
  curatedThumb: {
    width: '100%',
    height: 110,
    backgroundColor: '#F1F5F9',
  },
  curatedPlaceholder: {
    width: '100%',
    height: 110,
    backgroundColor: '#F1F5F9',
    justifyContent: 'center',
    alignItems: 'center',
  },
  curatedCaption: {
    fontSize: 12,
    color: colors.ink,
    fontWeight: '600',
    lineHeight: 16,
    padding: 8,
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
