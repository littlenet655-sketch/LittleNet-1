import { useState } from 'react';
import { FlatList, Image, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import {
  fetchAdminAudit,
  fetchAdminDashboard,
  fetchAdminReview,
  fetchAdminReviews,
  fetchAdminUsers,
  resolveAdminReview,
  updateAdminUserStatus,
} from '../../api/parentAdmin';
import { useAuth } from '../../auth/AuthProvider';
import type { AdminScreenProps } from '../../navigation/types';
import { useIsOnline } from '../../query/client';
import { adminKeys } from '../../query/keys';
import { BrandHeader, Button, Card, EmptyState, ErrorState, Field, LoadingState, Notice, OfflineBanner, Screen, errorText } from '../../ui/components';
import { CategoryBadge, TimeAgo } from '../../ui/social';
import { colors, radius, spacing, type } from '../../ui/tokens';

function Metric({ value, label, alert = false }: { value: number; label: string; alert?: boolean }) {
  return <View style={[styles.metric, alert && styles.alertMetric]}><Text style={styles.metricValue}>{value}</Text><Text style={styles.muted}>{label}</Text></View>;
}

export function AdminHomeScreen({ navigation }: AdminScreenProps<'AdminHome'>) {
  const { session, signOut } = useAuth();
  const online = useIsOnline();
  const query = useQuery({ queryKey: adminKeys.dashboard, queryFn: () => fetchAdminDashboard(session?.token ?? ''), enabled: Boolean(session) });
  const counts = query.data?.counts;
  return <Screen><ScrollView refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={() => void query.refetch()} />}><OfflineBanner online={online} /><BrandHeader title="Moderator dashboard" subtitle="Review safety events, account state and an append-only action history." />{query.isPending ? <LoadingState message="Loading moderation totals…" /> : query.isError ? <ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /> : <View style={styles.metrics}><Metric value={counts?.open_reviews ?? 0} label="Open reviews" alert={Boolean(counts?.open_reviews)} /><Metric value={counts?.children ?? 0} label="Children" /><Metric value={counts?.parents ?? 0} label="Parents" /></View>}<Menu label="Moderation queue" body="Inspect open REVIEW events" onPress={() => navigation.navigate('AdminReviews')} /><Menu label="User lookup" body="Search account role and status" onPress={() => navigation.navigate('AdminUsers')} /><Menu label="Audit history" body="See moderator and account actions" onPress={() => navigation.navigate('AdminAudit')} /><Button label="Log out" variant="secondary" onPress={() => void signOut()} /></ScrollView></Screen>;
}

function Menu({ label, body, onPress }: { label: string; body: string; onPress: () => void }) {
  return <Pressable accessibilityRole="button" style={styles.menu} onPress={onPress}><Text style={styles.title}>{label}</Text><Text style={styles.muted}>{body}</Text></Pressable>;
}

export function AdminReviewsScreen({ navigation }: AdminScreenProps<'AdminReviews'>) {
  const { session } = useAuth();
  const query = useQuery({ queryKey: adminKeys.reviews, queryFn: () => fetchAdminReviews(session?.token ?? ''), enabled: Boolean(session) });
  const events = query.data?.events ?? [];
  return <Screen><FlatList data={events} keyExtractor={(event) => String(event.event_id)} refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={() => void query.refetch()} />} ListHeaderComponent={<BrandHeader title="Moderation queue" subtitle="The server returns at most 100 open REVIEW events, newest first." />} ListEmptyComponent={query.isPending ? <LoadingState message="Loading review queue…" /> : query.isError ? <ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /> : <EmptyState title="Moderation queue clear" body="Open review events will appear here." />} renderItem={({ item: event }) => <Pressable accessibilityRole="button" style={styles.menu} onPress={() => navigation.navigate('AdminReview', { eventId: event.event_id })}><View style={styles.rowBetween}><CategoryBadge label={event.content_type} /><TimeAgo value={event.created_at} /></View><Text style={styles.title}>{event.full_name ?? event.username ?? `Child ${event.child_id}`}</Text><Text style={styles.body}>{event.reason || 'Requires moderator review'}</Text><Text style={styles.muted}>Risk: {String(event.risk_score ?? 'not provided')}</Text></Pressable>} /></Screen>;
}

