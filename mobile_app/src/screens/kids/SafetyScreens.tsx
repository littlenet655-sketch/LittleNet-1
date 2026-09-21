import { useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { fetchReports } from '../../api/kidsSocial';
import { useAuth } from '../../auth/AuthProvider';
import type { ChildScreenProps } from '../../navigation/types';
import { TimeAgo } from '../../ui/social';
import { Button, Card, EmptyState, ErrorState, GateNotice, LoadingState, Screen } from '../../ui/components';
import { colors, radius, spacing, type } from '../../ui/tokens';
import { SafetyListsCard } from './SocialStates';

export function SafetyCentreScreen({ navigation }: ChildScreenProps<'SafetyCentre'>) {
  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={styles.kicker}>YOUR SAFETY, YOUR SPACE</Text>
        <Text style={styles.title}>Safety Centre</Text>
        <Text style={styles.lead}>You can pause, leave, or ask for help whenever something online feels wrong.</Text>
        <Card>
          <Text style={styles.cardTitle}>If something feels unsafe</Text>
          <Text style={styles.body}>Do not reply or share personal details. Close the conversation, tell a trusted parent or guardian, and report what happened so it can be reviewed.</Text>
        </Card>
        <Card>
          <Text style={styles.cardTitle}>Quick Report</Text>
          <Text style={styles.body}>Open the post, profile, comment, or message you are worried about. Use its Safety actions to choose a clear reason and send a report.</Text>
          <Button label="Open my feed" onPress={() => navigation.navigate('KidsTabs', { tab: 'FeedTab' })} />
        </Card>
        <SafetyListsCard />
        <Button label="View report history" variant="secondary" onPress={() => navigation.navigate('ReportHistory')} />
        <View style={styles.parentNote}>
          <Text style={styles.cardTitle}>Need a parent?</Text>
          <Text style={styles.body}>Ask a parent or guardian in person. Parent help is handled by the linked family account and is not opened as a child action here.</Text>
        </View>
      </ScrollView>
    </Screen>
  );
}

export function ReportHistoryScreen({ navigation }: ChildScreenProps<'ReportHistory'>) {
  const { session } = useAuth();
  const query = useQuery({
    queryKey: ['kids', 'reports', session?.token ?? 'signed-out'],
    enabled: Boolean(session),
    queryFn: () => fetchReports(session!.token),
  });
  if (query.isPending) return <Screen><LoadingState message="Loading report history…" /></Screen>;
  if (query.isError) return <Screen><GateNotice error={query.error} /><ErrorState message="Could not load report history." onRetry={() => void query.refetch()} /></Screen>;
  const reports = query.data?.reports ?? [];
  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={styles.title}>Report history</Text>
        <Text style={styles.lead}>Reports you sent from this account appear here. Status comes from the safety review system.</Text>
        {!reports.length ? <EmptyState title="No reports yet" body="When you report something, its status will appear here." /> : reports.map((report) => (
          <Card key={report.report_id}>
            <View style={styles.reportTop}><Text style={styles.cardTitle}>{report.target_type} · {report.target_id}</Text><Text style={styles.status}>{report.status}</Text></View>
            <Text style={styles.body}>{report.reason}</Text>
            <TimeAgo value={report.created_at} />
          </Card>
        ))}
        <Button label="Back to Safety Centre" variant="secondary" onPress={() => navigation.goBack()} />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { paddingBottom: 24 },
  kicker: { color: colors.brand, fontSize: 11, fontWeight: '700', letterSpacing: 1, paddingHorizontal: spacing.md, paddingTop: spacing.lg },
  title: { color: colors.ink, fontSize: 26, fontWeight: '800', paddingHorizontal: spacing.md, marginTop: 4 },
  lead: { color: colors.muted, fontSize: type.body, lineHeight: 21, paddingHorizontal: spacing.md, marginTop: spacing.sm, marginBottom: spacing.md },
  cardTitle: { color: colors.ink, fontWeight: '700', fontSize: type.subtitle },
  body: { color: colors.ink, fontSize: type.body, lineHeight: 21, marginTop: spacing.sm },
  parentNote: { padding: spacing.md, borderTopWidth: 1, borderTopColor: colors.line, marginTop: spacing.md },
  reportTop: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  status: { color: colors.brandDark, fontSize: type.caption, fontWeight: '700' },
});