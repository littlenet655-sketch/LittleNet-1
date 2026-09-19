import { useEffect, useState } from 'react';
import { FlatList, Image, KeyboardAvoidingView, Platform, Pressable, RefreshControl, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Feather } from '@expo/vector-icons';
import {
  fetchFollowRequests,
  fetchParentActivity,
  fetchParentControls,
  fetchParentDashboard,
  fetchParentNotifications,
  fetchParentSafety,
  markParentNotificationsRead,
  resolveFollowRequest,
  resolveParentReview,
  updateParentControls,
  updateTimeLimit,
  type ParentChild,
  type ParentControls,
  type ReviewPreview,
} from '../../api/parentAdmin';
import { useAuth } from '../../auth/AuthProvider';
import type { ParentScreenProps } from '../../navigation/types';
import { useIsOnline } from '../../query/client';
import { parentKeys } from '../../query/keys';
import { BrandHeader, Button, Card, EmptyState, ErrorState, Field, LoadingState, Notice, OfflineBanner, Screen, errorText } from '../../ui/components';
import { Avatar, CategoryBadge, TimeAgo } from '../../ui/social';
import { colors, radius, spacing, type } from '../../ui/tokens';

type FeatherIconName = keyof typeof Feather.glyphMap;

const MENU: {
  label: string;
  body: string;
  icon: FeatherIconName;
  iconColor: string;
  badgeBg: string;
  route: 'Children' | 'ParentSafety' | 'ScreenTime' | 'ParentControls' | 'FollowRequests' | 'ParentActivity' | 'ParentNotifications' | 'ParentSettings';
}[] = [
  { label: 'Children', body: 'Profiles, progress and account state', icon: 'users', iconColor: '#2563EB', badgeBg: '#EFF6FF', route: 'Children' },
  { label: 'Safety Review', body: 'Items that need your decision', icon: 'shield', iconColor: '#DC2626', badgeBg: '#FEF2F2', route: 'ParentSafety' },
  { label: 'Screen Time', body: 'Daily usage and limits', icon: 'clock', iconColor: '#059669', badgeBg: '#ECFDF5', route: 'ScreenTime' },
  { label: 'Feature Controls', body: 'Permissions, quiet hours and categories', icon: 'sliders', iconColor: '#4F46E5', badgeBg: '#EEF2FF', route: 'ParentControls' },
  { label: 'Follow Requests', body: 'Two-parent friendship approvals', icon: 'user-check', iconColor: '#DB2777', badgeBg: '#FDF2F8', route: 'FollowRequests' },
  { label: 'Activity History', body: 'Recent child activity and logs', icon: 'activity', iconColor: '#7C3AED', badgeBg: '#F5F3FF', route: 'ParentActivity' },
  { label: 'Notifications', body: 'Safety and account updates', icon: 'bell', iconColor: '#D97706', badgeBg: '#FFFBEB', route: 'ParentNotifications' },
  { label: 'Parent Settings', body: 'Account and sign out', icon: 'settings', iconColor: '#475569', badgeBg: '#F1F5F9', route: 'ParentSettings' },
];

function useDashboard(token?: string) {
  return useQuery({
    queryKey: parentKeys.dashboard,
    queryFn: ({ signal }) => fetchParentDashboard(token ?? '', signal),
    enabled: Boolean(token),
  });
}

function RefreshingScroll({ refreshing, onRefresh, children }: { refreshing: boolean; onRefresh: () => void; children: React.ReactNode }) {
  return (
    <ScrollView
      style={styles.flex}
      keyboardShouldPersistTaps="handled"
      keyboardDismissMode="on-drag"
      automaticallyAdjustKeyboardInsets={Platform.OS === 'ios'}
      contentContainerStyle={styles.refreshScrollContent}
      showsVerticalScrollIndicator={true}
      nestedScrollEnabled={true}
      bounces={true}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
    >
      {children}
    </ScrollView>
  );
}

function GuardianBanner() {
  return (
    <View style={styles.guardianBanner}>
      <View style={styles.guardianRow}>
        <View style={styles.guardianIconWrap}>
          <Feather name="shield" size={24} color="#38BDF8" />
        </View>
        <View style={styles.flex}>
          <Text style={styles.guardianTitle}>Zero-Trust Child Guardian Active</Text>
          <Text style={styles.guardianSub}>Multimodal AI Safety (YOLOv8 + NudeNet + Detoxify) • Zero-Stranger Circle</Text>
        </View>
      </View>
      <View style={styles.guardianPillsRow}>
        <View style={styles.guardianPill}>
          <Feather name="check-circle" size={11} color="#60A5FA" />
          <Text style={styles.guardianPillText}>Pre-Filter: 100% Fail-Closed</Text>
        </View>
        <View style={styles.guardianPill}>
          <Feather name="check-circle" size={11} color="#60A5FA" />
          <Text style={styles.guardianPillText}>Friends: Mutual Parent Verified</Text>
        </View>
      </View>
    </View>
  );
}

function ChildCard({ child, onPress }: { child: ParentChild; onPress?: () => void }) {
  const limit = child.limit?.daily_limit_minutes;
  const usageRatio = limit ? Math.min(child.minutes_today / limit, 1) : 0;
  return (
    <Pressable accessibilityRole={onPress ? 'button' : undefined} disabled={!onPress} onPress={onPress} style={styles.childCard}>
      <Avatar uri={child.avatar_url} name={child.full_name} size={50} />
      <View style={styles.flex}>
        <View style={styles.childNameRow}>
          <Text style={styles.rowTitle}>{child.full_name}</Text>
          <View style={styles.presencePill}>
            <View style={[styles.statusDot, child.presence?.online && styles.statusDotOnline]} />
            <Text style={styles.presenceText}>{child.presence?.online ? 'Online' : 'Offline'}</Text>
          </View>
        </View>
        <Text style={styles.muted}>@{child.username} · {child.minutes_today} min today · {child.quiz_7d.accuracy}% quiz</Text>
        {limit ? (
          <View style={styles.usageTrack} accessibilityLabel={`${child.minutes_today} of ${limit} minutes used`}>
            <View style={[styles.usageFill, usageRatio >= 1 && styles.usageDanger, { width: `${Math.max(usageRatio * 100, 2)}%` }]} />
          </View>
        ) : null}
      </View>
      <View style={styles.childSignals}>
        {child.open_reviews > 0 ? (
          <View style={styles.alertPill}><Text style={styles.alertText}>{child.open_reviews} review</Text></View>
        ) : (
          <View style={styles.safePill}><Text style={styles.safeText}>✓ Safe</Text></View>
        )}
      </View>
    </Pressable>
  );
}

