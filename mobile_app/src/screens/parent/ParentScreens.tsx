import { useEffect, useState } from 'react';
import { FlatList, Image, Pressable, RefreshControl, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
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

const MENU: Array<{ label: string; body: string; route: keyof import('../../navigation/types').ParentStackParamList }> = [
  { label: 'Children', body: 'Profiles, progress and account state', route: 'Children' },
  { label: 'Safety review', body: 'Items that need your decision', route: 'ParentSafety' },
  { label: 'Screen time', body: 'Daily usage and limits', route: 'ScreenTime' },
  { label: 'Controls', body: 'Features, quiet hours and categories', route: 'ParentControls' },
  { label: 'Follow requests', body: 'Two-parent friendship approvals', route: 'FollowRequests' },
  { label: 'Activity', body: 'Recent child activity', route: 'ParentActivity' },
  { label: 'Notifications', body: 'Safety and account updates', route: 'ParentNotifications' },
  { label: 'Settings', body: 'Account and sign out', route: 'ParentSettings' },
];

function useDashboard(token?: string) {
  return useQuery({
    queryKey: parentKeys.dashboard,
    queryFn: ({ signal }) => fetchParentDashboard(token ?? '', signal),
    enabled: Boolean(token),
  });
}

function RefreshingScroll({ refreshing, onRefresh, children }: { refreshing: boolean; onRefresh: () => void; children: React.ReactNode }) {
  return <ScrollView refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}>{children}</ScrollView>;
}

