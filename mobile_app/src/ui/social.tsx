import { Image, StyleSheet, Text, View } from 'react-native';
import { colors, radius, spacing, type } from './tokens';

export function Avatar({ uri, name, size = 36 }: { uri?: string | null; name?: string | null; size?: number }) {
  if (uri) return <Image source={{ uri }} style={[styles.avatar, { width: size, height: size, borderRadius: size / 2 }]} />;
  const initial = (name ?? 'L').trim().charAt(0).toUpperCase() || 'L';
  return (
    <View style={[styles.fallback, { width: size, height: size, borderRadius: size / 2 }]}>
      <Text style={styles.initial}>{initial}</Text>
    </View>
  );
}

export function TimeAgo({ value }: { value?: string }) {
  if (!value) return null;
  const t = Date.parse(value);
  const label = Number.isNaN(t) ? '' : shortAgo(Date.now() - t);
  if (!label) return null;
  return <Text style={styles.time}>{label}</Text>;
}

export function shortAgo(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  return `${Math.floor(h / 24)}d`;
}

export function CategoryBadge({ label }: { label?: string }) {
  if (!label) return null;
  return (
    <View style={styles.badge}>
      <Text style={styles.badgeText}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  avatar: { backgroundColor: colors.line },
  fallback: { backgroundColor: colors.sunny, alignItems: 'center', justifyContent: 'center' },
  initial: { fontWeight: '800', color: colors.ink, fontSize: type.body },
  time: { color: colors.muted, fontSize: type.caption },
  badge: { backgroundColor: '#E6F7F7', borderRadius: radius.pill, paddingHorizontal: spacing.sm, paddingVertical: 3, alignSelf: 'flex-start' },
  badgeText: { color: colors.teal, fontSize: type.caption, fontWeight: '700' },
});
