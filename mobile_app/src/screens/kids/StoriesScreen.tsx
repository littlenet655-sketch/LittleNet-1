import { useEffect, useState } from 'react';
import { Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { fetchKidsHome, type StoryItem } from '../../api/kidsFeed';
import { useAuth } from '../../auth/AuthProvider';
import { VideoMedia } from '../../kids/VideoMedia';
import type { ChildScreenProps } from '../../navigation/types';
import { Avatar } from '../../ui/social';
import { Button, EmptyState, ErrorState, LoadingState, Screen } from '../../ui/components';
import { colors, radius, spacing } from '../../ui/tokens';

/** Stories tray + viewer. Seen tracking is a documented limitation (no mobile seen route). */
export function StoriesScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const { session } = useAuth();
  const [stories, setStories] = useState<StoryItem[]>([]);
  const [index, setIndex] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<unknown>(null);

  useEffect(() => {
    (async () => {
      if (!session) return;
      try {
        const home = await fetchKidsHome(session.token);
        setStories(home.stories ?? []);
      } catch (err) {
        setError(err);
      } finally {
        setLoading(false);
      }
    })();
  }, [session]);

  if (loading) return <Screen><LoadingState message="Loading stories…" /></Screen>;
  if (error) return <Screen><ErrorState message="Could not load stories." onRetry={() => (navigation as unknown as { goBack: () => void }).goBack()} /></Screen>;
  if (!stories.length) return <Screen><EmptyState title="No stories" body="New stories from friends will appear here." /></Screen>;

  const current = stories[Math.min(index, stories.length - 1)]!;
  const media = current.media_url ?? '';
  const isVideo = current.media_type?.toUpperCase() === 'VIDEO';
  return (
    <Screen>
      <Text style={styles.heading}>Stories</Text>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.tray}>
        {stories.map((s, i) => (
          <Pressable key={String(s.post_id ?? i)} onPress={() => setIndex(i)} style={[styles.ring, i === index && styles.active]}>
             <View style={styles.ringOuter}><View style={styles.ringInner}><Avatar uri={s.avatar_url} name={s.full_name ?? 'F'} size={52} /></View></View>
          </Pressable>
        ))}
      </ScrollView>
      <View style={styles.viewer}>
        {media && isVideo ? <VideoMedia key={current.post_id} source={media} posterUrl={current.poster_url} /> : null}
        {media && !isVideo ? <Image source={{ uri: media }} style={styles.media} /> : null}
        {!media ? <Text style={styles.caption}>This story has no media.</Text> : null}
        {current.caption ? <Text style={styles.caption}>{current.caption}</Text> : null}
      </View>
      <View style={styles.row}>
        <Button label="Previous" variant="secondary" onPress={() => setIndex((i) => Math.max(0, i - 1))} />
        <Button label="Next" variant="secondary" onPress={() => setIndex((i) => Math.min(stories.length - 1, i + 1))} />
      </View>
      <Text style={styles.note}>Story views are not tracked on mobile yet.</Text>
    </Screen>
  );
}

const styles = StyleSheet.create({
  heading: { fontSize: 20, fontWeight: '700', color: colors.ink, paddingHorizontal: spacing.md, marginBottom: spacing.sm },
  tray: { maxHeight: 78, paddingHorizontal: spacing.md },
  ring: { marginRight: 12, opacity: 0.7 },
  ringOuter: { padding: 2, borderRadius: 31, backgroundColor: '#DD2A7B' },
  ringInner: { padding: 2, borderRadius: 29, backgroundColor: colors.surface },
  active: { opacity: 1 },
  viewer: { marginTop: spacing.md, alignItems: 'center', backgroundColor: colors.ink },
  media: { width: '100%', height: 500, borderRadius: 0, backgroundColor: colors.line },
  caption: { marginTop: 8, color: colors.ink },
  row: { flexDirection: 'row', gap: 10, marginTop: 10 },
  note: { marginTop: 8, color: colors.muted, textAlign: 'center' },
});