function AsyncBody({ query, emptyTitle, emptyBody, children }: { query: { isPending: boolean; isError: boolean; error: unknown; refetch: () => Promise<unknown> }; emptyTitle?: string; emptyBody?: string; children: React.ReactNode }) {
  if (query.isPending) return <LoadingState />;
  if (query.isError) return <ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} />;
  return <>{children || <EmptyState title={emptyTitle ?? 'Nothing here'} body={emptyBody} />}</>;
}

export function ParentHomeScreen({ navigation }: ParentScreenProps<'ParentHome'>) {
  const { session } = useAuth();
  const online = useIsOnline();
  const dashboard = useDashboard(session?.token);
  const children = dashboard.data?.children ?? [];
  const reviews = children.reduce((sum, child) => sum + Number(child.open_reviews || 0), 0);

  return (
    <Screen>
      <RefreshingScroll refreshing={dashboard.isRefetching} onRefresh={() => void dashboard.refetch()}>
        <OfflineBanner online={online} />
        <BrandHeader
          title={`Hello, ${session?.user.full_name ?? 'Parent'}`}
          subtitle="Family controls and safety decisions enforced by LittleNet's server."
          showLogo={false}
        />

        <GuardianBanner />

        <View style={styles.metrics}>
          <Metric value={String(children.length)} label="Children" icon="users" iconColor="#2563EB" />
          <Metric value={String(reviews)} label="Reviews" icon="shield" iconColor="#DC2626" tone={reviews ? 'alert' : 'normal'} />
          <Metric value={String(dashboard.data?.unread ?? 0)} label="Alerts" icon="bell" iconColor="#D97706" />
        </View>

        <View style={styles.sectionWrap}>
          <View style={styles.sectionHeaderRow}>
            <Text style={styles.sectionHeaderLabel}>CHILD OVERSIGHT</Text>
            <Pressable
              accessibilityRole="button"
              onPress={() => navigation.navigate('CreateChild')}
              hitSlop={8}
              style={styles.addInlineButton}
            >
              <Feather name="plus" size={13} color={colors.brand} />
              <Text style={styles.addInlineText}>Add Child</Text>
            </Pressable>
          </View>
          {dashboard.isPending ? (
            <LoadingState message="Loading your family…" />
          ) : dashboard.isError ? (
            <ErrorState message={errorText(dashboard.error)} onRetry={() => void dashboard.refetch()} />
          ) : children.length ? (
            <>
              {children.map((child) => (
                <ChildCard
                  key={child.user_id}
                  child={child}
                  onPress={() => navigation.navigate('ChildSummary', { childId: child.user_id })}
                />
              ))}
              <Pressable
                accessibilityRole="button"
                onPress={() => navigation.navigate('CreateChild')}
                style={styles.addChildCard}
              >
                <View style={styles.addChildCardPlusWrap}>
                  <Feather name="user-plus" size={18} color={colors.brand} />
                </View>
                <View style={styles.flex}>
                  <Text style={styles.addChildCardTitle}>Add Another Child Account</Text>
                  <Text style={styles.addChildCardSub}>Activate AI moderation and personalized screen time</Text>
                </View>
                <Feather name="chevron-right" size={18} color="#9CA3AF" />
              </Pressable>
            </>
          ) : (
            <Card>
              <View style={styles.emptyChildContainer}>
                <View style={styles.emptyChildBadge}>
                  <Feather name="user-plus" size={24} color={colors.brand} />
                </View>
                <Text style={styles.emptyChildTitle}>No Child Accounts Yet</Text>
                <Text style={styles.emptyChildBody}>
                  Add your child's profile to activate AI safety monitoring, age-tailored quizzes, and daily screen time limits.
                </Text>
                <Button label="+ Add First Child" onPress={() => navigation.navigate('CreateChild')} />
              </View>
            </Card>
          )}
        </View>

        <View style={styles.sectionWrap}>
          <Text style={styles.sectionHeaderLabel}>CONTROLS & SUPERVISION</Text>
          <View style={styles.menuGroupCard}>
            {MENU.slice(0, 4).map((item, idx) => (
              <Pressable
                key={item.route}
                accessibilityRole="button"
                style={[styles.menuRowItem, idx < 3 && styles.menuRowBorder]}
                onPress={() => navigation.navigate(item.route as never)}
              >
                <View style={[styles.menuIconBadge, { backgroundColor: item.badgeBg }]}>
                  <Feather name={item.icon} size={20} color={item.iconColor} />
                </View>
                <View style={styles.flex}>
                  <Text style={styles.menuTitle}>{item.label}</Text>
                  <Text style={styles.muted}>{item.body}</Text>
                </View>
                <Feather name="chevron-right" size={18} color="#9CA3AF" />
              </Pressable>
            ))}
          </View>
        </View>

        <View style={styles.sectionWrap}>
          <Text style={styles.sectionHeaderLabel}>COMMUNITY & ACCOUNT</Text>
          <View style={styles.menuGroupCard}>
            {MENU.slice(4).map((item, idx) => (
              <Pressable
                key={item.route}
                accessibilityRole="button"
                style={[styles.menuRowItem, idx < 3 && styles.menuRowBorder]}
                onPress={() => navigation.navigate(item.route as never)}
              >
                <View style={[styles.menuIconBadge, { backgroundColor: item.badgeBg }]}>
                  <Feather name={item.icon} size={20} color={item.iconColor} />
                </View>
                <View style={styles.flex}>
                  <Text style={styles.menuTitle}>{item.label}</Text>
                  <Text style={styles.muted}>{item.body}</Text>
                </View>
                <Feather name="chevron-right" size={18} color="#9CA3AF" />
              </Pressable>
            ))}
          </View>
        </View>

        <View style={styles.bottomCtaCard}>
          <View style={styles.bottomCtaHeader}>
            <View style={styles.bottomCtaIconWrap}>
              <Feather name="shield" size={20} color="#0284C7" />
            </View>
            <View style={styles.flex}>
              <Text style={styles.bottomCtaTitle}>Family Management</Text>
              <Text style={styles.bottomCtaSub}>Every child profile has independent safety rules & analytics</Text>
            </View>
          </View>
          <Button label="+ Add a Child Account" onPress={() => navigation.navigate('CreateChild')} />
        </View>
      </RefreshingScroll>
    </Screen>
  );
}