function ChildCard({ child, onPress }: { child: ParentChild; onPress?: () => void }) {
  return (
    <Pressable accessibilityRole={onPress ? 'button' : undefined} disabled={!onPress} onPress={onPress} style={styles.childCard}>
      <Avatar uri={child.avatar_url} name={child.full_name} size={52} />
      <View style={styles.flex}>
        <Text style={styles.rowTitle}>{child.full_name}</Text>
        <Text style={styles.muted}>@{child.username} · {child.account_status}</Text>
        <Text style={styles.muted}>{child.minutes_today} min today · {child.quiz_7d.accuracy}% quiz accuracy</Text>
      </View>
      {child.open_reviews > 0 ? <View style={styles.alertPill}><Text style={styles.alertText}>{child.open_reviews} review</Text></View> : null}
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
  const firstChild = children[0];
  const reviews = children.reduce((sum, child) => sum + Number(child.open_reviews || 0), 0);

  return (
    <Screen>
      <RefreshingScroll refreshing={dashboard.isRefetching} onRefresh={() => void dashboard.refetch()}>
        <OfflineBanner online={online} />
        <BrandHeader title={`Hello, ${session?.user.full_name ?? 'Parent'}`} subtitle="Your family controls and safety decisions are enforced by LittleNet's server." />
        <View style={styles.metrics}>
          <Metric value={String(children.length)} label="Children" />
          <Metric value={String(reviews)} label="Reviews" tone={reviews ? 'alert' : 'normal'} />
          <Metric value={String(dashboard.data?.unread ?? 0)} label="Unread" />
        </View>
        {dashboard.isPending ? <LoadingState message="Loading your family…" /> : dashboard.isError ? <ErrorState message={errorText(dashboard.error)} onRetry={() => void dashboard.refetch()} /> : null}
        {firstChild ? <ChildCard child={firstChild} onPress={() => navigation.navigate('ChildSummary', { childId: firstChild.user_id })} /> : !dashboard.isPending && !dashboard.isError ? <EmptyState title="No children yet" body="Add your first child to begin their protected setup." /> : null}
        <View style={styles.menuGrid}>
          {MENU.map((item) => (
            <Pressable key={item.route} accessibilityRole="button" style={styles.menuCard} onPress={() => navigation.navigate(item.route as never)}>
              <Text style={styles.menuTitle}>{item.label}</Text>
              <Text style={styles.muted}>{item.body}</Text>
            </Pressable>
          ))}
        </View>
        <Button label="Add a child" onPress={() => navigation.navigate('CreateChild')} />
      </RefreshingScroll>
    </Screen>
  );
}

function Metric({ value, label, tone = 'normal' }: { value: string; label: string; tone?: 'normal' | 'alert' }) {
  return <View style={[styles.metric, tone === 'alert' && styles.metricAlert]}><Text style={styles.metricValue}>{value}</Text><Text style={styles.metricLabel}>{label}</Text></View>;
}

export function ParentChildrenScreen({ navigation }: ParentScreenProps<'Children'>) {
  const { session } = useAuth();
  const query = useDashboard(session?.token);
  const children = query.data?.children ?? [];
  return <Screen><RefreshingScroll refreshing={query.isRefetching} onRefresh={() => void query.refetch()}><BrandHeader title="Children" subtitle="Open a child to see only the summaries and controls available to your account." /><AsyncBody query={query}>{children.length ? children.map((child) => <ChildCard key={child.user_id} child={child} onPress={() => navigation.navigate('ChildSummary', { childId: child.user_id })} />) : <EmptyState title="No children yet" body="Create a child account to continue." />}</AsyncBody><Button label="Add a child" onPress={() => navigation.navigate('CreateChild')} /></RefreshingScroll></Screen>;
}

export function ParentChildSummaryScreen({ navigation, route }: ParentScreenProps<'ChildSummary'>) {
  const { session } = useAuth();
  const query = useDashboard(session?.token);
  const child = query.data?.children.find((item) => item.user_id === route.params.childId);
  if (query.isPending) return <Screen><LoadingState message="Loading child summary…" /></Screen>;
  if (query.isError) return <Screen><ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /></Screen>;
  if (!child) return <Screen><EmptyState title="Child unavailable" body="This child is not linked to your active parent account." /></Screen>;
  return <Screen><ScrollView><BrandHeader title={child.full_name} subtitle={`@${child.username} · age ${child.age ?? 'not set'}`} /><ChildCard child={child} /><Card><Text style={styles.sectionTitle}>This week</Text><Text style={styles.body}>Quiz: {child.quiz_7d.correct}/{child.quiz_7d.attempted} correct ({child.quiz_7d.accuracy}%)</Text><Text style={styles.body}>Safety level: {child.safety?.safety_level ?? 'STRICT'}</Text><Text style={styles.body}>Behavior indicator: {child.behavior?.level ?? 'No signal'} · {child.behavior?.trend ?? 'stable'}</Text>{child.behavior?.reasons?.map((reason) => <Text key={reason} style={styles.muted}>• {reason}</Text>)}</Card><Button label="Safety review" onPress={() => navigation.navigate('ParentSafety')} /><Button label="Screen time" variant="secondary" onPress={() => navigation.navigate('ScreenTime', { childId: child.user_id })} /><Button label="Controls" variant="secondary" onPress={() => navigation.navigate('ParentControls', { childId: child.user_id })} /><Button label="Activity" variant="secondary" onPress={() => navigation.navigate('ParentActivity', { childId: child.user_id })} /></ScrollView></Screen>;
}

export function ParentSafetyScreen({ navigation }: ParentScreenProps<'ParentSafety'>) {
  const { session } = useAuth();
  const query = useQuery({ queryKey: parentKeys.safety, queryFn: () => fetchParentSafety(session?.token ?? ''), enabled: Boolean(session) });
  const events = query.data?.events ?? [];
  return <Screen><FlatList data={events} keyExtractor={(event) => String(event.event_id)} refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={() => void query.refetch()} />} ListHeaderComponent={<BrandHeader title="Safety review" subtitle="Only open review items belonging to your children appear here." />} ListEmptyComponent={query.isPending ? <LoadingState message="Loading safety reviews…" /> : query.isError ? <ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /> : <EmptyState title="Review queue clear" body="Items needing your decision will appear here." />} renderItem={({ item: event }) => <Pressable accessibilityRole="button" style={styles.listCard} onPress={() => navigation.navigate('ParentReview', { eventId: event.event_id })}><View style={styles.rowBetween}><CategoryBadge label={event.content_type} /><TimeAgo value={event.created_at} /></View><Text style={styles.rowTitle}>{event.full_name ?? 'Your child'}</Text><Text style={styles.body}>{event.reason || 'LittleNet needs a parent decision.'}</Text></Pressable>} /></Screen>;
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
  return <Screen><ScrollView><BrandHeader title="Review detail" subtitle="The server keeps this content private until an authorized decision is complete." /><Card><View style={styles.rowBetween}><CategoryBadge label={event.content_type} /><TimeAgo value={event.created_at} /></View><Text style={styles.rowTitle}>{event.full_name ?? 'Your child'}</Text><ReviewMedia preview={event.preview} token={session?.token ?? ''} />{event.preview?.caption ? <Text style={styles.body}>{event.preview.caption}</Text> : null}{event.preview?.comment_text ? <Text style={styles.body}>{event.preview.comment_text}</Text> : null}{event.preview?.message_text ? <Text style={styles.body}>{event.preview.message_text}</Text> : null}<Text style={styles.muted}>Reason: {event.reason || 'Requires parent review'}</Text><Text style={styles.muted}>Risk score: {String(event.risk_score ?? 'Not provided')}</Text>{mutation.error ? <Notice message={errorText(mutation.error)} /> : null}<Button label="Approve safely" loading={mutation.isPending} onPress={() => mutation.mutate('APPROVE')} /><Button label="Block content" variant="secondary" disabled={mutation.isPending} onPress={() => mutation.mutate('BLOCK')} /></Card></ScrollView></Screen>;
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
  if (!childId) return <Screen><ScrollView><BrandHeader title="Screen time" subtitle="Choose a child to view current usage and set a server-enforced daily limit." /><AsyncBody query={dashboard}><SelectChild children={dashboard.data?.children ?? []} onPick={setChildId} /></AsyncBody></ScrollView></Screen>;
  if (!child) return <Screen><LoadingState message="Loading screen time…" /></Screen>;
  const valid = Number.isInteger(Number(minutes)) && Number(minutes) >= 1 && Number(minutes) <= 1440;
  return <Screen><ScrollView><BrandHeader title={`${child.full_name}'s screen time`} subtitle={`${child.minutes_today} minutes used today. Overnight and active-session enforcement remains on the server.`} /><Card><Field label="Daily limit in minutes (1–1440)" value={minutes} onChangeText={setMinutes} keyboardType="number-pad" error={valid ? undefined : 'Enter a whole number from 1 to 1440.'} /><Toggle label="Strict limit" body="Lock Kids Mode when the daily allowance is reached." value={strict} onChange={setStrict} />{mutation.isSuccess ? <Notice tone="ok" message="Screen-time limit saved." /> : null}{mutation.error ? <Notice message={errorText(mutation.error)} /> : null}<Button label="Save screen time" disabled={!valid} loading={mutation.isPending} onPress={() => mutation.mutate()} /></Card></ScrollView></Screen>;
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
  if (!childId) return <Screen><ScrollView><BrandHeader title="Controls" subtitle="Choose a child. These permissions are checked by the backend on every protected Kids route." /><AsyncBody query={dashboard}><SelectChild children={dashboard.data?.children ?? []} onPick={setChildId} /></AsyncBody></ScrollView></Screen>;
  if (query.isPending || !draft) return <Screen><LoadingState message="Loading controls…" /></Screen>;
  if (query.isError) return <Screen><ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /></Screen>;
  const set = <K extends keyof ParentControls>(key: K, value: ParentControls[K]) => setDraft((current) => current ? { ...current, [key]: value } : current);
  const featureRows: Array<[keyof ParentControls, string, string]> = [
    ['allow_reels', 'Reels', 'Short-form videos'], ['allow_stories', 'Stories', '24-hour stories'], ['allow_messaging', 'Messages', 'Approved-friend chat'], ['allow_posting', 'Posting', 'Create posts, stories and reels'], ['allow_discover', 'Discover', 'Search and recommendations'],
  ];
  return <Screen><ScrollView keyboardShouldPersistTaps="handled"><BrandHeader title="Feature controls" subtitle="Changes take effect on the next Kids request; no reinstall or relogin is required." /><Card>{featureRows.map(([key, label, body]) => <Toggle key={key} label={label} body={body} value={Boolean(draft[key])} onChange={(value) => set(key, value)} />)}<Toggle label="Educational-only feed" body="Limit the feed to learning-friendly categories." value={draft.educational_only_feed} onChange={(value) => set('educational_only_feed', value)} /><Toggle label="Quiet hours" body="Restrict Kids Mode during the configured window, including overnight windows." value={draft.quiet_hours_enabled} onChange={(value) => set('quiet_hours_enabled', value)} />{draft.quiet_hours_enabled ? <><Field label="Starts (24-hour HH:MM)" value={draft.quiet_start} onChangeText={(value) => set('quiet_start', value)} /><Field label="Ends (24-hour HH:MM)" value={draft.quiet_end} onChangeText={(value) => set('quiet_end', value)} /><Notice tone="info" message="For example, 21:00 to 07:00 runs overnight." /></> : null}</Card><Text style={styles.sectionTitle}>Allowed categories</Text><View style={styles.chips}>{(query.data?.categories ?? []).map((category) => { const selected = draft.allowed_categories.includes(category); return <Pressable key={category} accessibilityRole="checkbox" accessibilityState={{ checked: selected }} style={[styles.chip, selected && styles.chipSelected]} onPress={() => set('allowed_categories', selected ? draft.allowed_categories.filter((item) => item !== category) : [...draft.allowed_categories, category])}><Text style={[styles.chipText, selected && styles.chipTextSelected]}>{category}</Text></Pressable>; })}</View>{mutation.isSuccess ? <Notice tone="ok" message="Controls saved and active." /> : null}{mutation.error ? <Notice message={errorText(mutation.error)} /> : null}<Button label="Save controls" disabled={!draft.allowed_categories.length} loading={mutation.isPending} onPress={() => mutation.mutate()} /></ScrollView></Screen>;
}

