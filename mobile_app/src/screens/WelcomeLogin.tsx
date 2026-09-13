import { useState } from 'react';
import { ScrollView } from 'react-native';
import { login } from '../api/auth';
import type { LoginMode } from '../api/auth';
import { ApiError } from '../api/client';
import { useAuth } from '../auth/AuthProvider';
import { BrandHeader, Button, Card, Field, Notice, Screen, errorText } from '../ui/components';
import type { AuthScreenProps } from '../navigation/types';

const MODES: { label: string; value: LoginMode }[] = [
  { label: 'Kids', value: 'kids' },
  { label: 'Parent', value: 'parent' },
  { label: 'Admin', value: 'admin' },
];

export function WelcomeScreen({ navigation }: AuthScreenProps<'Welcome'>) {
  return (
    <Screen>
      <BrandHeader title="Safe, fun, and made for kids" subtitle="Parents verify first. Kids play, learn, and share safely." />
      <Card>
        <Button label="Log in" onPress={() => navigation.navigate('Login')} />
        <Button label="Parent sign-up" variant="secondary" onPress={() => navigation.navigate('ParentRegister')} />
        <Button label="Kids face login" variant="secondary" onPress={() => navigation.navigate('FaceLogin')} />
      </Card>
    </Screen>
  );
}

export function LoginScreen({ navigation }: AuthScreenProps<'Login'>) {
  const { signIn } = useAuth();
  const [mode, setMode] = useState<LoginMode>('kids');
  const [identifier, setIdentifier] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function submit() {
    if (!identifier.trim() || !password) {
      setError('Enter your username/email and password.');
      return;
    }
    setBusy(true);
    setError('');
    try {
      const response = await login(identifier.trim(), password, mode);
      await signIn(response);
      // Role-aware routing happens in RootNavigator; parent-verification
      // resume is handled here because login returns the pending token.
    } catch (err) {
      if (err instanceof ApiError && err.code === 'parent_verification_required') {
        const pendingToken = typeof err.details.pending_token === 'string' ? err.details.pending_token : '';
        navigation.navigate('OtpVerify', { pendingToken });
        return;
      }
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Screen>
      <ScrollView>
        <BrandHeader title="Log in" subtitle="Kids, parents, and admins each use their own login." />
        <Card>
          {MODES.map((item) => (
            <Button key={item.value} label={`${mode === item.value ? '✓ ' : ''}${item.label}`} variant={mode === item.value ? 'primary' : 'secondary'} onPress={() => setMode(item.value)} />
          ))}
          <Field label="Username or email" autoCapitalize="none" autoCorrect={false} value={identifier} onChangeText={setIdentifier} />
          <Field label="Password" secureTextEntry value={password} onChangeText={setPassword} />
          {error ? <Notice message={error} /> : null}
          <Button label={busy ? 'Logging in…' : 'Log in'} onPress={submit} loading={busy} disabled={busy} />
          <Button label="I forgot my password" variant="secondary" onPress={() => navigation.navigate('Welcome')} />
        </Card>
      </ScrollView>
    </Screen>
  );
}