function Metric({
  value,
  label,
  icon,
  iconColor,
  tone = 'normal',
}: {
  value: string;
  label: string;
  icon: FeatherIconName;
  iconColor: string;
  tone?: 'normal' | 'alert';
}) {
  return (
    <View style={[styles.metric, tone === 'alert' && styles.metricAlert]}>
      <View style={styles.metricTop}>
        <Feather name={icon} size={20} color={tone === 'alert' ? colors.danger : iconColor} />
        <Text style={[styles.metricValue, tone === 'alert' && styles.metricValueAlert]}>{value}</Text>
      </View>
      <Text style={styles.metricLabel}>{label}</Text>
    </View>
  );
}

export function ParentChildrenScreen({ navigation }: ParentScreenProps<'Children'>) {
  const { session } = useAuth();
  const query = useDashboard(session?.token);
  const children = query.data?.children ?? [];
  return <Screen><RefreshingScroll refreshing={query.isRefetching} onRefresh={() => void query.refetch()}><BrandHeader title="Children" subtitle="Open a child to see only the summaries and controls available to your account." showLogo={false} /><AsyncBody query={query}>{children.length ? children.map((child) => <ChildCard key={child.user_id} child={child} onPress={() => navigation.navigate('ChildSummary', { childId: child.user_id })} />) : <EmptyState title="No children yet" body="Create a child account to continue." />}</AsyncBody><Button label="Add a child" onPress={() => navigation.navigate('CreateChild')} /></RefreshingScroll></Screen>;
}

export function ParentChildSummaryScreen({ navigation, route }: ParentScreenProps<'ChildSummary'>) {
  const { session } = useAuth();
  const query = useDashboard(session?.token);
  const child = query.data?.children.find((item) => item.user_id === route.params.childId);
  if (query.isPending) return <Screen><LoadingState message="Loading child summary…" /></Screen>;
  if (query.isError) return <Screen><ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /></Screen>;
  if (!child) return <Screen><EmptyState title="Child unavailable" body="This child is not linked to your active parent account." /></Screen>;
  return <Screen><ScrollView><BrandHeader title={child.full_name} subtitle={`@${child.username} · age ${child.age ?? 'not set'}`} showLogo={false} /><ChildCard child={child} /><Card><Text style={styles.sectionTitle}>This week</Text><Text style={styles.body}>Quiz: {child.quiz_7d.correct}/{child.quiz_7d.attempted} correct ({child.quiz_7d.accuracy}%)</Text><Text style={styles.body}>Safety level: {child.safety?.safety_level ?? 'STRICT'}</Text><Text style={styles.body}>Behavior indicator: {child.behavior?.level ?? 'No signal'} · {child.behavior?.trend ?? 'stable'}</Text>{child.behavior?.reasons?.map((reason) => <Text key={reason} style={styles.muted}>• {reason}</Text>)}</Card><Button label="Safety review" onPress={() => navigation.navigate('ParentSafety')} /><Button label="Screen time" variant="secondary" onPress={() => navigation.navigate('ScreenTime', { childId: child.user_id })} /><Button label="Controls" variant="secondary" onPress={() => navigation.navigate('ParentControls', { childId: child.user_id })} /><Button label="Activity" variant="secondary" onPress={() => navigation.navigate('ParentActivity', { childId: child.user_id })} /></ScrollView></Screen>;
}

export function ParentSafetyScreen({ navigation }: ParentScreenProps<'ParentSafety'>) {
  const { session } = useAuth();
  const query = useQuery({ queryKey: parentKeys.safety, queryFn: () => fetchParentSafety(session?.token ?? ''), enabled: Boolean(session) });
  const events = query.data?.events ?? [];
  return <Screen><FlatList data={events} keyExtractor={(event) => String(event.event_id)} refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={() => void query.refetch()} />} ListHeaderComponent={<BrandHeader title="Safety review" subtitle="Only open review items belonging to your children appear here." showLogo={false} />} ListEmptyComponent={query.isPending ? <LoadingState message="Loading safety reviews…" /> : query.isError ? <ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /> : <EmptyState title="Review queue clear" body="Items needing your decision will appear here." />} renderItem={({ item: event }) => <Pressable accessibilityRole="button" style={styles.listCard} onPress={() => navigation.navigate('ParentReview', { eventId: event.event_id })}><View style={styles.rowBetween}><RiskBadge score={event.risk_score} /><TimeAgo value={event.created_at} /></View><Text style={styles.rowTitle}>{event.full_name ?? 'Your child'}</Text><Text style={styles.body}>{event.reason || 'LittleNet needs a parent decision.'}</Text><Text style={styles.muted}>Evidence: {event.preview?.media_type ? humanize(event.preview.media_type) : 'text summary'} · Status: {humanize(event.status)}</Text></Pressable>} /></Screen>;
}

