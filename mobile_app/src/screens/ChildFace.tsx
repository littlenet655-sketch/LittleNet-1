import { useState } from 'react';
import { ScrollView } from 'react-native';
import { enrollChildFace, faceLogin } from '../api/auth';
import { ApiError } from '../api/client';
import { useAuth } from '../auth/AuthProvider';
import { CameraCapture } from '../camera/CameraCapture';
import type { CapturedPhoto } from '../camera/livePhoto';
import type { AuthScreenProps, ChildScreenProps } from '../navigation/types';
import { BrandHeader, Button, Card, Field, GateNotice, Notice, Screen, errorText } from '../ui/components';

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
      <ScrollView>
        <BrandHeader title="Face login" subtitle="Look at the camera for a fresh liveness check on every login." />
        <Card>
          <Field label="Child username or email" autoCapitalize="none" autoCorrect={false} value={identifier} onChangeText={setIdentifier} />
          {error ? <GateNotice error={error} /> : null}
          <CameraCapture label="Log in with face" busyLabel="Checking face…" busy={busy} onCapture={onCapture} />
          <Button label="Use password instead" variant="secondary" onPress={() => navigation.navigate('Login')} />
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
      <ScrollView>
        <BrandHeader title="Set up face login" subtitle="One live photo enrolls this Kids account. Required before anything else." />
        <Card>
          <Notice tone="info" message="Good light, look at the camera, one face only. Spoof photos and groups are rejected." />
          {error ? <GateNotice error={error} /> : null}
          {checking ? <Notice tone="ok" message="Face enrolled. Checking what is next…" /> : null}
          <CameraCapture label="Take enrollment photo" busyLabel="Enrolling…" busy={busy} onCapture={onCapture} />
        </Card>
      </ScrollView>
    </Screen>
  );
}
