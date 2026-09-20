import { useEffect, useRef, useState } from 'react';
import { Image, Keyboard, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { fetchParentEmailStatus, registerParent, resendParentEmail, verifyParentEmail, verifyParentLiveness } from '../api/auth';
import { ApiError } from '../api/client';
import { useAuth } from '../auth/AuthProvider';
import { CameraCapture } from '../camera/CameraCapture';
import type { CapturedPhoto } from '../camera/livePhoto';
import type { AuthScreenProps } from '../navigation/types';
import { Button, Card, Field, GateNotice, GuidelineChips, Notice, Screen, StepIndicator, errorText } from '../ui/components';
import { colors, radius, spacing, type } from '../ui/tokens';

export function ParentRegisterScreen({ navigation }: AuthScreenProps<'ParentRegister'>) {
  const [username, setUsername] = useState('');
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [dob, setDob] = useState('');
  const [guardianAgreed, setGuardianAgreed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [keyboardHeight, setKeyboardHeight] = useState(0);

  const scrollRef = useRef<ScrollView>(null);

  useEffect(() => {
    const showSub = Keyboard.addListener(
      Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow',
      (e) => {
        setKeyboardHeight(e.endCoordinates.height);
      }
    );
    const hideSub = Keyboard.addListener(
      Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide',
      () => {
        setKeyboardHeight(0);
      }
    );
    return () => {
      showSub.remove();
      hideSub.remove();
    };
  }, []);

  const scrollToInput = (offsetY: number) => {
    setTimeout(() => {
      scrollRef.current?.scrollTo({ y: offsetY, animated: true });
    }, 120);
  };

  async function submit() {
    if (!guardianAgreed) {
      setError('You must certify that you are the legal adult guardian.');
      return;
    }
    setBusy(true);
    setError('');
    try {
      const response = await registerParent({
        username: username.trim(),
        full_name: fullName.trim(),
        email: email.trim(),
        password,
        dob: dob.trim(),
      });
      navigation.navigate('OtpVerify', {
        pendingToken: response.pending_token,
        emailSent: response.email_sent,
        // A release client never consumes an OTP returned by an API, even if a
        // server is accidentally misconfigured. Explicit dev builds retain the
        // local-only escape hatch for isolated testing.
        devCode: __DEV__ ? response.dev_code : undefined,
      });
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Screen>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 64 : 0}
        style={styles.keyboardContainer}
      >
        <ScrollView
          ref={scrollRef}
          style={styles.scroll}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="on-drag"
          automaticallyAdjustKeyboardInsets={Platform.OS === 'ios'}
          contentContainerStyle={[
            styles.scrollContent,
            { paddingBottom: keyboardHeight > 0 ? keyboardHeight + 40 : spacing.xl },
          ]}
          showsVerticalScrollIndicator={true}
          nestedScrollEnabled={true}
          bounces={true}
        >
          <View style={styles.headerHero}>
            <View style={styles.heroLogoBadge}>
              <Image
                source={require('../../assets/app_logo.png')}
                style={styles.heroLogo}
                resizeMode="cover"
              />
            </View>
            <Text style={styles.heroBrandName}>LittleNet</Text>
            <Text style={styles.heroSubtitle}>Create your verified parent account to supervise safely</Text>
          </View>

          <Card>
            <StepIndicator step={1} total={3} label="Guardian Details" />

            <Field
              label="Full Name"
              placeholder="e.g. Dr. Ramesh Kumar"
              value={fullName}
              onChangeText={setFullName}
              onFocus={() => scrollToInput(20)}
            />
            <Field
              label="Parent Username"
              placeholder="e.g. dad_ramesh"
              autoCapitalize="none"
              autoCorrect={false}
              helper="3–30 letters, numbers, _ or ."
              value={username}
              onChangeText={setUsername}
              onFocus={() => scrollToInput(75)}
            />
            <Field
              label="Email Address"
              placeholder="parent@example.com"
              autoCapitalize="none"
              autoCorrect={false}
              keyboardType="email-address"
              value={email}
              onChangeText={setEmail}
              onFocus={() => scrollToInput(135)}
            />
            <Field
              label="Date of Birth (YYYY-MM-DD)"
              placeholder="1990-05-14"
              helper="You must be at least 18 years old. Server validates age."
              value={dob}
              onChangeText={setDob}
              onFocus={() => scrollToInput(195)}
            />
            <Field
              label="Password"
              placeholder="Minimum 8 characters"
              secureTextEntry={!showPassword}
              value={password}
              onChangeText={setPassword}
              onFocus={() => scrollToInput(265)}
              rightAction={
                <Pressable onPress={() => setShowPassword((prev) => !prev)} hitSlop={8}>
                  <Text style={styles.pwdToggle}>{showPassword ? 'Hide' : 'Show'}</Text>
                </Pressable>
              }
            />

            <Pressable
              accessibilityRole="checkbox"
              accessibilityState={{ checked: guardianAgreed }}
              onPress={() => setGuardianAgreed((prev) => !prev)}
              style={styles.guardianCheckboxRow}
            >
              <View style={[styles.checkboxBox, guardianAgreed && styles.checkboxBoxChecked]}>
                {guardianAgreed ? <Feather name="check" size={13} color="#FFFFFF" strokeWidth={3} /> : null}
              </View>
              <Text style={styles.guardianCheckboxLabel}>
                I certify that I am the legal adult parent or guardian responsible for child safety and supervision.
              </Text>
            </Pressable>

            <View style={styles.flowInfoBox}>
              <Feather name="info" size={16} color="#0284C7" />
              <Text style={styles.flowInfoText}>
                Next: LittleNet sends a 6-digit email code, followed by a quick adult selfie check.
              </Text>
            </View>

            {error ? <Notice message={error} /> : null}

            <Button label={busy ? 'Creating Account…' : 'Create Account →'} onPress={submit} loading={busy} disabled={busy} />

            <View style={styles.signupBox}>
              <Text style={styles.signupMuted}>Already registered?</Text>
              <Pressable onPress={() => navigation.navigate('Login')} hitSlop={6}>
                <Text style={styles.signupLinkText}>Log In as Parent →</Text>
              </Pressable>
            </View>
          </Card>
        </ScrollView>
      </KeyboardAvoidingView>
    </Screen>
  );
}

export function OtpVerifyScreen({ navigation, route }: AuthScreenProps<'OtpVerify'>) {
  const { pendingToken, devCode } = route.params;
  const [otp, setOtp] = useState(devCode || '');
  const [busy, setBusy] = useState(false);
  const [resending, setResending] = useState(false);
  const [error, setError] = useState('');
  const [info, setInfo] = useState(
    devCode
      ? `Verification code: ${devCode} (expires in 10 minutes)`
      : route.params.emailSent === false
      ? 'Email delivery may be slow. You can resend the code below.'
      : ''
  );

  useEffect(() => {
    if (devCode) return undefined;

    let cancelled = false;
    const checkDelivery = async () => {
      try {
        const response = await fetchParentEmailStatus(pendingToken);
        if (cancelled) return;

        if (response.delivery_failed) {
          const message =
            response.status === 'SUPPRESSED'
              ? 'This email address is suppressed after an earlier delivery problem. Check the address or use a different email.'
              : response.status === 'BOUNCED'
                ? 'The email provider rejected this address. Check that the mailbox exists and use a valid email.'
                : 'The verification email could not be delivered. Check the address and try again.';
          setError(message);
          setInfo('');
          return;
        }

        if (response.status === 'DELIVERED') {
          setError('');
          setInfo('Verification email delivered. Enter the 6-digit code from your inbox.');
        } else if (response.status === 'DELIVERY_DELAYED') {
          setInfo('Your email provider reports a delivery delay. You can wait or resend the code.');
        }
      } catch {
        // Delivery telemetry is advisory; OTP entry and resend must keep working
        // even if the status endpoint is temporarily unavailable.
      }
    };

    void checkDelivery();
    const timer = setInterval(() => void checkDelivery(), 4000);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [devCode, pendingToken]);

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
      if (__DEV__ && response.dev_code) {
        setOtp(response.dev_code);
        setInfo(`Verification code: ${response.dev_code} (expires in 10 minutes)`);
      } else {
        setInfo(response.ok ? 'A fresh code is on its way. It expires in 10 minutes.' : (response.error ?? 'Resend failed. Try again.'));
      }
    } catch (err) {
      setError(errorText(err));
    } finally {
      setResending(false);
    }
  }

  const [keyboardHeight, setKeyboardHeight] = useState(0);
  const scrollRef = useRef<ScrollView>(null);

  useEffect(() => {
    const showSub = Keyboard.addListener(
      Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow',
      (e) => {
        setKeyboardHeight(e.endCoordinates.height);
      }
    );
    const hideSub = Keyboard.addListener(
      Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide',
      () => {
        setKeyboardHeight(0);
      }
    );
    return () => {
      showSub.remove();
      hideSub.remove();
    };
  }, []);

  return (
    <Screen>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 64 : 0}
        style={styles.keyboardContainer}
      >
        <ScrollView
          ref={scrollRef}
          style={styles.scroll}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="on-drag"
          automaticallyAdjustKeyboardInsets={Platform.OS === 'ios'}
          contentContainerStyle={[
            styles.scrollContent,
            { paddingBottom: keyboardHeight > 0 ? keyboardHeight + 40 : spacing.xl },
          ]}
          showsVerticalScrollIndicator={true}
          nestedScrollEnabled={true}
          bounces={true}
        >
          <View style={styles.headerHero}>
            <View style={styles.heroLogoBadge}>
              <Image
                source={require('../../assets/app_logo.png')}
                style={styles.heroLogo}
                resizeMode="cover"
              />
            </View>
            <Text style={styles.heroBrandName}>LittleNet</Text>
            <Text style={styles.heroSubtitle}>We sent a 6-digit verification code to your email</Text>
          </View>

          <Card>
            <StepIndicator step={2} total={3} label="Email Verification" />

            <View style={styles.otpFieldWrap}>
              <Text style={styles.otpLabel}>6-DIGIT VERIFICATION CODE</Text>
              <Field
                label=""
                keyboardType="number-pad"
                maxLength={6}
                value={otp}
                onChangeText={setOtp}
                onFocus={() => {
                  setTimeout(() => scrollRef.current?.scrollTo({ y: 60, animated: true }), 100);
                }}
                placeholder="000000"
                style={styles.otpInput}
              />
              <Text style={styles.otpHelperText}>The code expires in 10 minutes and is single-use.</Text>
            </View>

            {error ? <Notice message={error} /> : null}
            {info ? <Notice tone="info" message={info} /> : null}

            <Button label={busy ? 'Verifying…' : 'Verify Email →'} onPress={submit} loading={busy} disabled={busy} />
            <Button label={resending ? 'Resending Code…' : 'Resend Verification Code'} variant="secondary" onPress={resend} disabled={resending} />

            <View style={styles.flowInfoBox}>
              <Feather name="shield" size={16} color="#0284C7" />
              <Text style={styles.flowInfoText}>
                Your account activates after email ownership and adult liveness are verified.
              </Text>
            </View>
          </Card>
        </ScrollView>
      </KeyboardAvoidingView>
    </Screen>
  );
}