function ReviewMedia({ preview, token }: { preview?: ReviewPreview | null; token: string }) {
  const imageUrl = (preview?.media_type ?? '').toUpperCase() === 'IMAGE' ? preview?.media_url : preview?.poster_url;
  if (imageUrl) return <Image source={{ uri: imageUrl, headers: { Authorization: `Bearer ${token}` } }} resizeMode="cover" style={styles.reviewImage} />;
  if (preview?.media_url) return <Notice tone="info" message="This video remains in the private review area. Use its moderation summary for this decision." />;
  return null;
}

export function ParentReviewScreen({ navigation, route }: ParentScreenProps<'ParentReview'>) {
  const { session } = useAuth();
  const client = useQueryClient();
  const query = useQuery({ queryKey: parentKeys.safety, queryFn: () => fetchParentSafety(session?.token ?? ''), enabled: Boolean(session) });
  const event = query.data?.events.find((item) => item.event_id === route.params.eventId);
  const mutation = useMutation({
    mutationFn: (action: 'APPROVE' | 'BLOCK') => resolveParentReview(session?.token ?? '', route.params.eventId, action),
    onSuccess: async () => {
      await Promise.all([client.invalidateQueries({ queryKey: parentKeys.safety }), client.invalidateQueries({ queryKey: parentKeys.dashboard })]);
      navigation.goBack();
    },
  });
  if (query.isPending) return <Screen><LoadingState message="Loading review…" /></Screen>;
  if (!event) return <Screen><EmptyState title="Review unavailable" body="It may already be resolved or no longer belongs to your queue." /></Screen>;
  return <Screen><ScrollView><BrandHeader title="Review detail" subtitle="The server keeps this content private until an authorized decision is complete." showLogo={false} /><Card><View style={styles.rowBetween}><CategoryBadge label={event.content_type} /><TimeAgo value={event.created_at} /></View><Text style={styles.rowTitle}>{event.full_name ?? 'Your child'}</Text><ReviewMedia preview={event.preview} token={session?.token ?? ''} />{event.preview?.caption ? <Text style={styles.body}>{event.preview.caption}</Text> : null}{event.preview?.comment_text ? <Text style={styles.body}>{event.preview.comment_text}</Text> : null}{event.preview?.message_text ? <Text style={styles.body}>{event.preview.message_text}</Text> : null}<Text style={styles.muted}>Reason: {event.reason || 'Requires parent review'}</Text><Text style={styles.muted}>Risk score: {String(event.risk_score ?? 'Not provided')}</Text>{mutation.error ? <Notice message={errorText(mutation.error)} /> : null}<Button label="Approve safely" loading={mutation.isPending} onPress={() => mutation.mutate('APPROVE')} /><Button label="Block content" variant="secondary" disabled={mutation.isPending} onPress={() => mutation.mutate('BLOCK')} /></Card></ScrollView></Screen>;
}

function SelectChild({ children, onPick }: { children: ParentChild[]; onPick: (id: number) => void }) {
  return <>{children.map((child) => <ChildCard key={child.user_id} child={child} onPress={() => onPick(child.user_id)} />)}</>;
}

export function ParentScreenTimeScreen({ route }: ParentScreenProps<'ScreenTime'>) {
  const { session } = useAuth();
  const client = useQueryClient();
  const dashboard = useDashboard(session?.token);
  const [childId, setChildId] = useState<number | null>(route.params?.childId ?? null);
  const child = dashboard.data?.children.find((item) => item.user_id === childId);
  const [minutes, setMinutes] = useState('60');
  const [strict, setStrict] = useState(true);
  useEffect(() => { if (child?.limit) { setMinutes(String(child.limit.daily_limit_minutes)); setStrict(child.limit.strict_mode); } }, [child?.limit?.daily_limit_minutes, child?.limit?.strict_mode]);
  const mutation = useMutation({ mutationFn: () => updateTimeLimit(session?.token ?? '', childId ?? 0, Number(minutes), strict), onSuccess: async () => { await client.invalidateQueries({ queryKey: parentKeys.dashboard }); } });
  if (!childId) return <Screen><ScrollView keyboardShouldPersistTaps="handled"><BrandHeader title="Screen time" subtitle="Choose a child to view current usage and set a server-enforced daily limit." showLogo={false} /><AsyncBody query={dashboard}><SelectChild children={dashboard.data?.children ?? []} onPick={setChildId} /></AsyncBody></ScrollView></Screen>;
  if (!child) return <Screen><LoadingState message="Loading screen time…" /></Screen>;
  const valid = Number.isInteger(Number(minutes)) && Number(minutes) >= 1 && Number(minutes) <= 1440;
  const limit = Number(minutes);
  const usage = Math.min(child.minutes_today / Math.max(limit, 1), 1);
  return (
    <Screen>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'padding'}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 88 : 60}
        style={styles.flex}
      >
        <ScrollView
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="on-drag"
          automaticallyAdjustKeyboardInsets={true}
          contentContainerStyle={styles.formScrollContent}
        >
          <BrandHeader title={`${child.full_name}'s screen time`} subtitle={`${child.minutes_today} minutes used today. Overnight and active-session enforcement remains on the server.`} showLogo={false} />
          <Card>
            <View style={styles.usageSummary}>
              <Text style={styles.usageNumber}>{child.minutes_today}</Text>
              <Text style={styles.muted}>minutes used today</Text>
              <View style={styles.largeUsageTrack}>
                <View style={[styles.usageFill, usage >= 1 && styles.usageDanger, { width: `${Math.max(usage * 100, 2)}%` }]} />
              </View>
              <Text style={styles.muted}>{limit || '—'} minute daily allowance</Text>
            </View>
            <Field label="Daily limit in minutes (1–1440)" value={minutes} onChangeText={setMinutes} keyboardType="number-pad" error={valid ? undefined : 'Enter a whole number from 1 to 1440.'} />
            <Toggle label="Strict limit" body="Lock Kids Mode when the daily allowance is reached." value={strict} onChange={setStrict} />
            {mutation.isSuccess ? <Notice tone="ok" message="Screen-time limit saved." /> : null}
            {mutation.error ? <Notice message={errorText(mutation.error)} /> : null}
            <Button label="Save screen time" disabled={!valid} loading={mutation.isPending} onPress={() => mutation.mutate()} />
          </Card>
        </ScrollView>
      </KeyboardAvoidingView>
    </Screen>
  );
}