export function ParentFollowRequestsScreen(_props: ParentScreenProps<'FollowRequests'>) {
  const { session } = useAuth();
  const client = useQueryClient();
  const query = useQuery({ queryKey: parentKeys.follows, queryFn: () => fetchFollowRequests(session?.token ?? ''), enabled: Boolean(session) });
  const mutation = useMutation({ mutationFn: ({ childId, targetId, action }: { childId: number; targetId: number; action: 'approve' | 'reject' }) => resolveFollowRequest(session?.token ?? '', childId, targetId, action), onSuccess: async () => { await Promise.all([client.invalidateQueries({ queryKey: parentKeys.follows }), client.invalidateQueries({ queryKey: parentKeys.dashboard })]); } });
  const rows = query.data?.pending ?? [];
  return <Screen><RefreshingScroll refreshing={query.isRefetching} onRefresh={() => void query.refetch()}><BrandHeader title="Follow requests" subtitle="Both families must approve before children can become active friends or chat." /><AsyncBody query={query}>{rows.length ? rows.map((row) => <Card key={`${row.child_id}:${row.following_child_id}:${row.approval_stage}`}><View style={styles.rowBetween}><CategoryBadge label={row.approval_direction} /><TimeAgo value={row.created_at} /></View><Text style={styles.rowTitle}>{row.requester_name} → {row.target_name}</Text><Text style={styles.muted}>{row.stage_help}</Text>{row.actionable ? <View style={styles.actions}><View style={styles.flex}><Button label="Approve" disabled={mutation.isPending} onPress={() => mutation.mutate({ childId: row.child_id, targetId: row.following_child_id, action: 'approve' })} /></View><View style={styles.flex}><Button label="Deny" variant="secondary" disabled={mutation.isPending} onPress={() => mutation.mutate({ childId: row.child_id, targetId: row.following_child_id, action: 'reject' })} /></View></View> : null}</Card>) : <EmptyState title="No follow approvals" body="Pending two-parent friendship steps will appear here." />}</AsyncBody>{mutation.error ? <Notice message={errorText(mutation.error)} /> : null}</RefreshingScroll></Screen>;
}