export function GuardianLivenessScreen({ route }: AuthScreenProps<'GuardianLiveness'>) {
  const { signIn } = useAuth();
  const { pendingToken } = route.params;
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);

  async function onCapture(photo: CapturedPhoto) {
    setBusy(true);
    setError(null);
    try {
      const response = await verifyParentLiveness(pendingToken, photo.base64);
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
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={true}
        bounces={true}
      >
        <View style={styles.headerHero}>
          <View style={styles.heroLogoBadge}>
            <Image
              source={require('../../assets/app_logo.png')}
              style={styles.heroLogo}
              resizeMode="cover"
            />
          </View>
          <Text style={styles.heroBrandName}>LittleNet</Text>
          <Text style={styles.heroSubtitle}>Adult verification • Live selfie check</Text>
        </View>

        <Card>
          <StepIndicator step={3} total={3} label="Adult Check" />

          <GuidelineChips
            chips={[
              { iconName: 'sun', text: 'Good Light' },
              { iconName: 'user', text: 'Center Face' },
              { iconName: 'shield', text: 'Live Camera' },
            ]}
          />

          <Notice
            tone="info"
            message="Good light, look straight at the camera, one adult face only. The photo is checked for safety and discarded."
          />

          {error ? <GateNotice error={error} /> : null}
          {error instanceof ApiError && error.status === 503 ? (
            <Notice tone="info" message="The verification service is busy. Wait a moment and retry — your email step is saved." />
          ) : null}

          <CameraCapture label="Take Live Selfie" busyLabel="Checking…" busy={busy} onCapture={onCapture} />
        </Card>
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  keyboardContainer: { flex: 1 },
  scroll: { flex: 1 },
  scrollContent: { paddingBottom: spacing.xl },
  headerHero: { alignItems: 'center', paddingTop: spacing.md, paddingBottom: spacing.sm, paddingHorizontal: spacing.lg },
  heroLogoBadge: {
    width: 58,
    height: 58,
    borderRadius: 16,
    shadowColor: '#0095F6',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.22,
    shadowRadius: 10,
    elevation: 4,
    marginBottom: 4,
  },
  heroLogo: { width: 58, height: 58, borderRadius: 16 },
  heroBrandName: { color: colors.ink, fontSize: 24, fontWeight: '900', letterSpacing: -0.5, marginTop: 4 },
  heroSubtitle: { color: colors.muted, fontSize: 13, textAlign: 'center', marginTop: 3, lineHeight: 18, maxWidth: 320 },
  pwdToggle: { fontSize: 12, fontWeight: '700', color: colors.brand },
  guardianCheckboxRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 10,
    marginTop: spacing.md,
    backgroundColor: '#F8FAFC',
    borderWidth: 1,
    borderColor: '#E2E8F0',
    borderRadius: 12,
    padding: 12,
  },
  checkboxBox: {
    width: 20,
    height: 20,
    borderRadius: 5,
    borderWidth: 1.5,
    borderColor: '#CBD5E1',
    backgroundColor: '#FFFFFF',
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 2,
  },
  checkboxBoxChecked: {
    backgroundColor: colors.brand,
    borderColor: colors.brand,
  },
  checkmarkText: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '900',
  },
  guardianCheckboxLabel: {
    flex: 1,
    fontSize: 12,
    lineHeight: 18,
    color: '#475569',
    fontWeight: '500',
  },
  flowInfoBox: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: '#F0F9FF',
    borderWidth: 1,
    borderColor: '#BAE6FD',
    borderRadius: 12,
    padding: 10,
    marginTop: spacing.md,
  },
  flowInfoIcon: { fontSize: 14 },
  flowInfoText: { flex: 1, fontSize: 12, color: '#0369A1', lineHeight: 17, fontWeight: '500' },
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
  signupMuted: { fontSize: 13, color: colors.muted },
  signupLinkText: { fontSize: 13, fontWeight: '700', color: colors.brand },
  otpFieldWrap: { marginTop: spacing.sm },
  otpLabel: { fontSize: 11, fontWeight: '800', color: colors.muted, letterSpacing: 0.8, textAlign: 'center', marginBottom: 6 },
  otpInput: {
    letterSpacing: 10,
    fontSize: 26,
    fontWeight: '800',
    textAlign: 'center',
    paddingVertical: 14,
    backgroundColor: '#FFFFFF',
    borderColor: '#BFDBFE',
    borderWidth: 1.5,
    color: colors.ink,
  },
  otpHelperText: { fontSize: 11, color: colors.muted, textAlign: 'center', marginTop: 6 },
});
