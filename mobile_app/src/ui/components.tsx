import type { ReactNode } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import type { TextInputProps } from 'react-native';
import { ApiError } from '../api/client';
import { colors, radius, spacing, type } from './tokens';

export function Screen({ children }: { children: ReactNode }) {
  return <View style={styles.screen}>{children}</View>;
}

export function Card({ children }: { children: ReactNode }) {
  return <View style={styles.card}>{children}</View>;
}

export function BrandHeader({ title, subtitle }: { title: string; subtitle?: string }) {
  return (
    <View style={styles.header}>
      <Text style={styles.brand}>LittleNet</Text>
      <Text style={styles.title}>{title}</Text>
      {subtitle ? <Text style={styles.subtitle}>{subtitle}</Text> : null}
    </View>
  );
}

interface ButtonProps {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  loading?: boolean;
  variant?: 'primary' | 'secondary';
}

export function Button({ label, onPress, disabled, loading, variant = 'primary' }: ButtonProps) {
  const isDisabled = disabled || loading;
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      disabled={isDisabled}
      style={[styles.button, variant === 'secondary' && styles.buttonSecondary, isDisabled && styles.buttonDisabled]}
    >
      {loading ? <ActivityIndicator color="#fff" /> : <Text style={[styles.buttonText, variant === 'secondary' && styles.buttonTextSecondary]}>{label}</Text>}
    </Pressable>
  );
}

interface FieldProps extends TextInputProps {
  label: string;
  error?: string;
}

export function Field({ label, error, ...rest }: FieldProps) {
  return (
    <View style={styles.field}>
      <Text style={styles.label}>{label}</Text>
      <TextInput
        placeholderTextColor={colors.muted}
        style={[styles.input, error ? styles.inputError : null]}
        {...rest}
      />
      {error ? <Text style={styles.fieldError}>{error}</Text> : null}
    </View>
  );
}

export function Notice({ message, tone = 'error' }: { message: string; tone?: 'error' | 'info' | 'ok' }) {
  if (!message) return null;
  return (
    <View style={[styles.notice, tone === 'info' && styles.noticeInfo, tone === 'ok' && styles.noticeOk]}>
      <Text style={styles.noticeText}>{message}</Text>
    </View>
  );
}

export function errorText(error: unknown, fallback = 'Something went wrong. Please try again.'): string {
  if (error instanceof ApiError) return error.message;
  if (error instanceof Error && error.message) return error.message;
  return fallback;
}

/** Explicit UX for backend gates: 401/403/423/428/503. */
export function GateNotice({ error }: { error: unknown }) {
  if (!(error instanceof ApiError)) return <Notice message={errorText(error)} />;
  const gateLabel =
    error.gate === 'face'
      ? 'Face step needed'
      : error.gate === 'quiz'
        ? 'Quiz needed'
        : error.gate === 'quiet_hours'
          ? 'Quiet hours'
          : error.gate === 'screen_time'
            ? 'Screen-time limit'
            : error.gate === 'parent_verification'
              ? 'Parent verification'
              : error.gate === 'email_verification'
                ? 'Email check'
                : `Code ${error.status}`;
  return (
    <View style={styles.notice}>
      <Text style={styles.gateLabel}>{gateLabel}</Text>
      <Text style={styles.noticeText}>{error.message}</Text>
    </View>
  );
}

export function LoadingState({ message = 'Loading…' }: { message?: string }) {
  return (
    <View style={styles.center}>
      <ActivityIndicator size="large" color={colors.brand} />
      <Text style={styles.centerText}>{message}</Text>
    </View>
  );
}

export function EmptyState({ title, body }: { title: string; body?: string }) {
  return (
    <View style={styles.center}>
      <Text style={styles.emptyTitle}>{title}</Text>
      {body ? <Text style={styles.centerText}>{body}</Text> : null}
    </View>
  );
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <View style={styles.center}>
      <Text style={styles.emptyTitle}>Something needs attention</Text>
      <Text style={styles.centerText}>{message}</Text>
      {onRetry ? <Button label="Try again" onPress={onRetry} variant="secondary" /> : null}
    </View>
  );
}