export function AdminReviewScreen({ navigation, route }: AdminScreenProps<'AdminReview'>) {
  const { session } = useAuth();
  const client = useQueryClient();
  const [notes, setNotes] = useState('');
  const query = useQuery({ queryKey: adminKeys.review(route.params.eventId), queryFn: () => fetchAdminReview(session?.token ?? '', route.params.eventId), enabled: Boolean(session) });
  const mutation = useMutation({
    mutationFn: (action: 'APPROVE' | 'BLOCK' | 'ESCALATE') => resolveAdminReview(session?.token ?? '', route.params.eventId, action, notes),
    onSuccess: async (result) => {
      await Promise.all([client.invalidateQueries({ queryKey: adminKeys.reviews }), client.invalidateQueries({ queryKey: adminKeys.dashboard }), client.invalidateQueries({ queryKey: adminKeys.audit }), client.invalidateQueries({ queryKey: adminKeys.review(route.params.eventId) })]);
      if (result.status === 'RESOLVED') navigation.goBack();
    },
  });
  if (query.isPending) return <Screen><LoadingState message="Loading review detail…" /></Screen>;
  if (query.isError || !query.data) return <Screen><ErrorState message={errorText(query.error, 'Review unavailable.')} onRetry={() => void query.refetch()} /></Screen>;
  const { event, preview } = query.data;
  const previewImage = (preview?.media_type ?? '').toUpperCase() === 'IMAGE' ? preview?.media_url : preview?.poster_url;
  return <Screen><ScrollView><BrandHeader title="Moderation detail" subtitle="Final actions are confirmed by the backend and recorded in the audit history." /><Card><View style={styles.rowBetween}><CategoryBadge label={event.content_type} /><TimeAgo value={event.created_at} /></View><Text style={styles.title}>{event.full_name ?? event.username ?? `Child ${event.child_id}`}</Text>{previewImage ? <Image source={{ uri: previewImage, headers: { Authorization: `Bearer ${session?.token ?? ''}` } }} resizeMode="cover" style={styles.preview} /> : null}{preview?.media_url && !previewImage ? <Notice tone="info" message="The video remains in private quarantine. Use its event summary for this decision." /> : null}{preview?.caption ? <Text style={styles.body}>{preview.caption}</Text> : null}{preview?.comment_text ? <Text style={styles.body}>{preview.comment_text}</Text> : null}{preview?.message_text ? <Text style={styles.body}>{preview.message_text}</Text> : null}<Text style={styles.body}>{event.reason || 'No public-facing reason supplied.'}</Text><Text style={styles.muted}>Status: {event.status} · decision: {event.decision} · risk: {String(event.risk_score ?? 'not provided')}</Text><Field label="Moderator notes (optional)" value={notes} onChangeText={setNotes} multiline />{mutation.error ? <Notice message={errorText(mutation.error)} /> : null}{mutation.isSuccess && mutation.data.status === 'OPEN' ? <Notice tone="ok" message="Escalation recorded. This event remains open for a final decision." /> : null}<Button label="Approve" loading={mutation.isPending} onPress={() => mutation.mutate('APPROVE')} /><Button label="Block" variant="secondary" disabled={mutation.isPending} onPress={() => mutation.mutate('BLOCK')} /><Button label="Escalate" variant="secondary" disabled={mutation.isPending} onPress={() => mutation.mutate('ESCALATE')} /></Card></ScrollView></Screen>;
}

