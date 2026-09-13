import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { ChildScreenProps } from '../../navigation/types';
import { BrandHeader, Screen } from '../../ui/components';
import { colors } from '../../ui/tokens';

const TABS = [
  { key: 'FeedTab', label: 'Home' },
  { key: 'DiscoverTab', label: 'Discover' },
  { key: 'CreateTab', label: 'Create' },
  { key: 'ReelsTab', label: 'Reels' },
  { key: 'ProfileTab', label: 'Profile' },
] as const;

export function KidsTabsShell({ navigation, route, render }: ChildScreenProps<'KidsTabs'> & { render: (tab: string) => React.ReactNode }) {
  const active = String((route.params as { tab?: string } | undefined)?.tab ?? 'FeedTab');
  const nav = navigation as unknown as { navigate: (r: string, p: object) => void };
  return (
    <Screen>
      <BrandHeader title="LittleNet" subtitle="A kind place to share and learn." />
      <View style={styles.top}>
        <Pressable onPress={() => nav.navigate('Stories', {})}><Text style={styles.link}>Stories</Text></Pressable>
        <Pressable onPress={() => nav.navigate('NotificationsTab', {})}><Text style={styles.link}>Notifications</Text></Pressable>
        <Pressable onPress={() => nav.navigate('Conversations', {})}><Text style={styles.link}>Messages</Text></Pressable>
      </View>
      <View style={styles.body}>{render(active)}</View>
      <View style={styles.tabs}>
        {TABS.map((t) => (
          <Pressable key={t.key} onPress={() => nav.navigate('KidsTabs', { tab: t.key })} style={[styles.tab, active === t.key && styles.on]}>
            <Text style={styles.tabText}>{t.label}</Text>
          </Pressable>
        ))}
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  top: { flexDirection: 'row', gap: 16, marginBottom: 8 },
  link: { color: colors.brandDark, fontWeight: '700' },
  body: { flex: 1 },
  tabs: { flexDirection: 'row', borderTopWidth: 1, borderTopColor: colors.line, paddingTop: 8 },
  tab: { flex: 1, alignItems: 'center', paddingVertical: 8 },
  on: { backgroundColor: '#FFF1E8', borderRadius: 10 },
  tabText: { fontWeight: '700', color: colors.ink },
});
