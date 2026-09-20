import { useState } from 'react';
import { ActivityIndicator, Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { completeUpload, requestUploadSession } from '../../api/kidsUpload';
import { useAuth } from '../../auth/AuthProvider';
import { putFileToSignedUrl } from '../../kids/directUpload';
import { capturePostMedia, localMediaSize, pickGalleryMedia, validateMediaIdentity, type PickedMedia } from '../../kids/postMedia';
import type { ChildScreenProps } from '../../navigation/types';
import { Card, Field, GateNotice, Notice } from '../../ui/components';
import { colors, radius, spacing } from '../../ui/tokens';

type Kind = 'post' | 'reel' | 'story';

const SUGGESTED_TAGS = ['art', 'fun', 'learning', 'nature', 'friends', 'school'];

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

  function addTag(tag: string) {
    const list = tags.split(',').map((t) => t.trim()).filter(Boolean);
    if (!list.includes(tag)) {
      setTags([...list, tag].join(', '));
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
      setStatus('Preparing safe upload…');
      const sess = await requestUploadSession(session.token, {
        kind,
        filename: media.fileName,
        mediaType,
        sizeBytes,
        mimeType: media.mimeType,
      });
      setStatus('Uploading content securely…');
      await putFileToSignedUrl(sess.upload_url, media.uri, sess.required_headers);
      setStatus('LittleNet AI safety check…');
      const done = await completeUpload(session.token, sess.upload_id, {
        caption: caption.trim(),
        contentCategory: kind === 'reel' ? 'Fun' : 'Other',
        tags: tags.split(',').map((t) => t.trim()).filter(Boolean),
        locationName: location.trim(),
      });
      nav.navigate('ProcessingStatus', { postId: done.post_id });
    } catch (err) {
      setError(err);
      setStatus('Upload paused. Your selected file and details are still here—tap Share Safely to retry.');
    } finally {
      setBusy(false);
    }
  }

  const isVideo = kind === 'reel';

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
      {/* Mode Switcher */}
      <View style={styles.kindSelector}>
        {(['post', 'reel', 'story'] as Kind[]).map((k) => {
          const active = kind === k;
          const label = k === 'post' ? 'Photo Post' : k === 'reel' ? 'Short Reel' : 'Daily Story';
          const icon = k === 'post' ? 'image' : k === 'reel' ? 'film' : 'zap';
          return (
            <Pressable
              key={k}
              onPress={() => {
                setKind(k);
                setMedia(null);
              }}
              style={[styles.kindBtn, active && styles.kindBtnActive]}
            >
              <Feather name={icon} size={14} color={active ? '#FFFFFF' : '#64748B'} />
              <Text style={[styles.kindText, active && styles.kindTextActive]}>{label}</Text>
            </Pressable>
          );
        })}
      </View>

      {error ? <GateNotice error={error} /> : null}
      {status ? <Notice tone="info" message={status} /> : null}

      {/* Media Picker / Preview */}
      {!media ? (
        <Card style={styles.pickerCard}>
          <Text style={styles.sectionHeading}>
            {isVideo ? 'Choose or record a video' : 'Choose or snap a photo'}
          </Text>
          <View style={styles.pickRow}>
            {isVideo ? (
              <>
                <Pressable
                  style={styles.pickOption}
                  onPress={() => void choose(() => pickGalleryMedia('video'))}
                >
                  <View style={[styles.pickIconCircle, { backgroundColor: '#EFF6FF' }]}>
                    <Feather name="film" size={24} color={colors.brand} />
                  </View>
                  <Text style={styles.pickOptionTitle}>Gallery Video</Text>
                  <Text style={styles.pickOptionSub}>Choose from files</Text>
                </Pressable>
                <Pressable
                  style={styles.pickOption}
                  onPress={() => void choose(() => capturePostMedia('video'))}
                >
                  <View style={[styles.pickIconCircle, { backgroundColor: '#FDF2F8' }]}>
                    <Feather name="video" size={24} color="#DB2777" />
                  </View>
                  <Text style={styles.pickOptionTitle}>Camera Video</Text>
                  <Text style={styles.pickOptionSub}>Record right now</Text>
                </Pressable>
              </>
            ) : (
              <>
                <Pressable
                  style={styles.pickOption}
                  onPress={() => void choose(() => pickGalleryMedia('image'))}
                >
                  <View style={[styles.pickIconCircle, { backgroundColor: '#EFF6FF' }]}>
                    <Feather name="image" size={24} color={colors.brand} />
                  </View>
                  <Text style={styles.pickOptionTitle}>Choose Photo</Text>
                  <Text style={styles.pickOptionSub}>From your gallery</Text>
                </Pressable>
                <Pressable
                  style={styles.pickOption}
                  onPress={() => void choose(() => capturePostMedia('image'))}
                >
                  <View style={[styles.pickIconCircle, { backgroundColor: '#ECFDF5' }]}>
                    <Feather name="camera" size={24} color="#10B981" />
                  </View>
                  <Text style={styles.pickOptionTitle}>Take Photo</Text>
                  <Text style={styles.pickOptionSub}>Snap with camera</Text>
                </Pressable>
              </>
            )}
          </View>
        </Card>
      ) : (
        <Card style={styles.previewCard}>
          {media.mimeType.startsWith('image/') ? (
            <Image source={{ uri: media.uri }} style={styles.previewImg} resizeMode="cover" />
          ) : (
            <View style={styles.videoPlaceholder}>
              <Feather name="film" size={36} color="#FFFFFF" />
              <Text style={styles.videoName}>{media.fileName}</Text>
            </View>
          )}
          <View style={styles.previewBottom}>
            <View style={styles.fileInfo}>
              <Feather name="check-circle" size={14} color="#10B981" />
              <Text style={styles.fileText} numberOfLines={1}>{media.fileName}</Text>
            </View>
            <Pressable onPress={() => setMedia(null)} style={styles.changeBtn}>
              <Text style={styles.changeBtnText}>Change</Text>
            </Pressable>
          </View>
        </Card>
      )}

      {/* Post Details */}
      <Card>
        <Field
          label="Caption"
          value={caption}
          onChangeText={setCaption}
          multiline
          placeholder="Write a kind caption, joke, or fact…"
        />

        {/* Suggested Quick Tags */}
        <View style={styles.tagSection}>
          <Text style={styles.tagLabel}>QUICK TAGS</Text>
          <View style={styles.tagRow}>
            {SUGGESTED_TAGS.map((t) => (
              <Pressable key={t} onPress={() => addTag(t)} style={styles.tagChip}>
                <Text style={styles.tagChipText}>#{t}</Text>
              </Pressable>
            ))}
          </View>
        </View>

        <Field
          label="Tags"
          value={tags}
          onChangeText={setTags}
          placeholder="art, school, reading"
        />

        <Field
          label="Location (optional)"
          value={location}
          onChangeText={setLocation}
          placeholder="Home, School, Art Class"
        />
      </Card>

      {/* Safety Notice Card */}
      <View style={styles.safetyBox}>
        <Feather name="shield" size={16} color="#10B981" />
        <Text style={styles.safetyText}>
          LittleNet AI automatically checks every upload for child safety before sharing.
        </Text>
      </View>

      {/* Submit Button */}
      <Pressable
        onPress={() => void publish()}
        disabled={busy || !media}
        style={[styles.publishBtn, (busy || !media) && styles.publishBtnDisabled]}
      >
        {busy ? (
          <ActivityIndicator size="small" color="#FFFFFF" />
        ) : (
          <Feather name="send" size={18} color="#FFFFFF" />
        )}
        <Text style={styles.publishBtnText}>
          {busy ? 'Sharing Safely…' : 'Share Safely ✨'}
        </Text>
      </Pressable>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scrollContent: {
    padding: 16,
    paddingBottom: 40,
  },
  kindSelector: {
    flexDirection: 'row',
    backgroundColor: colors.surface,
    padding: 4,
    borderRadius: 14,
    marginBottom: 14,
    gap: 6,
    borderWidth: 1,
    borderColor: '#F0F0F0',
  },
  kindBtn: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingVertical: 9,
    borderRadius: 10,
  },
  kindBtnActive: {
    backgroundColor: colors.brand,
  },
  kindText: {
    fontSize: 13,
    fontWeight: '700',
    color: '#64748B',
  },
  kindTextActive: {
    color: '#FFFFFF',
  },
  pickerCard: {
    padding: 16,
    marginBottom: 14,
  },
  sectionHeading: {
    fontSize: 14,
    fontWeight: '800',
    color: colors.ink,
    marginBottom: 12,
  },
  pickRow: {
    flexDirection: 'row',
    gap: 12,
  },
  pickOption: {
    flex: 1,
    alignItems: 'center',
    paddingVertical: 18,
    paddingHorizontal: 10,
    backgroundColor: '#F8FAFC',
    borderRadius: 14,
    borderWidth: 1.5,
    borderColor: '#E2E8F0',
    borderStyle: 'dashed',
  },
  pickIconCircle: {
    width: 48,
    height: 48,
    borderRadius: 24,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 8,
  },
  pickOptionTitle: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.ink,
    marginBottom: 2,
  },
  pickOptionSub: {
    fontSize: 11,
    color: colors.muted,
  },
  previewCard: {
    padding: 0,
    overflow: 'hidden',
    marginBottom: 14,
    borderRadius: 16,
  },
  previewImg: {
    width: '100%',
    height: 240,
    backgroundColor: '#F1F5F9',
  },
  videoPlaceholder: {
    width: '100%',
    height: 200,
    backgroundColor: '#0F172A',
    justifyContent: 'center',
    alignItems: 'center',
    gap: 8,
  },
  videoName: {
    color: '#E2E8F0',
    fontSize: 12,
  },
  previewBottom: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 14,
    paddingVertical: 10,
    backgroundColor: colors.surface,
  },
  fileInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    flex: 1,
  },
  fileText: {
    fontSize: 12,
    color: colors.ink,
    fontWeight: '600',
  },
  changeBtn: {
    paddingHorizontal: 12,
    paddingVertical: 5,
    borderRadius: 12,
    backgroundColor: '#F1F5F9',
  },
  changeBtnText: {
    fontSize: 12,
    fontWeight: '700',
    color: colors.brand,
  },
  tagSection: {
    marginTop: 10,
  },
  tagLabel: {
    fontSize: 10,
    fontWeight: '800',
    color: '#94A3B8',
    letterSpacing: 0.8,
    marginBottom: 6,
  },
  tagRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
  tagChip: {
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
    backgroundColor: '#F1F5F9',
  },
  tagChipText: {
    fontSize: 11,
    fontWeight: '700',
    color: colors.brand,
  },
  safetyBox: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: '#ECFDF5',
    borderWidth: 1,
    borderColor: '#A7F3D0',
    borderRadius: 12,
    padding: 12,
    marginBottom: 16,
  },
  safetyText: {
    flex: 1,
    fontSize: 12,
    color: '#065F46',
    lineHeight: 16,
    fontWeight: '600',
  },
  publishBtn: {
    backgroundColor: colors.brand,
    borderRadius: 14,
    paddingVertical: 14,
    flexDirection: 'row',
    justifyContent: 'center',
    alignItems: 'center',
    gap: 8,
    shadowColor: colors.brand,
    shadowOffset: { width: 0, height: 3 },
    shadowOpacity: 0.25,
    shadowRadius: 6,
    elevation: 3,
  },
  publishBtnDisabled: {
    opacity: 0.5,
    elevation: 0,
  },
  publishBtnText: {
    color: '#FFFFFF',
    fontSize: 15,
    fontWeight: '800',
  },
});
