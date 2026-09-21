import { useState } from 'react';
import { Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { enrollChildFace, faceLogin, requestFaceChallenge, skipChildFaceEnroll, type FaceChallengeResponse } from '../api/auth';
import { ApiError } from '../api/client';
import { useAuth } from '../auth/AuthProvider';
import { CameraCapture } from '../camera/CameraCapture';
import type { CapturedPhoto } from '../camera/livePhoto';
import { precheckFaceChallenge } from '../camera/facePrecheck';
import type { AuthScreenProps, ChildScreenProps } from '../navigation/types';
import { Button, Card, Field, GateNotice, GuidelineChips, Notice, Screen, errorText } from '../ui/components';
import { colors, radius, spacing, type } from '../ui/tokens';

/**
 * Normalize every face-login failure into a user-facing message that reveals
 * nothing about the account.
 *
 * The backend deliberately returns indistinguishable failures for an unknown
 * identifier, a missing face enrollment, and a non-matching face (synthetic
 * challenges for unknown identifiers, uniform `face_login_failed` codes).
 * The client distinguishes these cases internally via status/code/reason for
 * flow decisions, but must never turn those differences into an account or
 * enrollment oracle in the UI.
 */
export function faceLoginFailureMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.status === 0) {
      return 'No internet connection. Reconnect, then retry verification.';
    }
    switch (error.code) {
      case 'face_challenge_expired_or_consumed':
      case 'challenge_expired':
      case 'challenge_already_used_replay_detected':
      case 'invalid_face_challenge':
      case 'face_auth_challenge_required':
      case 'challenge_action_mismatch':
      case 'challenge_nonce_mismatch':
      case 'challenge_not_found':
      case 'missing_challenge_params':
        // The single-use challenge is gone; only a fresh challenge can work.
        return 'This face check expired. Start a fresh face check and try again.';
      case 'network_unreachable':
      case 'server_unavailable':
      case 'request_timeout':
        return 'Verification is temporarily unavailable. Try again in a moment.';
      default:
        break;
    }
    if (error.status >= 500) {
      return 'Verification is temporarily unavailable. Try again in a moment.';
    }
    // 400/401/403/404 from face-login: unknown account, no enrolled face,
    // non-matching face, or rejected liveness all look identical here on
    // purpose — never reveal which one happened.
    return 'Face login did not work. Check the username and try again, or use password login.';
  }
  return errorText(error);
}

/** Replay-resistant kids face login with interactive challenge-response. */
export function FaceLoginScreen({ navigation, route }: AuthScreenProps<'FaceLogin'>) {
  const { signIn } = useAuth();
  // Face login is kids-only. Parent access uses Android device authentication.
  const mode = route.params?.mode ?? 'kids';
  const [identifier, setIdentifier] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [challenge, setChallenge] = useState<FaceChallengeResponse | null>(null);

  async function startChallenge() {
    const trimmed = identifier.trim();
    if (!trimmed) {
      setError(new Error('Enter the child username or email first.'));
      return;
    }
    setBusy(true);
    setError(null);
    try {
      setChallenge(await requestFaceChallenge(trimmed, mode));
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  }

  async function onCapture(photo: CapturedPhoto) {
    const trimmed = identifier.trim();
    if (!trimmed) {
      throw new Error('Enter the child username or email first.');
    }
    setBusy(true);
    setError(null);
    try {
      if (!challenge) throw new Error('Start a fresh face challenge before taking the photo.');
      const response = await faceLogin(trimmed, mode, photo.base64, challenge.challenge_id, challenge.nonce, challenge.action);
      await signIn(response);
    } catch (err) {
      // The server-side challenge is single-use: any failure invalidates it,
      // so the next attempt must start a fresh challenge with a fresh photo.
      setChallenge(null);
      // Normalize before surfacing: the raw ApiError message would reveal
      // whether the account exists or has a face enrolled.
      const normalized =
        err instanceof ApiError
          ? new ApiError(err.status, err.code, faceLoginFailureMessage(err), err.gate, err.details)
          : err;
      setError(normalized);
      throw normalized;
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
            onChangeText={(value) => { setIdentifier(value); setChallenge(null); }}
          />

          {error ? <GateNotice error={error} /> : null}

          {!challenge ? (
            <Button label="Start secure face check" loading={busy} disabled={busy} onPress={() => void startChallenge()} />
          ) : (
            <>
              <Notice
                tone="info"
                message={challenge.action === 'BLINK' ? 'Challenge: close both eyes, then take the photo.' : challenge.action === 'TURN_LEFT' ? 'Challenge: turn your head left, then take the photo.' : 'Challenge: turn your head right, then take the photo.'}
              />
              <CameraCapture
                label="Capture challenge photo"
                busyLabel="Checking Face…"
                busy={busy}
                livenessAction={challenge.action}
                instruction="Google ML Kit will automatically scan your face and detect the challenge action. Photo captures automatically."
                validatePhoto={(photo) => precheckFaceChallenge(photo, challenge.action)}
                onCapture={onCapture}
              />
              <Button label="Get a different challenge" variant="secondary" disabled={busy} onPress={() => void startChallenge()} />
            </>
          )}

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
 * refresh drives the transition (Quiz if required, else KidsTabs). A failed
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

  async function onSkip() {
    if (!session || busy || checking) return;
    setBusy(true);
    setError(null);
    try {
      await skipChildFaceEnroll(session.token);
      setChecking(true);
      try {
        const next = await refreshMe();
        if (next.onboarding?.face_required) {
          setChecking(false);
          setError(new Error('Could not update face setup. Please try again.'));
          return;
        }
      } catch (refreshError) {
        setChecking(false);
        if (refreshError instanceof ApiError && refreshError.status === 401) return;
        setError(refreshError);
        throw refreshError;
      }
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) return;
      setError(err);
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
          {checking ? <Notice tone="ok" message="Face setup updated. Checking what is next…" /> : null}

          <CameraCapture
            label="Save My Face Key"
            busyLabel="Enrolling Face…"
            busy={busy}
            livenessAction="BLINK"
            instruction="Google ML Kit will scan your face and ask you to blink naturally to confirm liveness."
            onCapture={onCapture}
          />

          <View style={styles.skipBox}>
            <Button
              label="Skip for Now"
              variant="secondary"
              disabled={busy || checking}
              onPress={() => void onSkip()}
            />
          </View>
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
  skipBox: {
    marginTop: spacing.md,
    alignItems: 'center',
    width: '100%',
  },
});
