import { Image, Pressable, StyleSheet, Text, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import type { ChildScreenProps } from '../../navigation/types';
import { Screen } from '../../ui/components';
import { colors } from '../../ui/tokens';

const TABS: {
  key: string;
  label: string;
  icon: keyof typeof Feather.glyphMap;
}[] = [
  { key: 'FeedTab', label: 'Home', icon: 'home' },
  { key: 'DiscoverTab', label: 'Search', icon: 'search' },
  { key: 'CreateTab', label: 'Create', icon: 'plus-circle' },
  { key: 'ReelsTab', label: 'Reels', icon: 'film' },
  { key: 'ProfileTab', label: 'Profile', icon: 'user' },
];

export function KidsTabsShell({ navigation, route, render }: ChildScreenProps<'KidsTabs'> & { render: (tab: string) => React.ReactNode }) {
  const active = String((route.params as { tab?: string } | undefined)?.tab ?? 'FeedTab');
  const nav = navigation as unknown as { navigate: (r: string, p: object) => void };
  return (
    <Screen>
      <View style={styles.top}>
        <View style={styles.brandRow}>
          <Image
            source={require('../../../assets/app_logo.png')}
            style={styles.topLogo}
            resizeMode="cover"
          />
          <Text style={styles.wordmark}>LittleNet</Text>
        </View>
        <View style={styles.utilities}>
          <Pressable accessibilityRole="button" accessibilityLabel="Stories" onPress={() => nav.navigate('Stories', {})} hitSlop={8}>
            <Feather name="heart" size={21} color={colors.ink} />
          </Pressable>
          <Pressable accessibilityRole="button" accessibilityLabel="Notifications" onPress={() => nav.navigate('NotificationsTab', {})} hitSlop={8}>
            <Feather name="bell" size={21} color={colors.ink} />
          </Pressable>
          <Pressable accessibilityRole="button" accessibilityLabel="Messages" onPress={() => nav.navigate('Conversations', {})} hitSlop={8}>
            <Feather name="send" size={20} color={colors.ink} />
          </Pressable>
        </View>
      </View>
      <View style={styles.body}>{render(active)}</View>
      <View style={styles.tabs}>
        {TABS.map((t) => {
          const isOn = active === t.key;
          return (
            <Pressable
              key={t.key}
              accessibilityRole="tab"
              accessibilityState={{ selected: isOn }}
              accessibilityLabel={t.label}
              onPress={() => nav.navigate('KidsTabs', { tab: t.key })}
              style={[styles.tab, isOn && styles.on]}
            >
              <Feather
                name={t.icon}
                size={t.key === 'CreateTab' ? 24 : 22}
                color={isOn ? colors.brand : colors.muted}
              />
            </Pressable>
          );
        })}
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  top: { height: 50, paddingHorizontal: 16, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', backgroundColor: colors.surface, borderBottomWidth: 1, borderBottomColor: '#F0F0F0' },
  brandRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  topLogo: { width: 28, height: 28, borderRadius: 7 },
  wordmark: { color: colors.ink, fontSize: 22, fontWeight: '900', letterSpacing: -0.5 },
  utilities: { flexDirection: 'row', alignItems: 'center', gap: 18 },
  body: { flex: 1 },
  tabs: { flexDirection: 'row', height: 54, backgroundColor: colors.surface, borderTopWidth: 1, borderTopColor: '#F0F0F0', paddingTop: 5 },
  tab: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  on: { backgroundColor: colors.surface },
});