export function ParentActivityScreen({ route }: ParentScreenProps<'ParentActivity'>) {
  const { session } = useAuth();
  const dashboard = useDashboard(session?.token);
  const [childId, setChildId] = useState<number | null>(route.params?.childId ?? null);
  const child = dashboard.data?.children.find((item) => item.user_id === childId);
  const query = useQuery({ queryKey: parentKeys.activity(childId ?? 0), queryFn: () => fetchParentActivity(session?.token ?? '', childId ?? 0), enabled: Boolean(session && childId) });
  if (!childId) return <Screen><ScrollView><BrandHeader title="Activity" subtitle="Choose a child to see their bounded activity history without private message contents." /><AsyncBody query={dashboard}><SelectChild children={dashboard.data?.children ?? []} onPick={setChildId} /></AsyncBody></ScrollView></Screen>;
  const rows = query.data?.events ?? [];
  return <Screen><FlatList data={rows} keyExtractor={(event) => String(event.log_id)} refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={() => void query.refetch()} />} ListHeaderComponent={<BrandHeader title={`${child?.full_name ?? 'Child'} activity`} subtitle="Recent safety, control and account events." />} ListEmptyComponent={query.isPending ? <LoadingState message="Loading activity…" /> : query.isError ? <ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /> : <EmptyState title="No recent activity" body="New account, safety and control events will appear here." />} renderItem={({ item: event }) => <View style={styles.activityRow}><View style={styles.timelineDot} /><View style={styles.flex}><Text style={styles.rowTitle}>{humanize(event.activity_type)}</Text><TimeAgo value={event.created_at} /></View></View>} /></Screen>;
}