function Toggle({ label, body, value, onChange }: { label: string; body: string; value: boolean; onChange: (value: boolean) => void }) {
  return <View style={styles.toggle}><View style={styles.flex}><Text style={styles.rowTitle}>{label}</Text><Text style={styles.muted}>{body}</Text></View><Switch accessibilityLabel={label} value={value} onValueChange={onChange} trackColor={{ true: colors.teal }} /></View>;
}

export function ParentControlsScreen({ route }: ParentScreenProps<'ParentControls'>) {
  const { session } = useAuth();
  const client = useQueryClient();
  const dashboard = useDashboard(session?.token);
  const [childId, setChildId] = useState<number | null>(route.params?.childId ?? null);
  const query = useQuery({ queryKey: parentKeys.controls(childId ?? 0), queryFn: () => fetchParentControls(session?.token ?? '', childId ?? 0), enabled: Boolean(session && childId) });
  const [draft, setDraft] = useState<ParentControls | null>(null);
  useEffect(() => { if (query.data?.controls) setDraft(query.data.controls); }, [query.data?.controls]);
  const mutation = useMutation({ mutationFn: () => updateParentControls(session?.token ?? '', childId ?? 0, draft!), onSuccess: async (data) => { setDraft(data.controls); await Promise.all([client.invalidateQueries({ queryKey: parentKeys.dashboard }), client.invalidateQueries({ queryKey: parentKeys.controls(childId ?? 0) })]); } });
  if (!childId) return <Screen><ScrollView keyboardShouldPersistTaps="handled"><BrandHeader title="Controls" subtitle="Choose a child. These permissions are checked by the backend on every protected Kids route." showLogo={false} /><AsyncBody query={dashboard}><SelectChild children={dashboard.data?.children ?? []} onPick={setChildId} /></AsyncBody></ScrollView></Screen>;
  if (query.isPending || !draft) return <Screen><LoadingState message="Loading controls…" /></Screen>;
  if (query.isError) return <Screen><ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /></Screen>;
  const set = <K extends keyof ParentControls>(key: K, value: ParentControls[K]) => setDraft((current) => current ? { ...current, [key]: value } : current);
  const featureRows: Array<[keyof ParentControls, string, string]> = [
    ['allow_reels', 'Reels', 'Short-form videos'], ['allow_stories', 'Stories', '24-hour stories'], ['allow_messaging', 'Messages', 'Approved-friend chat'], ['allow_posting', 'Posting', 'Create posts, stories and reels'], ['allow_discover', 'Discover', 'Search and recommendations'],
  ];
  return (
    <Screen>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'padding'}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 88 : 60}
        style={styles.flex}
      >
        <ScrollView
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="on-drag"
          automaticallyAdjustKeyboardInsets={true}
          contentContainerStyle={styles.formScrollContent}
        >
          <BrandHeader title="Feature controls" subtitle="Changes take effect on the next Kids request; no reinstall or relogin is required." showLogo={false} />
          <Text style={styles.sectionKicker}>CONTENT & SOCIAL</Text>
          <Card>{featureRows.map(([key, label, body]) => <Toggle key={key} label={label} body={body} value={Boolean(draft[key])} onChange={(value) => set(key, value)} />)}</Card>
          <Text style={styles.sectionKicker}>LEARNING & ROUTINES</Text>
          <Card>
            <Toggle label="Educational-only feed" body="Limit the feed to learning-friendly categories." value={draft.educational_only_feed} onChange={(value) => set('educational_only_feed', value)} />
            <Toggle label="Quiet hours" body="Restrict Kids Mode during the configured window, including overnight windows." value={draft.quiet_hours_enabled} onChange={(value) => set('quiet_hours_enabled', value)} />
            {draft.quiet_hours_enabled ? (
              <>
                <Field label="Starts (24-hour HH:MM)" value={draft.quiet_start} onChangeText={(value) => set('quiet_start', value)} />
                <Field label="Ends (24-hour HH:MM)" value={draft.quiet_end} onChangeText={(value) => set('quiet_end', value)} />
                <Notice tone="info" message="For example, 21:00 to 07:00 runs overnight." />
              </>
            ) : null}
          </Card>
          <Text style={styles.sectionTitle}>Allowed categories</Text>
          <View style={styles.chips}>
            {(query.data?.categories ?? []).map((category) => {
              const selected = draft.allowed_categories.includes(category);
              return (
                <Pressable key={category} accessibilityRole="checkbox" accessibilityState={{ checked: selected }} style={[styles.chip, selected && styles.chipSelected]} onPress={() => set('allowed_categories', selected ? draft.allowed_categories.filter((item) => item !== category) : [...draft.allowed_categories, category])}>
                  <Text style={[styles.chipText, selected && styles.chipTextSelected]}>{category}</Text>
                </Pressable>
              );
            })}
          </View>
          {mutation.isSuccess ? <Notice tone="ok" message="Controls saved and active." /> : null}
          {mutation.error ? <Notice message={errorText(mutation.error)} /> : null}
          <Button label="Save controls" disabled={!draft.allowed_categories.length} loading={mutation.isPending} onPress={() => mutation.mutate()} />
        </ScrollView>
      </KeyboardAvoidingView>
    </Screen>
  );
}

