import { useState } from 'react';
import { ScrollView } from 'react-native';
import { enrollChildFace, faceLogin } from '../api/auth';
import { ApiError } from '../api/client';
import { useAuth } from '../auth/AuthProvider';
import { captureLivePhoto } from '../camera/livePhoto';
import type { AuthScreenProps, ChildScreenProps } from '../navigation/types';
import { BrandHeader, Button, Card, Field, GateNotice, Notice, Screen, errorText } from '../ui/components';

/** Face-first login. Password remains only as the backend-permitted fallback. */
export function FaceLoginScreen({ navigation }: AuthScreenProps<'FaceLogin'>) {
  const { signIn } = useAuth();
  const [identifier, setIdentifier] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);

  async function submit() {
    if (!identifier.trim()) {
      setError(new Error('Enter the child username or email first.'));
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const photo = await captureLivePhoto();
      const response = await faceLogin(identifier.trim(), 'kids', photo.base64);
      await signIn(response);
    } catch (err) {
      setError(err);
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
          <Button label={busy ? 'Checking face…' : 'Log in with face'} onPress={submit} loading={busy} disabled={busy} />
          <Button label="Use password instead" variant="secondary" onPress={() => navigation.navigate('Login')} />
        </Card>
      </ScrollView>
    </Screen>
  );
}

/** Mandatory child face enrollment gate. A failed attempt never clears the gate. */
export function FaceEnrollScreen(_props: ChildScreenProps<'FaceEnroll'>) {
  const { session, refreshMe } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [done, setDone] = useState(false);

  async function submit() {
    if (!session) return;
    setBusy(true);
    setError(null);
    try {
      const photo = await captureLivePhoto();
      await enrollChildFace(session.token, photo.base64);
      setDone(true);
      await refreshMe();
      // RootNavigator re-reads server state and moves the child to the quiz gate.
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        // Centralized handler already signed out; keep local gate intact.
      }
      setError(err);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Screen>
      <ScrollView>
        <BrandHeader title="Set up face login" subtitle="One live photo enrolls this device-free Kids account. Required before anything else." />
        <Card>
          <Notice tone="info" message="Good light, look at the camera, one face only. Spoof photos and groups are rejected." />
          {error ? <GateNotice error={error} /> : null}
          {done ? <Notice tone="ok" message="Face enrolled. Checking what is next…" /> : null}
          <Button label={busy ? 'Enrolling…' : 'Take enrollment photo'} onPress={submit} loading={busy} disabled={busy} />
        </Card>
      </ScrollView>
    </Screen>
  );
}
