import { useState } from 'react';
import { Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { enrollChildFace, faceLogin } from '../api/auth';
import { ApiError } from '../api/client';
import { useAuth } from '../auth/AuthProvider';
import { CameraCapture } from '../camera/CameraCapture';
import type { CapturedPhoto } from '../camera/livePhoto';
import type { AuthScreenProps, ChildScreenProps } from '../navigation/types';
import { Button, Card, Field, GateNotice, GuidelineChips, Notice, Screen, errorText } from '../ui/components';
import { colors, radius, spacing, type } from '../ui/tokens';

/** Face-first login. Password remains only as the backend-permitted fallback. */
export function FaceLoginScreen({ navigation }: AuthScreenProps<'FaceLogin'>) {
  const { signIn } = useAuth();
  const [identifier, setIdentifier] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);

  async function onCapture(photo: CapturedPhoto) {
    if (!identifier.trim()) {
      throw new Error('Enter the child username or email first.');
    }
    setBusy(true);
    setError(null);
    try {
      const response = await faceLogin(identifier.trim(), 'kids', photo.base64);
      await signIn(response);
    } catch (err) {
      setError(err);
      throw err;
    } finally {
      setBusy(false);
    }
  }

  return (
    <Screen>
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={styles.scrollContent}>
        <View style={styles.headerHero}>
          <View style={styles.heroLogoBadge}>
            <Image
              source={require('../../assets/app_logo.png')}
              style={styles.heroLogo}
              resizeMode="cover"
            />
          </View>
          <Text style={styles.heroBrandName}>LittleNet</Text>
          <Text style={styles.heroSubtitle}>Kids Face ID Login • Look at the camera</Text>
        </View>

        <Card>
          <GuidelineChips
            chips={[
              { iconName: 'sun', text: 'Good Light' },
              { iconName: 'user', text: 'Center Face' },
              { iconName: 'shield', text: 'Live Camera' },
            ]}
          />

          <Field
            label="Child Username or Email"
            placeholder="e.g. alex_star or child@example.com"
            autoCapitalize="none"
            autoCorrect={false}
            value={identifier}
            onChangeText={setIdentifier}
          />

          {error ? <GateNotice error={error} /> : null}

          <CameraCapture label="Scan & Verify Face ID" busyLabel="Checking Face…" busy={busy} onCapture={onCapture} />

          <View style={styles.signupBox}>
            <Pressable onPress={() => navigation.navigate('Login')} hitSlop={8} style={styles.switchAuthButton}>
              <Feather name="arrow-left" size={14} color={colors.brand} />
              <Text style={styles.signupLinkText}>Use password login instead</Text>
            </Pressable>
          </View>
        </Card>
      </ScrollView>
    </Screen>
  );
}

/**
 * Mandatory child face enrollment gate. After success the authoritative /me
 * refresh drives the transition (Quiz if required, else KidsHome). A failed
 * attempt or failed refresh keeps the child gated with retry.
 */
export function FaceEnrollScreen(_props: ChildScreenProps<'FaceEnroll'>) {
  const { session, refreshMe } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [checking, setChecking] = useState(false);

  async function onCapture(photo: CapturedPhoto) {
    if (!session) return;
    setBusy(true);
    setChecking(false);
    setError(null);
    try {
      await enrollChildFace(session.token, photo.base64);
      setChecking(true);
      try {
        const next = await refreshMe();
        if (next.onboarding?.face_required) {
          setChecking(false);
          setError(new Error('Face enrollment is not confirmed yet. Please retake the photo.'));
          return;
        }
        // GateSync transitions automatically once onboarding updates.
      } catch (refreshError) {
        setChecking(false);
        if (refreshError instanceof ApiError && refreshError.status === 401) return;
        setError(refreshError);
        throw refreshError;
      }
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) return;
      setError(err);
      throw err;
    } finally {
      setBusy(false);
    }
  }

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.scrollContent}>
        <View style={styles.headerHero}>
          <View style={styles.heroLogoBadge}>
            <Image
              source={require('../../assets/app_logo.png')}
              style={styles.heroLogo}
              resizeMode="cover"
            />
          </View>
          <Text style={styles.heroBrandName}>LittleNet</Text>
          <Text style={styles.heroSubtitle}>Set up your face key for instant biometric login</Text>
        </View>

        <Card>
          <GuidelineChips
            chips={[
              { iconName: 'sun', text: 'Bright Room' },
              { iconName: 'eye', text: 'Look Straight' },
              { iconName: 'user', text: 'Just You' },
            ]}
          />

          <Notice tone="info" message="Good light, look straight at the camera, one face only. Spoof photos and groups are rejected." />
          {error ? <GateNotice error={error} /> : null}
          {checking ? <Notice tone="ok" message="Face enrolled. Checking what is next…" /> : null}

          <CameraCapture label="Save My Face Key" busyLabel="Enrolling Face…" busy={busy} onCapture={onCapture} />
        </Card>
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  scrollContent: { paddingBottom: spacing.xl },
  headerHero: { alignItems: 'center', paddingTop: spacing.lg, paddingBottom: spacing.md, paddingHorizontal: spacing.lg },
  heroLogoBadge: {
    width: 60,
    height: 60,
    borderRadius: 16,
    shadowColor: '#0095F6',
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.26,
    shadowRadius: 14,
    elevation: 5,
    marginBottom: spacing.xs,
  },
  heroLogo: { width: 60, height: 60, borderRadius: 16 },
  heroBrandName: { color: colors.ink, fontSize: 26, fontWeight: '900', letterSpacing: -0.5, marginTop: 4 },
  heroSubtitle: { color: colors.muted, fontSize: 13, textAlign: 'center', marginTop: 4, lineHeight: 18, maxWidth: 300 },
  signupBox: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingTop: 12,
    marginTop: spacing.md,
    borderTopWidth: 1,
    borderTopColor: '#F3F4F6',
    width: '100%',
    justifyContent: 'center',
  },
  switchAuthButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  signupLinkText: {
    fontSize: 13,
    fontWeight: '700',
    color: colors.brand,
  },
});
