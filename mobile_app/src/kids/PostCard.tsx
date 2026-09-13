import { Image, Pressable, StyleSheet, Text, View } from 'react-native';
import type { InfiniteData } from '@tanstack/react-query';
import type { FeedItem, FeedPage } from '../api/kidsFeed';
import { useAuth } from '../auth/AuthProvider';
import { queryClient } from '../query/client';
import { invalidateSocialCaches, kidsKeys } from '../query/keys';
import { toggleLike, toggleSave } from '../api/kidsSocial';
import { isPubliclyVisible } from './social';
import { Avatar, CategoryBadge, TimeAgo } from '../ui/social';
import { colors, radius, spacing, type } from '../ui/tokens';

export function PostCard({ item, onOpen, onProfile }: { item: FeedItem; onOpen: () => void; onProfile: () => void }) {
  const { session } = useAuth();
  if (!isPubliclyVisible(item)) return null;

  async function onLike() {
    if (!session) return;
    const update = (old: InfiniteData<FeedPage> | undefined, liked: boolean, likes: number) => old ? ({
      ...old,
      pages: old.pages.map((page) => ({ ...page, items: page.items.map((post) => post.post_id === item.post_id ? { ...post, viewer_liked: liked, likes } : post) })),
    }) : old;
    const optimisticLiked = !item.viewer_liked;
    const optimisticLikes = (item.likes ?? 0) + (item.viewer_liked ? -1 : 1);
    queryClient.setQueriesData<InfiniteData<FeedPage>>({ queryKey: kidsKeys.feed }, (old) => update(old, optimisticLiked, optimisticLikes));
    queryClient.setQueriesData<InfiniteData<FeedPage>>({ queryKey: kidsKeys.reels }, (old) => update(old, optimisticLiked, optimisticLikes));
    try {
      const result = await toggleLike(session.token, item.post_id);
      queryClient.setQueriesData<InfiniteData<FeedPage>>({ queryKey: kidsKeys.feed }, (old) => update(old, result.liked, result.likes));
      queryClient.setQueriesData<InfiniteData<FeedPage>>({ queryKey: kidsKeys.reels }, (old) => update(old, result.liked, result.likes));
      await invalidateSocialCaches([item.post_id]);
    } catch {
      await queryClient.invalidateQueries({ queryKey: kidsKeys.feed });
    }
  }

  async function onSave() {
    if (!session) return;
    try {
      const result = await toggleSave(session.token, item.post_id);
      const update = (old: InfiniteData<FeedPage> | undefined) => old ? ({
        ...old,
        pages: old.pages.map((page) => ({ ...page, items: page.items.map((post) => post.post_id === item.post_id ? { ...post, viewer_saved: result.saved } : post) })),
      }) : old;
      queryClient.setQueriesData<InfiniteData<FeedPage>>({ queryKey: kidsKeys.feed }, update);
      queryClient.setQueriesData<InfiniteData<FeedPage>>({ queryKey: kidsKeys.reels }, update);
      await invalidateSocialCaches([item.post_id]);
    } catch {
      await queryClient.invalidateQueries({ queryKey: kidsKeys.saved });
    }
  }

  return (
    <View style={styles.card}>
      <Pressable onPress={onProfile} style={styles.row}>
        <Avatar uri={item.avatar_url} name={item.full_name} />
        <View style={styles.meta}>
          <Text style={styles.name}>{item.full_name ?? 'Friend'}</Text>
          <TimeAgo value={item.created_at} />
        </View>
        <CategoryBadge label={item.content_category} />
      </Pressable>
      {item.caption ? <Text style={styles.caption}>{item.caption}</Text> : null}
      {item.media_url && item.media_type?.toUpperCase() !== 'VIDEO' ? <Image source={{ uri: item.media_url }} style={styles.media} /> : null}
      <View style={styles.actions}>
        <Pressable onPress={() => void onLike()} style={styles.action}>
          <Text style={styles.actionText}>{item.viewer_liked ? '♥ Liked' : '♡ Like'} ({item.likes ?? 0})</Text>
        </Pressable>
        <Pressable onPress={() => void onSave()} style={styles.action}>
          <Text style={styles.actionText}>{item.viewer_saved ? '★ Saved' : '☆ Save'}</Text>
        </Pressable>
        <Pressable onPress={onOpen} style={styles.action}>
          <Text style={styles.actionText}>Comments ({item.comments_count ?? 0})</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: { backgroundColor: colors.surface, borderRadius: radius.lg, borderWidth: 1, borderColor: colors.line, padding: spacing.md, marginBottom: spacing.md },
  row: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  meta: { flex: 1 },
  name: { fontWeight: '800', color: colors.ink },
  caption: { marginTop: 8, color: colors.ink, fontSize: type.body, lineHeight: 22 },
  media: { marginTop: 10, width: '100%', height: 300, borderRadius: radius.md, backgroundColor: colors.line },
  actions: { flexDirection: 'row', marginTop: 8 },
  action: { paddingVertical: 8, paddingRight: 16 },
  actionText: { color: colors.brandDark, fontWeight: '700' },
});
