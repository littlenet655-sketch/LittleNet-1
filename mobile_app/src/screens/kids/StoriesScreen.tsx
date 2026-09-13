import { useEffect, useState } from 'react';
import { Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { fetchKidsHome } from '../../api/kidsFeed';
import { useAuth } from '../../auth/AuthProvider';
import type { ChildScreenProps } from '../../navigation/types';
import { Avatar } from '../../ui/social';
import { Button, EmptyState, ErrorState, LoadingState, Screen } from '../../ui/components';
import { colors, radius, spacing } from '../../ui/tokens';

/** Stories tray + viewer. Seen tracking is a documented limitation (no mobile seen route). */
export function StoriesScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const { session } = useAuth();
  const [stories, setStories] = useState<Array<Record<string, unknown>>>([]);
  const [index, setIndex] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<unknown>(null);

  useEffect(() => {
    (async () => {
      if (!session) return;
      try {
        const home = await fetchKidsHome(session.token);
        setStories((home.stories as Array<Record<string, unknown>>) ?? []);
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

  const current = stories[Math.min(index, stories.length - 1)] ?? {};
  const media = String(current.media_url ?? '');
  return (
    <Screen>
      <ScrollView horizontal style={styles.tray}>
        {stories.map((s, i) => (
          <Pressable key={String(s.post_id ?? i)} onPress={() => setIndex(i)} style={[styles.ring, i === index && styles.active]}>
            <Avatar uri={typeof s.avatar_url === 'string' ? s.avatar_url : null} name={String(s.full_name ?? 'F')} size={48} />
          </Pressable>
        ))}
      </ScrollView>
      <View style={styles.viewer}>
        {media ? <Image source={{ uri: media }} style={styles.media} /> : <Text style={styles.caption}>{String(current.caption ?? '')}</Text>}
        <Text style={styles.caption}>{String(current.caption ?? '')}</Text>
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
  tray: { maxHeight: 70 },
  ring: { marginRight: 10, opacity: 0.7 },
  active: { opacity: 1, borderWidth: 2, borderColor: colors.brand, borderRadius: 28 },
  viewer: { marginTop: spacing.md, alignItems: 'center' },
  media: { width: '100%', height: 380, borderRadius: radius.lg, backgroundColor: colors.line },
  caption: { marginTop: 8, color: colors.ink },
  row: { flexDirection: 'row', gap: 10, marginTop: 10 },
  note: { marginTop: 8, color: colors.muted, textAlign: 'center' },
});
