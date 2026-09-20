import { Image, Pressable, StyleSheet, Text, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import type { InfiniteData } from '@tanstack/react-query';
import type { FeedItem, FeedPage } from '../api/kidsFeed';
import { useAuth } from '../auth/AuthProvider';
import { queryClient } from '../query/client';
import { invalidateSocialCaches, kidsKeys } from '../query/keys';
import { toggleLike, toggleSave } from '../api/kidsSocial';
import { isPubliclyVisible, runSocialPostAction, socialPostTarget } from './social';
import { VideoMedia } from './VideoMedia';
import { Avatar, CategoryBadge, TimeAgo } from '../ui/social';
import { colors, radius, spacing, type } from '../ui/tokens';

export function PostCard({
  item,
  onOpen,
  onProfile,
  onNotInterested,
  inlineVideoPlayback = false,
  videoActive = false,
}: {
  item: FeedItem;
  onOpen?: () => void;
  onProfile?: () => void;
  onNotInterested?: () => void;
  inlineVideoPlayback?: boolean;
  videoActive?: boolean;
}) {
  const { session } = useAuth();
  if (!isPubliclyVisible(item)) return null;
  const socialTarget = socialPostTarget(item);
  const isVideo = item.media_type?.toUpperCase() === 'VIDEO';
  const previewUrl = isVideo ? item.poster_url : item.media_url;

  async function onLike() {
    if (!session || !socialTarget) return;
    const postId = socialTarget.postId;
    const update = (old: InfiniteData<FeedPage> | undefined, liked: boolean, likes: number) => old ? ({
      ...old,
      pages: old.pages.map((page) => ({ ...page, items: page.items.map((post) => post.source_type === 'SOCIAL' && post.post_id === postId ? { ...post, viewer_liked: liked, likes } : post) })),
    }) : old;
    const optimisticLiked = !item.viewer_liked;
    const optimisticLikes = (item.likes ?? 0) + (item.viewer_liked ? -1 : 1);
    queryClient.setQueriesData<InfiniteData<FeedPage>>({ queryKey: kidsKeys.feed }, (old) => update(old, optimisticLiked, optimisticLikes));
    queryClient.setQueriesData<InfiniteData<FeedPage>>({ queryKey: kidsKeys.reels }, (old) => update(old, optimisticLiked, optimisticLikes));
    try {
      const result = await runSocialPostAction(item, (id) => toggleLike(session.token, id));
      if (!result) return;
      queryClient.setQueriesData<InfiniteData<FeedPage>>({ queryKey: kidsKeys.feed }, (old) => update(old, result.liked, result.likes));
      queryClient.setQueriesData<InfiniteData<FeedPage>>({ queryKey: kidsKeys.reels }, (old) => update(old, result.liked, result.likes));
      await invalidateSocialCaches([postId]);
    } catch {
      await queryClient.invalidateQueries({ queryKey: kidsKeys.feed });
    }
  }

  async function onSave() {
    if (!session || !socialTarget) return;
    const postId = socialTarget.postId;
    try {
      const result = await runSocialPostAction(item, (id) => toggleSave(session.token, id));
      if (!result) return;
      const update = (old: InfiniteData<FeedPage> | undefined) => old ? ({
        ...old,
        pages: old.pages.map((page) => ({ ...page, items: page.items.map((post) => post.source_type === 'SOCIAL' && post.post_id === postId ? { ...post, viewer_saved: result.saved } : post) })),
      }) : old;
      queryClient.setQueriesData<InfiniteData<FeedPage>>({ queryKey: kidsKeys.feed }, update);
      queryClient.setQueriesData<InfiniteData<FeedPage>>({ queryKey: kidsKeys.reels }, update);
      await invalidateSocialCaches([postId]);
    } catch {
      await queryClient.invalidateQueries({ queryKey: kidsKeys.saved });
    }
  }

  return (
    <View style={styles.card}>
      <View style={styles.row}>
        <Pressable onPress={onProfile} disabled={!onProfile} style={styles.profileRow}>
          <Avatar uri={item.avatar_url} name={item.full_name} />
          <View style={styles.meta}>
            <Text style={styles.name}>{item.full_name ?? 'Friend'}</Text>
            <TimeAgo value={item.created_at} />
          </View>
          <CategoryBadge label={item.content_category} />
        </Pressable>
        {onNotInterested ? (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Not interested"
            onPress={onNotInterested}
            hitSlop={8}
            style={styles.dismiss}
          >
            <Feather name="eye-off" size={18} color={colors.muted} />
          </Pressable>
        ) : null}
      </View>
      {item.title ? <Text style={styles.title}>{item.title}</Text> : null}
      {item.caption ? <Text style={styles.caption}>{item.caption}</Text> : null}
      {isVideo ? (
        inlineVideoPlayback && videoActive && item.media_url ? (
          <View style={styles.inlineVideo}>
            <VideoMedia
              source={item.media_url}
              posterUrl={item.poster_url}
              active={videoActive}
              height={300}
              nativeControls={false}
              loop
            />
          </View>
        ) : previewUrl ? (
          <Pressable onPress={onOpen} disabled={!onOpen} style={styles.videoPoster}>
            <Image source={{ uri: previewUrl }} style={styles.media} />
            <View style={styles.playBadge} pointerEvents="none">
              <Feather name="play" size={24} color="#FFFFFF" />
            </View>
          </Pressable>
        ) : (
          <Pressable onPress={onOpen} disabled={!onOpen} style={styles.media}>
            <Text style={styles.videoLabel}>Video</Text>
          </Pressable>
        )
      ) : previewUrl ? (
        <Pressable onPress={onOpen} disabled={!onOpen}>
          <Image source={{ uri: previewUrl }} style={styles.media} />
        </Pressable>
      ) : null}
      {socialTarget ? (
        <View style={styles.actions}>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={item.viewer_liked ? 'Unlike post' : 'Like post'}
            onPress={() => void onLike()}
            style={styles.action}
            hitSlop={6}
          >
            <Feather
              name="heart"
              size={21}
              color={item.viewer_liked ? colors.danger : colors.ink}
            />
          </Pressable>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={item.viewer_saved ? 'Unsave post' : 'Save post'}
            onPress={() => void onSave()}
            style={styles.action}
            hitSlop={6}
          >
            <Feather
              name="bookmark"
              size={21}
              color={item.viewer_saved ? colors.brand : colors.ink}
            />
          </Pressable>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Comments"
            onPress={onOpen}
            style={styles.action}
            hitSlop={6}
          >
            <Feather name="message-circle" size={20} color={colors.ink} />
          </Pressable>
          <Text style={styles.likeCount}>{item.likes ?? 0} likes</Text>
          <View style={styles.flex} />
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Share post"
            onPress={onOpen}
            hitSlop={6}
          >
            <Feather name="send" size={19} color={colors.ink} />
          </Pressable>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  card: { backgroundColor: colors.surface, borderBottomWidth: 1, borderBottomColor: colors.line, paddingBottom: spacing.md, marginBottom: spacing.sm },
  row: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  profileRow: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 10 },
  meta: { flex: 1 },
  name: { fontWeight: '800', color: colors.ink },
  title: { marginTop: 8, color: colors.ink, fontSize: type.body, fontWeight: '800' },
  caption: { marginTop: 8, color: colors.ink, fontSize: type.body, lineHeight: 22 },
  media: { marginTop: 10, width: '100%', height: 300, borderRadius: 0, backgroundColor: colors.line },
  videoLabel: { margin: 'auto', color: colors.muted, fontWeight: '700' },
  inlineVideo: { marginTop: 10, width: '100%', height: 300, backgroundColor: colors.ink },
  videoPoster: { position: 'relative' },
  playBadge: { position: 'absolute', left: '50%', top: '50%', marginLeft: -24, marginTop: -24, width: 48, height: 48, borderRadius: 24, backgroundColor: 'rgba(0,0,0,0.55)', alignItems: 'center', justifyContent: 'center' },
  actions: { flexDirection: 'row', alignItems: 'center', gap: 16, marginTop: 8, paddingHorizontal: spacing.md },
  action: { paddingVertical: 5 },
  actionText: { color: colors.brandDark, fontWeight: '700' },
  likeCount: { color: colors.ink, fontSize: type.caption, fontWeight: '700' },
  flex: { flex: 1 },
  dismiss: { padding: 6 },
  icon: { color: colors.ink, fontSize: 24, lineHeight: 24 },
  liked: { color: colors.danger },
});