export function ParentNotificationsScreen({ navigation }: ParentScreenProps<'ParentNotifications'>) {
  const { session } = useAuth();
  const client = useQueryClient();
  const query = useQuery({ queryKey: parentKeys.notifications, queryFn: () => fetchParentNotifications(session?.token ?? ''), enabled: Boolean(session) });
  const read = useMutation({ mutationFn: () => markParentNotificationsRead(session?.token ?? ''), onSuccess: async () => { await Promise.all([client.invalidateQueries({ queryKey: parentKeys.notifications }), client.invalidateQueries({ queryKey: parentKeys.dashboard })]); } });
  const rows = query.data?.notifications ?? [];
  function open(type: string) { const value = type.toUpperCase(); if (value.includes('FOLLOW')) navigation.navigate('FollowRequests'); else if (value.includes('REVIEW') || value.includes('BLOCK') || value.includes('SAFETY')) navigation.navigate('ParentSafety'); }
  return <Screen><FlatList data={rows} keyExtractor={(row) => String(row.notification_id)} refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={() => void query.refetch()} />} ListHeaderComponent={<><BrandHeader title="Notifications" subtitle="Refresh manually when you want the latest family updates." />{rows.some((row) => !row.is_read) ? <Button label="Mark all read" variant="secondary" loading={read.isPending} onPress={() => read.mutate()} /> : null}</>} ListEmptyComponent={query.isPending ? <LoadingState message="Loading notifications…" /> : query.isError ? <ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /> : <EmptyState title="No notifications" body="Safety, control and friendship updates will appear here." />} renderItem={({ item: row }) => <Pressable accessibilityRole="button" style={[styles.notification, !row.is_read && styles.unread]} onPress={() => open(row.notification_type)}><View style={styles.flex}><Text style={styles.rowTitle}>{humanize(row.notification_type)}</Text><Text style={styles.body}>{row.notification_message}</Text></View><TimeAgo value={row.created_at} /></Pressable>} /></Screen>;
}