export function AdminUsersScreen(_props: AdminScreenProps<'AdminUsers'>) {
  const { session } = useAuth();
  const client = useQueryClient();
  const [input, setInput] = useState('');
  const [queryText, setQueryText] = useState('');
  const query = useQuery({ queryKey: adminKeys.users(queryText), queryFn: () => fetchAdminUsers(session?.token ?? '', queryText), enabled: Boolean(session) });
  const mutation = useMutation({ mutationFn: ({ userId, status }: { userId: number; status: 'ACTIVE' | 'SUSPENDED' }) => updateAdminUserStatus(session?.token ?? '', userId, status), onSuccess: async () => { await Promise.all([client.invalidateQueries({ queryKey: ['admin', 'users'] }), client.invalidateQueries({ queryKey: adminKeys.audit })]); } });
  const users = query.data?.users ?? [];
  const header = <><BrandHeader title="User lookup" subtitle="Search by name, username or email. Passwords, tokens and biometric data are never returned." /><Card><Field label="Search accounts" value={input} onChangeText={setInput} autoCapitalize="none" autoCorrect={false} /><Button label="Search" onPress={() => setQueryText(input.trim())} /></Card>{mutation.error ? <Notice message={errorText(mutation.error)} /> : null}</>;
  return <Screen><FlatList keyboardShouldPersistTaps="handled" data={users} keyExtractor={(user) => String(user.user_id)} refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={() => void query.refetch()} />} ListHeaderComponent={header} ListEmptyComponent={query.isPending ? <LoadingState message="Loading accounts…" /> : query.isError ? <ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /> : <EmptyState title="No accounts found" body="Try a different name, username or email." />} renderItem={({ item: user }) => <Card><View style={styles.rowBetween}><CategoryBadge label={user.role} /><Text style={[styles.status, user.account_status !== 'ACTIVE' && styles.statusAlert]}>{user.account_status}</Text></View><Text style={styles.title}>{user.full_name}</Text><Text style={styles.muted}>@{user.username} · {user.email}</Text>{user.role !== 'ADMIN' ? <Button label={user.account_status === 'ACTIVE' ? 'Suspend account' : 'Activate account'} variant="secondary" disabled={mutation.isPending} onPress={() => mutation.mutate({ userId: user.user_id, status: user.account_status === 'ACTIVE' ? 'SUSPENDED' : 'ACTIVE' })} /> : <Notice tone="info" message="Admin accounts cannot be changed from mobile lookup." />}</Card>} /></Screen>;
}

export function AdminAuditScreen(_props: AdminScreenProps<'AdminAudit'>) {
  const { session } = useAuth();
  const query = useQuery({ queryKey: adminKeys.audit, queryFn: () => fetchAdminAudit(session?.token ?? ''), enabled: Boolean(session) });
  const rows = query.data?.events ?? [];
  return <Screen><FlatList data={rows} keyExtractor={(event) => String(event.audit_id)} refreshControl={<RefreshControl refreshing={query.isRefetching} onRefresh={() => void query.refetch()} />} ListHeaderComponent={<BrandHeader title="Audit history" subtitle="A bounded, newest-first record of moderator actions." />} ListEmptyComponent={query.isPending ? <LoadingState message="Loading audit history…" /> : query.isError ? <ErrorState message={errorText(query.error)} onRetry={() => void query.refetch()} /> : <EmptyState title="No audit entries" body="Moderator actions will be recorded here." />} renderItem={({ item: event }) => <View style={styles.auditRow}><View style={styles.auditDot} /><View style={styles.flex}><Text style={styles.title}>{humanize(event.action)}</Text><Text style={styles.body}>{event.admin_name} · {event.target_type ?? 'SYSTEM'} {event.target_id ?? ''}</Text><TimeAgo value={event.created_at} /></View></View>} /></Screen>;
}

function humanize(value: string): string {
  return value.toLowerCase().split('_').map((part) => part.charAt(0).toUpperCase() + part.slice(1)).join(' ');
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  metrics: { flexDirection: 'row', gap: spacing.sm, marginBottom: spacing.md },
  metric: { flex: 1, minHeight: 72, padding: spacing.sm, borderRadius: radius.md, backgroundColor: '#F0F8FD', borderWidth: 1, borderColor: colors.line, justifyContent: 'center' },
  alertMetric: { backgroundColor: '#FFF1F2' },
  metricValue: { color: colors.ink, fontWeight: '900', fontSize: type.title },
  muted: { color: colors.muted, fontSize: type.caption, lineHeight: 19 },
  body: { color: colors.ink, fontSize: type.body, lineHeight: 22, marginTop: spacing.xs },
  title: { color: colors.ink, fontSize: type.subtitle, fontWeight: '800' },
  menu: { minHeight: 64, backgroundColor: colors.surface, borderRadius: radius.md, borderWidth: 1, borderColor: colors.line, padding: spacing.md, marginBottom: spacing.sm, justifyContent: 'center' },
  rowBetween: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.sm },
  preview: { width: '100%', height: 300, borderRadius: radius.md, backgroundColor: colors.line, marginVertical: spacing.sm },
  status: { color: colors.ok, fontWeight: '800', fontSize: type.caption },
  statusAlert: { color: colors.danger },
  auditRow: { flexDirection: 'row', gap: spacing.sm, minHeight: 68, paddingVertical: spacing.sm, borderBottomWidth: 1, borderBottomColor: colors.line, alignItems: 'center' },
  auditDot: { width: 12, height: 12, borderRadius: 6, backgroundColor: colors.brand },
});
