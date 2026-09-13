import { useState } from 'react';
import { Image, ScrollView, StyleSheet, Text, View } from 'react-native';
import { completeUpload, requestUploadSession } from '../../api/kidsUpload';
import { useAuth } from '../../auth/AuthProvider';
import { putFileToSignedUrl } from '../../kids/directUpload';
import { capturePostMedia, localMediaSize, pickGalleryMedia, validateMediaIdentity, type PickedMedia } from '../../kids/postMedia';
import type { ChildScreenProps } from '../../navigation/types';
import { BrandHeader, Button, Card, Field, GateNotice, Notice, Screen } from '../../ui/components';
import { colors } from '../../ui/tokens';

type Kind = 'post' | 'reel' | 'story';

export function CreateScreen({ navigation }: ChildScreenProps<'KidsTabs'>) {
  const { session } = useAuth();
  const [kind, setKind] = useState<Kind>('post');
  const [media, setMedia] = useState<PickedMedia | null>(null);
  const [caption, setCaption] = useState('');
  const [tags, setTags] = useState('');
  const [location, setLocation] = useState('');
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState('');
  const [error, setError] = useState<unknown>(null);
  const nav = navigation as unknown as { navigate: (r: string, p: object) => void };

  async function choose(fn: () => Promise<PickedMedia | null>) {
    try {
      const picked = await fn();
      if (picked) {
        setMedia(picked);
        setError(null);
      }
    } catch (err) {
      setError(err);
    }
  }

  async function publish() {
    if (!session || !media) return;
    setBusy(true);
    setError(null);
    try {
      const mediaType = media.mimeType.startsWith('video/') ? 'VIDEO' : 'IMAGE';
      validateMediaIdentity(media.fileName, media.mimeType);
      const sizeBytes = localMediaSize(media.uri);
      setStatus('Requesting a safe upload…');
      const sess = await requestUploadSession(session.token, {
        kind, filename: media.fileName, mediaType,
        sizeBytes, mimeType: media.mimeType,
      });
      setStatus('Uploading directly…');
      await putFileToSignedUrl(sess.upload_url, media.uri, sess.required_headers);
      setStatus('Finishing safely…');
      const done = await completeUpload(session.token, sess.upload_id, {
        caption: caption.trim(), contentCategory: 'Other',
        tags: tags.split(',').map((t) => t.trim()).filter(Boolean),
        locationName: location.trim(),
      });
      nav.navigate('ProcessingStatus', { postId: done.post_id });
    } catch (err) {
      setError(err);
      setStatus('');
    } finally {
      setBusy(false);
    }
  }

  return (
    <Screen>
      <ScrollView>
        <BrandHeader title="Create" subtitle="Share something kind." />
        {error ? <GateNotice error={error} /> : null}
        {status ? <Notice tone="info" message={status} /> : null}
        <Card>
          <View style={styles.kinds}>
            {(['post', 'reel', 'story'] as Kind[]).map((k) => (
              <Button key={k} label={k} variant={kind === k ? 'primary' : 'secondary'} onPress={() => setKind(k)} />
            ))}
          </View>
          <View style={styles.row}>
            <Button label="Gallery photo" variant="secondary" onPress={() => void choose(() => pickGalleryMedia('image'))} />
            <Button label="Camera photo" variant="secondary" onPress={() => void choose(() => capturePostMedia('image'))} />
          </View>
          <View style={styles.row}>
            <Button label="Gallery video" variant="secondary" onPress={() => void choose(() => pickGalleryMedia('video'))} />
            <Button label="Camera video" variant="secondary" onPress={() => void choose(() => capturePostMedia('video'))} />
          </View>
          {media ? <Text style={styles.file}>{media.fileName}</Text> : null}
          {media && media.mimeType.startsWith('image/') ? <Image source={{ uri: media.uri }} style={styles.preview} /> : null}
        </Card>
        <Card>
          <Field label="Caption" value={caption} onChangeText={setCaption} multiline placeholder="Write a kind caption…" />
          <Field label="Tags (comma separated)" value={tags} onChangeText={setTags} placeholder="art, school" />
          <Field label="Location label (optional text only)" value={location} onChangeText={setLocation} placeholder="Bengaluru" />
          <Button label={busy ? 'Publishing…' : 'Share safely'} disabled={busy || !media} onPress={() => void publish()} />
        </Card>
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  kinds: { flexDirection: 'row', gap: 8 },
  row: { flexDirection: 'row', gap: 8, marginTop: 8 },
  file: { marginTop: 8, color: colors.ink },
  preview: { marginTop: 8, width: '100%', height: 220, borderRadius: 12, backgroundColor: colors.line },
});