export function OfflineBanner({ online }: { online: boolean }) {
  if (online) return null;
  return (
    <View style={styles.offline}>
      <Text style={styles.offlineText}>You are offline. Changes will wait until you reconnect.</Text>
    </View>
  );
}

/** Shown when parent controls disable a feature instead of broken navigation. */
export function DisabledFeature({ feature }: { feature: string }) {
  return (
    <View style={styles.center}>
      <Text style={styles.emptyTitle}>{feature} is off</Text>
      <Text style={styles.centerText}>Your parent turned this off in controls. Ask them to enable it.</Text>
    </View>
  );
}

export function Skeleton({ lines = 3 }: { lines?: number }) {
  return (
    <View style={styles.skeletonWrap}>
      {Array.from({ length: lines }).map((_, index) => (
        <View key={index} style={styles.skeletonLine} />
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background },
  card: { backgroundColor: colors.surface, borderRadius: radius.md, padding: spacing.lg, borderWidth: 1, borderColor: colors.line, marginHorizontal: spacing.md, marginBottom: spacing.md },
  header: { paddingHorizontal: spacing.md, paddingTop: spacing.md, paddingBottom: spacing.sm, marginBottom: spacing.sm },
  brand: { fontSize: 24, fontWeight: '800', color: colors.ink, letterSpacing: -1 },
  title: { fontSize: type.hero, fontWeight: '800', color: colors.ink, marginTop: 4 },
  subtitle: { fontSize: type.subtitle, color: colors.muted, marginTop: 6, lineHeight: 24 },
  button: { backgroundColor: colors.brand, borderRadius: radius.md, minHeight: 36, paddingHorizontal: spacing.lg, paddingVertical: 8, alignItems: 'center', justifyContent: 'center', marginTop: spacing.sm },
  buttonSecondary: { backgroundColor: '#EFEFEF', borderWidth: 1, borderColor: colors.line },
  buttonDisabled: { opacity: 0.55 },
  buttonText: { color: '#fff', fontWeight: '700', fontSize: type.body },
  buttonTextSecondary: { color: colors.ink },
  field: { marginTop: spacing.sm },
  label: { fontSize: type.caption, fontWeight: '700', color: colors.ink, marginBottom: 4 },
  input: { backgroundColor: '#EFEFEF', borderWidth: 1, borderColor: 'transparent', borderRadius: radius.md, paddingHorizontal: 12, paddingVertical: 10, fontSize: type.body, color: colors.ink },
  inputError: { borderColor: colors.danger },
  fieldError: { color: colors.danger, fontSize: type.caption, marginTop: 4 },
  notice: { backgroundColor: '#FDECEC', borderRadius: radius.md, padding: spacing.sm, marginTop: spacing.sm },
  noticeInfo: { backgroundColor: '#E6F7F7' },
  noticeOk: { backgroundColor: '#E7F6EC' },
  noticeText: { color: colors.ink, fontSize: type.body, lineHeight: 21 },
  gateLabel: { fontWeight: '800', fontSize: type.caption, color: colors.danger, marginBottom: 2, textTransform: 'uppercase', letterSpacing: 1 },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: spacing.lg, gap: 8 },
  centerText: { color: colors.muted, fontSize: type.body, textAlign: 'center', lineHeight: 22 },
  emptyTitle: { fontSize: type.title, fontWeight: '800', color: colors.ink, textAlign: 'center' },
  offline: { backgroundColor: colors.ink, borderRadius: radius.md, padding: spacing.sm, marginBottom: spacing.sm },
  offlineText: { color: '#fff', textAlign: 'center', fontSize: type.caption },
  skeletonWrap: { gap: 8, marginTop: spacing.sm },
  skeletonLine: { height: 16, borderRadius: 8, backgroundColor: colors.line },
});
