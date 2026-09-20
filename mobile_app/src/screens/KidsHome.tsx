import { Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { useAuth } from '../auth/AuthProvider';
import type { ChildScreenProps } from '../navigation/types';
import { Button, Screen } from '../ui/components';
import { colors, radius, spacing } from '../ui/tokens';

interface HubCardProps {
  icon: keyof typeof Feather.glyphMap;
  title: string;
  subtitle: string;
  badge?: string;
  accentColor: string;
  onPress: () => void;
}

function HubCard({ icon, title, subtitle, badge, accentColor, onPress }: HubCardProps) {
  return (
    <Pressable
      style={({ pressed }) => [
        styles.hubCard,
        { borderLeftColor: accentColor },
        pressed && styles.cardPressed,
      ]}
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={title}
    >
      <View style={[styles.iconContainer, { backgroundColor: `${accentColor}18` }]}>
        <Feather name={icon} size={22} color={accentColor} />
      </View>
      <View style={styles.cardContent}>
        <View style={styles.cardTitleRow}>
          <Text style={styles.cardTitle}>{title}</Text>
          {badge ? (
            <View style={[styles.cardBadge, { backgroundColor: `${accentColor}22` }]}>
              <Text style={[styles.cardBadgeText, { color: accentColor }]}>{badge}</Text>
            </View>
          ) : null}
        </View>
        <Text style={styles.cardSubtitle}>{subtitle}</Text>
      </View>
      <Feather name="chevron-right" size={18} color="#94A3B8" />
    </Pressable>
  );
}

/**
 * Joyful, modern LittleNet Kids Home Dashboard.
 * Gives kids an inspiring starting point to launch their feed, explore content,
 * take quizzes, and see their safety status.
 */
export function KidsHomeScreen({ navigation }: ChildScreenProps<'KidsHome'>) {
  const { session, signOut } = useAuth();
  const rawName = session?.user.full_name || session?.user.username || 'Friend';
  const firstName = rawName.split(' ')[0] ?? 'Friend';

  function openTab(tab: 'FeedTab' | 'DiscoverTab' | 'CreateTab' | 'ReelsTab' | 'ProfileTab') {
    (navigation as unknown as { replace: (r: string, p: object) => void }).replace('KidsTabs', { tab });
  }

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        {/* Hero Header */}
        <View style={styles.heroSection}>
          <View style={styles.logoBadge}>
            <Image
              source={require('../../assets/app_logo.png')}
              style={styles.logoImage}
              resizeMode="cover"
            />
          </View>
          <View style={styles.safePill}>
            <Feather name="shield" size={12} color="#10B981" />
            <Text style={styles.safePillText}>LITTLENET KIDS ZONE</Text>
          </View>
          <Text style={styles.heroGreeting}>Welcome, {firstName}! ✨</Text>
          <Text style={styles.heroSubtitle}>
            A kinder place to learn, share, and connect with your friends.
          </Text>
        </View>

        {/* Safety & Status Highlights */}
        <View style={styles.safetyRow}>
          <View style={styles.safetyBadge}>
            <Feather name="check-circle" size={14} color="#10B981" />
            <Text style={styles.safetyBadgeText}>Face Key Set</Text>
          </View>
          <View style={styles.safetyBadge}>
            <Feather name="cpu" size={14} color="#0095F6" />
            <Text style={styles.safetyBadgeText}>AI Guard Active</Text>
          </View>
          <View style={styles.safetyBadge}>
            <Feather name="lock" size={14} color="#8B5CF6" />
            <Text style={styles.safetyBadgeText}>Parent Supervised</Text>
          </View>
        </View>

        {/* Primary Call to Action */}
        <View style={styles.primaryActionWrap}>
          <Pressable
            style={({ pressed }) => [styles.primaryBanner, pressed && styles.cardPressed]}
            onPress={() => openTab('FeedTab')}
            accessibilityRole="button"
            accessibilityLabel="Open Safe Feed"
          >
            <View style={styles.primaryBannerLeft}>
              <View style={styles.bannerIconBox}>
                <Feather name="compass" size={26} color="#FFFFFF" />
              </View>
              <View>
                <Text style={styles.bannerTitle}>Explore Safe Feed</Text>
                <Text style={styles.bannerSubtitle}>See kind photos & stories from friends</Text>
              </View>
            </View>
            <View style={styles.bannerArrow}>
              <Feather name="arrow-right" size={20} color="#FFFFFF" />
            </View>
          </Pressable>
        </View>

        {/* Action Hub Cards */}
        <View style={styles.sectionHeader}>
          <Text style={styles.sectionTitle}>What do you want to do?</Text>
        </View>

        <View style={styles.cardsList}>
          <HubCard
            icon="home"
            title="My Friends & Feed"
            subtitle="Catch up on safe stories and positive posts"
            accentColor="#0095F6"
            onPress={() => openTab('FeedTab')}
          />
          <HubCard
            icon="search"
            title="Discover & Learn"
            subtitle="Explore science, drawing, animals & facts"
            badge="NEW"
            accentColor="#10B981"
            onPress={() => openTab('DiscoverTab')}
          />
          <HubCard
            icon="plus-circle"
            title="Create Something Fun"
            subtitle="Share an art photo, achievement, or kind note"
            accentColor="#EC4899"
            onPress={() => openTab('CreateTab')}
          />
          <HubCard
            icon="film"
            title="Wholesome Reels"
            subtitle="Watch funny and educational short clips"
            accentColor="#F59E0B"
            onPress={() => openTab('ReelsTab')}
          />
          <HubCard
            icon="award"
            title="Daily Safety Quiz"
            subtitle="Answer safety challenges and earn LittleNet XP"
            badge="EARN XP"
            accentColor="#8B5CF6"
            onPress={() => navigation.navigate('Quiz')}
          />
          <HubCard
            icon="user"
            title="My Profile & Badges"
            subtitle="View your shared posts, avatar, and achievements"
            accentColor="#6366F1"
            onPress={() => openTab('ProfileTab')}
          />
        </View>

        {/* Footer Account & Logout */}
        <View style={styles.footerSection}>
          <Text style={styles.footerUserText}>Logged in as @{session?.user.username}</Text>
          <Button
            label="Log out of LittleNet"
            variant="secondary"
            onPress={() => void signOut()}
          />
        </View>
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  scrollContent: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.xl * 1.5,
  },
  heroSection: {
    alignItems: 'center',
    paddingTop: spacing.lg,
    paddingBottom: spacing.md,
  },
  logoBadge: {
    width: 68,
    height: 68,
    borderRadius: 20,
    backgroundColor: '#FFFFFF',
    shadowColor: '#0095F6',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.22,
    shadowRadius: 16,
    elevation: 6,
    marginBottom: spacing.sm,
    alignItems: 'center',
    justifyContent: 'center',
  },
  logoImage: {
    width: 68,
    height: 68,
    borderRadius: 20,
  },
  safePill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    backgroundColor: '#DCFCE7',
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderRadius: radius.pill,
    marginBottom: spacing.xs,
  },
  safePillText: {
    color: '#15803D',
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.6,
  },
  heroGreeting: {
    fontSize: 24,
    fontWeight: '900',
    color: colors.ink,
    letterSpacing: -0.5,
    textAlign: 'center',
    marginTop: 2,
  },
  heroSubtitle: {
    fontSize: 13,
    color: colors.muted,
    textAlign: 'center',
    marginTop: 4,
    lineHeight: 18,
    maxWidth: 280,
  },
  safetyRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 8,
    marginVertical: spacing.md,
  },
  safetyBadge: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 5,
    backgroundColor: '#FFFFFF',
    paddingVertical: 8,
    paddingHorizontal: 6,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#E2E8F0',
  },
  safetyBadgeText: {
    fontSize: 11,
    fontWeight: '700',
    color: colors.ink,
  },
  primaryActionWrap: {
    marginBottom: spacing.lg,
  },
  primaryBanner: {
    backgroundColor: '#0095F6',
    borderRadius: 18,
    padding: spacing.md + 2,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    shadowColor: '#0095F6',
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.35,
    shadowRadius: 14,
    elevation: 5,
  },
  primaryBannerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    flex: 1,
  },
  bannerIconBox: {
    width: 46,
    height: 46,
    borderRadius: 14,
    backgroundColor: 'rgba(255, 255, 255, 0.22)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  bannerTitle: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '800',
    letterSpacing: -0.2,
  },
  bannerSubtitle: {
    color: 'rgba(255, 255, 255, 0.85)',
    fontSize: 12,
    marginTop: 2,
  },
  bannerArrow: {
    width: 32,
    height: 32,
    borderRadius: 16,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  sectionHeader: {
    marginBottom: spacing.sm,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '800',
    color: colors.ink,
    letterSpacing: -0.2,
  },
  cardsList: {
    gap: 10,
  },
  hubCard: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#FFFFFF',
    padding: spacing.md,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: '#E2E8F0',
    borderLeftWidth: 4,
    gap: 12,
    shadowColor: '#000000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.04,
    shadowRadius: 8,
    elevation: 2,
  },
  cardPressed: {
    opacity: 0.85,
    transform: [{ scale: 0.99 }],
  },
  iconContainer: {
    width: 42,
    height: 42,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  cardContent: {
    flex: 1,
  },
  cardTitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  cardTitle: {
    fontSize: 14,
    fontWeight: '800',
    color: colors.ink,
  },
  cardBadge: {
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 6,
  },
  cardBadgeText: {
    fontSize: 9,
    fontWeight: '900',
    letterSpacing: 0.4,
  },
  cardSubtitle: {
    fontSize: 12,
    color: colors.muted,
    marginTop: 2,
    lineHeight: 16,
  },
  footerSection: {
    marginTop: spacing.xl,
    paddingTop: spacing.md,
    borderTopWidth: 1,
    borderTopColor: '#E2E8F0',
    alignItems: 'center',
    gap: 10,
  },
  footerUserText: {
    fontSize: 12,
    color: colors.muted,
    fontWeight: '600',
  },
});