export function ParentSettingsScreen(_props: ParentScreenProps<'ParentSettings'>) {
  const { session, signOut } = useAuth();
  return <Screen><ScrollView><BrandHeader title="Parent settings" subtitle="Account access and mobile session controls." /><Card><Text style={styles.rowTitle}>{session?.user.full_name}</Text><Text style={styles.muted}>@{session?.user.username}</Text><Text style={styles.muted}>{session?.user.email}</Text><Notice tone="info" message="LittleNet stores only the public API base URL in the mobile environment. Family controls remain server-enforced." /><Button label="Log out" variant="secondary" onPress={() => void signOut()} /></Card></ScrollView></Screen>;
}

function humanize(value: string): string {
  return value.toLowerCase().split('_').map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(' ');
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  body: { color: colors.ink, fontSize: type.body, lineHeight: 22, marginTop: spacing.xs },
  muted: { color: colors.muted, fontSize: type.caption, lineHeight: 19 },
  sectionTitle: { color: colors.ink, fontSize: type.title, fontWeight: '800', marginTop: spacing.lg, marginBottom: spacing.sm },
  metrics: { flexDirection: 'row', gap: spacing.sm, marginBottom: spacing.md },
  metric: { flex: 1, minHeight: 72, padding: spacing.sm, borderRadius: radius.md, backgroundColor: '#F0F8FD', borderWidth: 1, borderColor: colors.line, justifyContent: 'center' },
  metricAlert: { backgroundColor: '#FFF1F2' },
  metricValue: { color: colors.ink, fontWeight: '800', fontSize: type.title },
  metricLabel: { color: colors.muted, fontSize: type.caption },
  menuGrid: { gap: spacing.sm, marginTop: spacing.md },
  menuCard: { minHeight: 64, padding: spacing.md, borderWidth: 1, borderColor: colors.line, borderRadius: radius.md, backgroundColor: colors.surface, justifyContent: 'center' },
  menuTitle: { color: colors.ink, fontSize: type.subtitle, fontWeight: '800' },
  childCard: { minHeight: 76, flexDirection: 'row', gap: spacing.sm, alignItems: 'center', backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.line, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.sm },
  listCard: { backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.line, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.sm },
  rowTitle: { color: colors.ink, fontWeight: '800', fontSize: type.body },
  rowBetween: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.sm },
  alertPill: { backgroundColor: '#FDECEC', borderRadius: radius.pill, paddingHorizontal: spacing.sm, paddingVertical: spacing.xs },
  alertText: { color: colors.danger, fontWeight: '800', fontSize: type.caption },
  reviewImage: { width: '100%', height: 280, borderRadius: 0, backgroundColor: colors.line, marginVertical: spacing.sm },
  toggle: { minHeight: 64, flexDirection: 'row', alignItems: 'center', gap: spacing.md, borderBottomWidth: 1, borderBottomColor: colors.line, paddingVertical: spacing.sm },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  chip: { borderWidth: 1, borderColor: colors.line, borderRadius: radius.pill, paddingVertical: spacing.sm, paddingHorizontal: spacing.md, backgroundColor: colors.surface },
  chipSelected: { backgroundColor: colors.teal, borderColor: colors.teal },
  chipText: { color: colors.ink, fontWeight: '700' },
  chipTextSelected: { color: colors.surface },
  actions: { flexDirection: 'row', gap: spacing.sm },
  activityRow: { flexDirection: 'row', gap: spacing.sm, minHeight: 62, paddingVertical: spacing.sm, borderBottomWidth: 1, borderBottomColor: colors.line, alignItems: 'center' },
  timelineDot: { width: 12, height: 12, borderRadius: 6, backgroundColor: colors.teal },
  notification: { minHeight: 72, flexDirection: 'row', gap: spacing.sm, alignItems: 'center', borderBottomWidth: 1, borderBottomColor: colors.line, padding: spacing.sm },
  unread: { backgroundColor: '#F0F8FD' },
});