export function ParentFollowRequestsScreen(_props: ParentScreenProps<'FollowRequests'>) {
  const { session } = useAuth();
  const client = useQueryClient();
  const query = useQuery({ queryKey: parentKeys.follows, queryFn: () => fetchFollowRequests(session?.token ?? ''), enabled: Boolean(session) });
  const mutation = useMutation({ mutationFn: ({ childId, targetId, action }: { childId: number; targetId: number; action: 'approve' | 'reject' }) => resolveFollowRequest(session?.token ?? '', childId, targetId, action), onSuccess: async () => { await Promise.all([client.invalidateQueries({ queryKey: parentKeys.follows }), client.invalidateQueries({ queryKey: parentKeys.dashboard })]); } });
  const rows = query.data?.pending ?? [];
  return <Screen><RefreshingScroll refreshing={query.isRefetching} onRefresh={() => void query.refetch()}><BrandHeader title="Follow requests" subtitle="Both families must approve before children can become active friends or chat." showLogo={false} /><AsyncBody query={query}>{rows.length ? rows.map((row) => <Card key={`${row.child_id}:${row.following_child_id}:${row.approval_stage}`}><View style={styles.rowBetween}><CategoryBadge label={row.approval_direction} /><TimeAgo value={row.created_at} /></View><Text style={styles.rowTitle}>{row.requester_name} → {row.target_name}</Text><Text style={styles.muted}>{row.stage_help}</Text>{row.actionable ? <View style={styles.actions}><View style={styles.flex}><Button label="Approve" disabled={mutation.isPending} onPress={() => mutation.mutate({ childId: row.child_id, targetId: row.following_child_id, action: 'approve' })} /></View><View style={styles.flex}><Button label="Deny" variant="secondary" disabled={mutation.isPending} onPress={() => mutation.mutate({ childId: row.child_id, targetId: row.following_child_id, action: 'reject' })} /></View></View> : null}</Card>) : <EmptyState title="No follow approvals" body="Pending two-parent friendship steps will appear here." />}</AsyncBody>{mutation.error ? <Notice message={errorText(mutation.error)} /> : null}</RefreshingScroll></Screen>;
}

export function ParentActivityScreen({ route }: ParentScreenProps<'ParentActivity'>) {
  const { session } = useAuth();
  const dashboard = useDashboard(session?.token);
  const [childId, setChildId] = useState<number | null>(route.params?.childId ?? null);
  const child = dashboard.data?.children.find((item) => item.user_id === childId);
  const query = useQuery({ queryKey: parentKeys.activity(childId ?? 0), queryFn: () => fetchParentActivity(session?.token ?? '', childId ?? 0), enabled: Boolean(session && childId) });
  if (!childId) return <Screen><ScrollView><BrandHeader title="Activity" subtitle="Choose a child to see their bounded activity history without private message contents." showLogo={false} /><AsyncBody query={dashboard}><SelectChild children={dashboard.data?.children ?? []} onPick={setChildId} /></AsyncBody></ScrollView></Screen>;
  const rows = query.data?.events ?? [];
  return <Screen><FlatList data={rows} keyExtractor={(event) => String(event.log_id)} refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={() => void query.refetch()} />} ListHeaderComponent={<BrandHeader title={`${child?.full_name ?? 'Child'} activity`} subtitle="Recent safety, control and account events." showLogo={false} />} ListEmptyComponent={query.isPending ? <LoadingState message="Loading activity…" /> : query.isError ? <ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /> : <EmptyState title="No recent activity" body="New account, safety and control events will appear here." />} renderItem={({ item: event }) => <View style={styles.activityRow}><View style={styles.timelineDot} /><View style={styles.flex}><Text style={styles.rowTitle}>{humanize(event.activity_type)}</Text><TimeAgo value={event.created_at} /></View></View>} /></Screen>;
}

export function ParentNotificationsScreen({ navigation }: ParentScreenProps<'ParentNotifications'>) {
  const { session } = useAuth();
  const client = useQueryClient();
  const query = useQuery({ queryKey: parentKeys.notifications, queryFn: () => fetchParentNotifications(session?.token ?? ''), enabled: Boolean(session) });
  const read = useMutation({ mutationFn: () => markParentNotificationsRead(session?.token ?? ''), onSuccess: async () => { await Promise.all([client.invalidateQueries({ queryKey: parentKeys.notifications }), client.invalidateQueries({ queryKey: parentKeys.dashboard })]); } });
  const rows = query.data?.notifications ?? [];
  function open(type: string) { const value = type.toUpperCase(); if (value.includes('FOLLOW')) navigation.navigate('FollowRequests'); else if (value.includes('REVIEW') || value.includes('BLOCK') || value.includes('SAFETY')) navigation.navigate('ParentSafety'); }
  return <Screen><FlatList data={rows} keyExtractor={(row) => String(row.notification_id)} refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={() => void query.refetch()} />} ListHeaderComponent={<><BrandHeader title="Notifications" subtitle="Refresh manually when you want the latest family updates." showLogo={false} />{rows.some((row) => !row.is_read) ? <Button label="Mark all read" variant="secondary" loading={read.isPending} onPress={() => read.mutate()} /> : null}</>} ListEmptyComponent={query.isPending ? <LoadingState message="Loading notifications…" /> : query.isError ? <ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /> : <EmptyState title="No notifications" body="Safety, control and friendship updates will appear here." />} renderItem={({ item: row }) => <Pressable accessibilityRole="button" style={[styles.notification, !row.is_read && styles.unread]} onPress={() => open(row.notification_type)}><View style={styles.flex}><Text style={styles.rowTitle}>{humanize(row.notification_type)}</Text><Text style={styles.body}>{row.notification_message}</Text></View><TimeAgo value={row.created_at} /></Pressable>} /></Screen>;
}

export function ParentSettingsScreen(_props: ParentScreenProps<'ParentSettings'>) {
  const { session, signOut } = useAuth();
  return <Screen><ScrollView><BrandHeader title="Parent settings" subtitle="Account access and mobile session controls." showLogo={false} /><Card><Text style={styles.rowTitle}>{session?.user.full_name}</Text><Text style={styles.muted}>@{session?.user.username}</Text><Text style={styles.muted}>{session?.user.email}</Text><Notice tone="info" message="LittleNet stores only the public API base URL in the mobile environment. Family controls remain server-enforced." /><Button label="Log out" variant="secondary" onPress={() => void signOut()} /></Card></ScrollView></Screen>;
}

function humanize(value: string): string {
  return value.toLowerCase().split('_').map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(' ');
}

