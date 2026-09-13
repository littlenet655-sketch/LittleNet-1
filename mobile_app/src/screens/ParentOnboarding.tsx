import { useState } from 'react';
import { ScrollView } from 'react-native';
import { registerParent, resendParentEmail, verifyParentEmail, verifyParentLiveness } from '../api/auth';
import { ApiError } from '../api/client';
import { useAuth } from '../auth/AuthProvider';
import { captureLivePhoto } from '../camera/livePhoto';
import type { AuthScreenProps } from '../navigation/types';
import { BrandHeader, Button, Card, Field, GateNotice, Notice, Screen, errorText } from '../ui/components';

export function ParentRegisterScreen({ navigation }: AuthScreenProps<'ParentRegister'>) {
  const [username, setUsername] = useState('');
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [dob, setDob] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function submit() {
    setBusy(true);
    setError('');
    try {
      const response = await registerParent({ username: username.trim(), full_name: fullName.trim(), email: email.trim(), password, dob: dob.trim() });
      navigation.navigate('OtpVerify', { pendingToken: response.pending_token, emailSent: response.email_sent });
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Screen>
      <ScrollView>
        <BrandHeader title="Parent sign-up" subtitle="Step 1 of 3: create your guardian account. A 6-digit email code comes next." />
        <Card>
          <Field label="Username (3–30 letters, numbers, _ or .)" autoCapitalize="none" autoCorrect={false} value={username} onChangeText={setUsername} />
          <Field label="Full name" value={fullName} onChangeText={setFullName} />
          <Field label="Email" autoCapitalize="none" autoCorrect={false} keyboardType="email-address" value={email} onChangeText={setEmail} />
          <Field label="Password (min 8 characters)" secureTextEntry value={password} onChangeText={setPassword} />
          <Field label="Date of birth (YYYY-MM-DD, 18+)" placeholder="1990-05-14" value={dob} onChangeText={setDob} />
          <Notice tone="info" message="By continuing you confirm you are the child's adult guardian." />
          {error ? <Notice message={error} /> : null}
          <Button label={busy ? 'Creating…' : 'Create account'} onPress={submit} loading={busy} disabled={busy} />
        </Card>
      </ScrollView>
    </Screen>
  );
}

export function OtpVerifyScreen({ navigation, route }: AuthScreenProps<'OtpVerify'>) {
  const { pendingToken } = route.params;
  const [otp, setOtp] = useState('');
  const [busy, setBusy] = useState(false);
  const [resending, setResending] = useState(false);
  const [error, setError] = useState('');
  const [info, setInfo] = useState(route.params.emailSent === false ? 'Email delivery may be slow. You can resend the code below.' : '');

  async function submit() {
    if (otp.trim().length !== 6) {
      setError('Enter the 6-digit code from your email.');
      return;
    }
    setBusy(true);
    setError('');
    try {
      const response = await verifyParentEmail(pendingToken, otp.trim());
      navigation.navigate('GuardianLiveness', { pendingToken: response.pending_token });
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  async function resend() {
    setResending(true);
    setError('');
    try {
      const response = await resendParentEmail(pendingToken);
      setInfo(response.ok ? 'A fresh code is on its way. It expires in 10 minutes.' : (response.error ?? 'Resend failed. Try again.'));
    } catch (err) {
      setError(errorText(err));
    } finally {
      setResending(false);
    }
  }

  return (
    <Screen>
      <ScrollView>
        <BrandHeader title="Check your email" subtitle="Step 2 of 3: enter the 6-digit code. It expires in 10 minutes." />
        <Card>
          <Field label="6-digit code" keyboardType="number-pad" maxLength={6} value={otp} onChangeText={setOtp} />
          {error ? <Notice message={error} /> : null}
          {info ? <Notice tone="info" message={info} /> : null}
          <Button label={busy ? 'Verifying…' : 'Verify email'} onPress={submit} loading={busy} disabled={busy} />
          <Button label={resending ? 'Resending…' : 'Resend code'} variant="secondary" onPress={resend} disabled={resending} />
        </Card>
      </ScrollView>
    </Screen>
  );
}

export function GuardianLivenessScreen({ route }: AuthScreenProps<'GuardianLiveness'>) {
  const { signIn } = useAuth();
  const { pendingToken } = route.params;
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);

  async function submit() {
    setBusy(true);
    setError(null);
    try {
      const photo = await captureLivePhoto();
      const response = await verifyParentLiveness(pendingToken, photo.base64);
      await signIn(response);
      // RootNavigator routes the now-ACTIVE parent to ParentStack.
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Screen>
      <ScrollView>
        <BrandHeader title="Adult check" subtitle="Step 3 of 3: take a live selfie. An adult guardian must complete this step." />
        <Card>
          <Notice tone="info" message="Good light, look at the camera, one face only. The photo is used for this check and then discarded." />
          {error ? <GateNotice error={error} /> : null}
          {error instanceof ApiError && error.status === 503 ? (
            <Notice tone="info" message="The verification service is busy. Wait a moment and retry — your email step is saved." />
          ) : null}
          <Button label={busy ? 'Checking…' : 'Take live selfie'} onPress={submit} loading={busy} disabled={busy} />
        </Card>
      </ScrollView>
    </Screen>
  );
}
