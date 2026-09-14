import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { ChildScreenProps } from '../../navigation/types';
import { Screen } from '../../ui/components';
import { colors } from '../../ui/tokens';

const TABS = [
  { key: 'FeedTab', label: 'Home', icon: 'home-outline', activeIcon: 'home' },
  { key: 'DiscoverTab', label: 'Search', icon: 'search-outline', activeIcon: 'search' },
  { key: 'CreateTab', label: 'Create', icon: 'add-circle-outline', activeIcon: 'add-circle' },
  { key: 'ReelsTab', label: 'Reels', icon: 'play-circle-outline', activeIcon: 'play-circle' },
  { key: 'ProfileTab', label: 'Profile', icon: 'person-circle-outline', activeIcon: 'person-circle' },
] as const;

export function KidsTabsShell({ navigation, route, render }: ChildScreenProps<'KidsTabs'> & { render: (tab: string) => React.ReactNode }) {
  const active = String((route.params as { tab?: string } | undefined)?.tab ?? 'FeedTab');
  const nav = navigation as unknown as { navigate: (r: string, p: object) => void };
  return (
    <Screen>
      <View style={styles.top}>
        <Text style={styles.wordmark}>LittleNet⌄</Text>
        <View style={styles.utilities}>
          <Pressable onPress={() => nav.navigate('Stories', {})}><Text style={styles.utility}>♡</Text></Pressable>
          <Pressable onPress={() => nav.navigate('NotificationsTab', {})}><Text style={styles.utility}>○</Text></Pressable>
          <Pressable onPress={() => nav.navigate('Conversations', {})}><Text style={styles.utility}>↗</Text></Pressable>
        </View>
      </View>
      <View style={styles.body}>{render(active)}</View>
      <View style={styles.tabs}>
        {TABS.map((t) => (
          <Pressable key={t.key} onPress={() => nav.navigate('KidsTabs', { tab: t.key })} style={[styles.tab, active === t.key && styles.on]}>
            <Text style={[styles.tabIcon, active === t.key && styles.tabIconActive]}>{t.key === 'FeedTab' ? '⌂' : t.key === 'DiscoverTab' ? '⌕' : t.key === 'CreateTab' ? '+' : t.key === 'ReelsTab' ? '▣' : '○'}</Text>
          </Pressable>
        ))}
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  top: { height: 48, paddingHorizontal: 16, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', backgroundColor: colors.surface, borderBottomWidth: 1, borderBottomColor: colors.line },
  wordmark: { color: colors.ink, fontSize: 22, fontWeight: '800', letterSpacing: -1 },
  utilities: { flexDirection: 'row', alignItems: 'center', gap: 18 },
  utility: { color: colors.ink, fontSize: 25, lineHeight: 26 },
  body: { flex: 1 },
  tabs: { flexDirection: 'row', height: 54, backgroundColor: colors.surface, borderTopWidth: 1, borderTopColor: colors.line, paddingTop: 5 },
  tab: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  on: { backgroundColor: colors.surface },
  tabIcon: { color: colors.muted, fontSize: 24, lineHeight: 25 },
  tabIconActive: { color: colors.ink, fontWeight: '700' },
});