function RiskBadge({ score }: { score?: number | string | null }) {
  const numeric = Number(score);
  const tone = Number.isFinite(numeric) && numeric >= 0.7 ? 'danger' : Number.isFinite(numeric) && numeric >= 0.4 ? 'review' : 'safe';
  return <View style={[styles.riskBadge, tone === 'danger' ? styles.riskDanger : tone === 'review' ? styles.riskReview : styles.riskSafe]}><Text style={styles.riskText}>{tone === 'safe' ? 'Review item' : `${tone === 'danger' ? 'High' : 'Review'} risk · ${String(score ?? 'not scored')}`}</Text></View>;
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  refreshScrollContent: { flexGrow: 1, paddingBottom: spacing.xl },
  formScrollContent: { flexGrow: 1, paddingBottom: spacing.xl },
  body: { color: colors.ink, fontSize: type.body, lineHeight: 22, marginTop: spacing.xs },
  muted: { color: colors.muted, fontSize: type.caption, lineHeight: 18 },
  sectionTitle: { color: colors.ink, fontSize: type.title, fontWeight: '800', marginTop: spacing.lg, marginBottom: spacing.sm, marginHorizontal: spacing.md },
  sectionWrap: { marginTop: spacing.sm },
  sectionHeaderRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingRight: spacing.md,
    marginBottom: spacing.xs,
  },
  sectionHeaderLabel: {
    color: colors.muted,
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 0.8,
    marginHorizontal: spacing.md,
    marginBottom: spacing.xs,
  },
  addInlineButton: {
    paddingHorizontal: 12,
    paddingVertical: 5,
    borderRadius: radius.pill,
    backgroundColor: '#EFF6FF',
    borderWidth: 1,
    borderColor: '#BFDBFE',
  },
  addInlineText: {
    color: colors.brand,
    fontWeight: '800',
    fontSize: 12,
  },
  emptyChildContainer: {
    alignItems: 'center',
    paddingVertical: spacing.sm,
    gap: 6,
  },
  emptyChildBadge: {
    width: 48,
    height: 48,
    borderRadius: 14,
    backgroundColor: '#EFF6FF',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 4,
  },
  emptyChildIcon: {
    fontSize: 24,
  },
  emptyChildTitle: {
    fontSize: 16,
    fontWeight: '800',
    color: colors.ink,
  },
  emptyChildBody: {
    fontSize: 12,
    color: colors.muted,
    textAlign: 'center',
    lineHeight: 18,
    maxWidth: 290,
    marginBottom: spacing.xs,
  },
  addChildCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    backgroundColor: '#F8FAFC',
    borderWidth: 1.5,
    borderColor: '#CBD5E1',
    borderStyle: 'dashed',
    borderRadius: 16,
    padding: 14,
    marginHorizontal: spacing.md,
    marginBottom: spacing.sm,
  },
  addChildCardPlusWrap: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: '#EFF6FF',
    alignItems: 'center',
    justifyContent: 'center',
  },
  addChildCardPlusIcon: { fontSize: 18, color: colors.brand, fontWeight: '900' },
  addChildCardTitle: { fontSize: 14, fontWeight: '800', color: colors.ink },
  addChildCardSub: { fontSize: 11, color: colors.muted, marginTop: 2 },
  buttonWrap: { marginHorizontal: spacing.md, marginTop: spacing.sm, marginBottom: spacing.md },
  guardianBanner: {
    backgroundColor: '#0F172A',
    borderRadius: 16,
    padding: spacing.md,
    marginHorizontal: spacing.md,
    marginBottom: spacing.md,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.12,
    shadowRadius: 10,
    elevation: 3,
  },
  guardianRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  guardianIconWrap: {
    width: 42,
    height: 42,
    borderRadius: 12,
    backgroundColor: 'rgba(0, 149, 246, 0.18)',
    borderWidth: 1,
    borderColor: 'rgba(0, 149, 246, 0.35)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  guardianIcon: { fontSize: 22 },
  guardianTitle: { color: '#FFFFFF', fontSize: 14, fontWeight: '800', letterSpacing: -0.2 },
  guardianSub: { color: '#94A3B8', fontSize: 11, marginTop: 2, lineHeight: 15 },
  guardianPillsRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginTop: 10,
    paddingTop: 10,
    borderTopWidth: 1,
    borderTopColor: '#1E293B',
  },
  guardianPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: '#1E293B',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: radius.pill,
  },
  guardianPillDot: { color: '#60A5FA', fontSize: 8 },
  guardianPillText: { color: '#E2E8F0', fontSize: 10, fontWeight: '700' },
  metrics: { flexDirection: 'row', gap: 8, marginHorizontal: spacing.md, marginBottom: spacing.md },
  metric: {
    flex: 1,
    padding: 12,
    borderRadius: 14,
    backgroundColor: '#FFFFFF',
    borderWidth: 1,
    borderColor: '#EFEFEF',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.03,
    shadowRadius: 6,
    elevation: 1,
  },
  metricAlert: { backgroundColor: '#FFF5F5', borderColor: '#FEE2E2' },
  metricTop: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 },
  metricIcon: { fontSize: 18 },
  metricValue: { color: colors.ink, fontWeight: '900', fontSize: 20 },
  metricValueAlert: { color: colors.danger },
  metricLabel: { color: colors.muted, fontSize: 11, fontWeight: '700', textTransform: 'uppercase', letterSpacing: 0.5 },
  menuGroupCard: {
    backgroundColor: '#FFFFFF',
    borderWidth: 1,
    borderColor: '#EFEFEF',
    borderRadius: 16,
    marginHorizontal: spacing.md,
    marginTop: spacing.xs,
    marginBottom: spacing.sm,
    overflow: 'hidden',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.03,
    shadowRadius: 6,
    elevation: 1,
  },
  menuRowItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 14,
    paddingVertical: 13,
  },
  menuRowBorder: {
    borderBottomWidth: 1,
    borderBottomColor: '#F3F4F6',
  },
  menuGrid: { gap: 8, marginHorizontal: spacing.md, marginTop: spacing.xs, marginBottom: spacing.sm },
  menuCard: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    padding: 12,
    borderWidth: 1,
    borderColor: '#EFEFEF',
    borderRadius: 14,
    backgroundColor: '#FFFFFF',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.02,
    shadowRadius: 4,
    elevation: 1,
  },
  menuIconBadge: {
    width: 44,
    height: 44,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  menuIconEmoji: { fontSize: 20 },
  menuTitle: { color: colors.ink, fontSize: 15, fontWeight: '800' },
  chevron: { color: '#9CA3AF', fontSize: 20, fontWeight: '600' },
  bottomCtaCard: {
    backgroundColor: '#F0F9FF',
    borderWidth: 1,
    borderColor: '#BAE6FD',
    borderRadius: 16,
    padding: 16,
    marginHorizontal: spacing.md,
    marginTop: spacing.md,
    marginBottom: spacing.md,
    gap: 12,
  },
  bottomCtaHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  bottomCtaIconWrap: {
    width: 40,
    height: 40,
    borderRadius: 12,
    backgroundColor: '#E0F2FE',
    alignItems: 'center',
    justifyContent: 'center',
  },
  bottomCtaIcon: { fontSize: 22 },
  bottomCtaTitle: { color: '#0369A1', fontSize: 15, fontWeight: '800' },
  bottomCtaSub: { color: '#0284C7', fontSize: 12, lineHeight: 16, marginTop: 2 },
  childCard: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'center',
    backgroundColor: '#FFFFFF',
    borderWidth: 1,
    borderColor: '#EFEFEF',
    borderRadius: 16,
    padding: 14,
    marginHorizontal: spacing.md,
    marginBottom: spacing.sm,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.03,
    shadowRadius: 6,
    elevation: 1,
  },
  childNameRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  presencePill: { flexDirection: 'row', alignItems: 'center', gap: 4, backgroundColor: '#F3F4F6', paddingHorizontal: 6, paddingVertical: 2, borderRadius: radius.pill },
  presenceText: { fontSize: 10, fontWeight: '700', color: colors.muted },
  childSignals: { alignItems: 'flex-end', gap: spacing.xs },
  statusDot: { width: 6, height: 6, borderRadius: 3, backgroundColor: '#9CA3AF' },
  statusDotOnline: { backgroundColor: '#10B981' },
  usageTrack: { height: 4, backgroundColor: '#F3F4F6', borderRadius: 4, overflow: 'hidden', marginTop: spacing.xs },
  usageFill: { height: 4, backgroundColor: colors.brand, borderRadius: 4 },
  usageDanger: { backgroundColor: colors.danger },
  usageSummary: { padding: spacing.md, backgroundColor: '#EFF6FF', borderRadius: 14, marginBottom: spacing.sm },
  usageNumber: { color: colors.brand, fontSize: 32, fontWeight: '900' },
  largeUsageTrack: { height: 8, backgroundColor: '#DBEAFE', borderRadius: 8, overflow: 'hidden', marginVertical: spacing.sm },
  sectionKicker: { color: colors.violet, fontSize: 11, fontWeight: '900', letterSpacing: 1.3, marginHorizontal: spacing.md, marginTop: spacing.sm, marginBottom: spacing.xs },
  riskBadge: { paddingHorizontal: spacing.sm, paddingVertical: spacing.xs, borderRadius: radius.pill },
  riskSafe: { backgroundColor: '#E7F6EC' },
  riskReview: { backgroundColor: '#FFF4D6' },
  riskDanger: { backgroundColor: '#FDECEC' },
  riskText: { color: colors.ink, fontSize: 11, fontWeight: '800' },
  listCard: { backgroundColor: colors.surface, borderWidth: 1, borderColor: '#EFEFEF', borderRadius: 14, padding: spacing.md, marginHorizontal: spacing.md, marginBottom: spacing.sm },
  rowTitle: { color: colors.ink, fontWeight: '800', fontSize: type.body },
  rowBetween: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.sm },
  alertPill: { backgroundColor: '#FDECEC', borderRadius: radius.pill, paddingHorizontal: 8, paddingVertical: 4 },
  alertText: { color: colors.danger, fontWeight: '800', fontSize: 11 },
  safePill: { backgroundColor: '#ECFDF5', borderRadius: radius.pill, paddingHorizontal: 8, paddingVertical: 4, borderWidth: 1, borderColor: '#A7F3D0' },
  safeText: { color: '#047857', fontWeight: '800', fontSize: 11 },
  reviewImage: { width: '100%', height: 280, borderRadius: 12, backgroundColor: colors.line, marginVertical: spacing.sm },
  toggle: { minHeight: 64, flexDirection: 'row', alignItems: 'center', gap: spacing.md, borderBottomWidth: 1, borderBottomColor: '#F3F4F6', paddingVertical: spacing.sm },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm, marginHorizontal: spacing.md },
  chip: { borderWidth: 1, borderColor: '#E5E7EB', borderRadius: radius.pill, paddingVertical: 8, paddingHorizontal: 14, backgroundColor: colors.surface },
  chipSelected: { backgroundColor: colors.teal, borderColor: colors.teal },
  chipText: { color: colors.ink, fontWeight: '700', fontSize: 13 },
  chipTextSelected: { color: colors.surface },
  actions: { flexDirection: 'row', gap: spacing.sm },
  activityRow: { flexDirection: 'row', gap: spacing.sm, minHeight: 62, paddingVertical: spacing.sm, borderBottomWidth: 1, borderBottomColor: '#F3F4F6', alignItems: 'center', marginHorizontal: spacing.md },
  timelineDot: { width: 10, height: 10, borderRadius: 5, backgroundColor: colors.teal },
  notification: { minHeight: 72, flexDirection: 'row', gap: spacing.sm, alignItems: 'center', borderBottomWidth: 1, borderBottomColor: '#F3F4F6', padding: spacing.md },
  unread: { backgroundColor: '#F0F9FF' },
});
