import { useEffect, useRef, useState } from 'react';
import { Image, Pressable, StyleSheet, Text, View, useWindowDimensions } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { fetchKidsHome, recordStoryView, type StoryItem } from '../../api/kidsFeed';
import { useAuth } from '../../auth/AuthProvider';
import { VideoMedia } from '../../kids/VideoMedia';
import type { ChildScreenProps } from '../../navigation/types';
import { Avatar } from '../../ui/social';
import { Button, EmptyState, ErrorState, LoadingState, Screen } from '../../ui/components';
import { colors, spacing } from '../../ui/tokens';

const IMAGE_DURATION = 5000;

/** Full-screen story viewer. Stories are already filtered by the server's public-safety rules. */
export function StoriesScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const { session } = useAuth();
  const { height } = useWindowDimensions();
  const focused = useIsFocused();
  const [stories, setStories] = useState<StoryItem[]>([]);
  const [index, setIndex] = useState(0);
  const [paused, setPaused] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<unknown>(null);
  const mounted = useRef(true);


  async function load() {
    if (!session) return;
    setLoading(true);
    setError(null);
    try {
      const home = await fetchKidsHome(session.token);
      if (mounted.current) setStories(home.stories ?? []);
    } catch (err) {
      if (mounted.current) setError(err);
    } finally {
      if (mounted.current) setLoading(false);
    }
  }

  useEffect(() => {
    mounted.current = true;
    void load();
    return () => { mounted.current = false; };
  }, [session]);

  const current = stories[index];
  const isVideo = current?.media_type?.toUpperCase() === 'VIDEO';

  useEffect(() => {
    setPaused(false);
    if (session?.token && current?.post_id) {
      void recordStoryView(session.token, current.post_id, 1.0).catch(() => {});
    }
  }, [index, current?.post_id, session?.token]);

  useEffect(() => {
    if (!current || isVideo || !stories.length || paused || !focused) return;
    const timer = setTimeout(() => setIndex((value) => value < stories.length - 1 ? value + 1 : 0), IMAGE_DURATION);
    return () => clearTimeout(timer);
  }, [index, current?.post_id, isVideo, stories.length, paused, focused]);

  if (loading) return <Screen><LoadingState message="Loading stories…" /></Screen>;
  if (error) return <Screen><ErrorState message="Could not load stories." onRetry={() => void load()} /></Screen>;
  if (!current) return <Screen><EmptyState title="No stories" body="New stories from friends will appear here." /><Button label="Create a story" onPress={() => navigation.navigate('CreateTab')} /></Screen>;

  const next = () => setIndex((value) => Math.min(stories.length - 1, value + 1));
  const previous = () => setIndex((value) => Math.max(0, value - 1));
  return (
    <Screen>
      <View style={[styles.viewer, { height }]}>
        <View style={styles.top}>
          <View style={styles.progressRow}>
            {stories.map((story, storyIndex) => <View key={story.post_id} style={styles.progressTrack}>
              <View style={[styles.progress, storyIndex < index && styles.complete, storyIndex === index && !paused && styles.current]} />
            </View>)}
          </View>
          <View style={styles.identity}>
            <Avatar uri={current.avatar_url} name={current.full_name ?? 'Friend'} size={34} />
            <Text style={styles.name}>{current.full_name ?? 'Friend'}</Text>
            <Pressable onPress={() => navigation.navigate('CreateTab')} style={styles.create}><Text style={styles.createText}>＋ Story</Text></Pressable>
          </View>
        </View>
        <View style={styles.media}>
          {current.media_url && isVideo ? <VideoMedia key={current.post_id} source={current.media_url} posterUrl={current.poster_url} active={!paused && focused} height={height} /> : null}
          {current.media_url && !isVideo ? <Image source={{ uri: current.media_url }} style={styles.image} resizeMode="cover" /> : null}
          {!current.media_url ? <Text style={styles.missing}>This story has no media.</Text> : null}
          <Pressable accessibilityLabel="Previous story" onPress={previous} style={styles.leftTap} />
          <Pressable accessibilityLabel={paused ? 'Resume story' : 'Pause story'} onPress={() => setPaused((value) => !value)} style={styles.centerTap} />
          <Pressable accessibilityLabel="Next story" onPress={next} style={styles.rightTap} />
          {paused ? <View pointerEvents="none" style={styles.pause}><Text style={styles.pauseText}>Ⅱ</Text><Text style={styles.pauseLabel}>Paused</Text></View> : null}
          {current.caption ? <Text style={styles.caption}>{current.caption}</Text> : null}
        </View>
        <View style={styles.controls}>
          <Button label="Back" variant="secondary" disabled={index === 0} onPress={previous} />
          <Button label={paused ? 'Resume' : 'Pause'} variant="secondary" onPress={() => setPaused((value) => !value)} />
          <Button label={index === stories.length - 1 ? 'Restart' : 'Next'} onPress={() => index === stories.length - 1 ? setIndex(0) : next()} />
        </View>
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  viewer: { backgroundColor: colors.ink },
  top: { position: 'absolute', zIndex: 3, top: spacing.md, left: spacing.md, right: spacing.md },
  progressRow: { flexDirection: 'row', gap: 4 },
  progressTrack: { flex: 1, height: 3, backgroundColor: 'rgba(255,255,255,0.35)', overflow: 'hidden' },
  progress: { width: 0, height: '100%', backgroundColor: colors.surface },
  complete: { width: '100%' },
  current: { width: '100%' },
  identity: { flexDirection: 'row', alignItems: 'center', gap: 9, marginTop: spacing.sm },
  name: { color: colors.surface, fontWeight: '800', flex: 1 },
  create: { padding: 7 },
  createText: { color: colors.surface, fontWeight: '800' },
  media: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  image: { width: '100%', height: '100%' },
  missing: { color: colors.surface, fontWeight: '700' },
  leftTap: { position: 'absolute', left: 0, top: 0, bottom: 0, width: '28%' },
  centerTap: { position: 'absolute', left: '28%', right: '28%', top: 0, bottom: 0 },
  rightTap: { position: 'absolute', right: 0, top: 0, bottom: 0, width: '28%' },
  pause: { position: 'absolute', alignItems: 'center' },
  pauseText: { color: colors.surface, fontSize: 42, fontWeight: '800' },
  pauseLabel: { color: colors.surface, fontWeight: '800' },
  caption: { position: 'absolute', bottom: spacing.lg + 50, left: spacing.md, right: spacing.md, color: colors.surface, fontSize: 16, fontWeight: '700' },
  controls: { flexDirection: 'row', gap: 8, padding: spacing.md },
});