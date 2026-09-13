import { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text } from 'react-native';
import { redriveProcessing } from '../../api/kidsUpload';
import { useAuth } from '../../auth/AuthProvider';
import { MAX_POLL_ATTEMPTS, moderationCopy } from '../../kids/social';
import { useProcessingStatus } from '../../kids/useProcessing';
import type { ChildScreenProps } from '../../navigation/types';
import { useIsForeground } from '../../query/client';
import { invalidateSocialCaches } from '../../query/keys';
import { BrandHeader, Button, Card, GateNotice, Notice, Screen } from '../../ui/components';
import { colors } from '../../ui/tokens';

export function ProcessingStatusScreen({ route }: ChildScreenProps<'ProcessingStatus'>) {
  const { session } = useAuth();
  const foreground = useIsForeground();
  const postId = Number((route.params as { postId?: number } | undefined)?.postId ?? 0);
  const poll = useProcessingStatus(postId || null, foreground);
  const [redriving, setRedriving] = useState(false);
  const [redriveError, setRedriveError] = useState<unknown>(null);
  const invalidatedPost = useRef<number | null>(null);

  useEffect(() => {
    if (poll.stage === 'allowed' && invalidatedPost.current !== postId) {
      invalidatedPost.current = postId;
      void invalidateSocialCaches([postId]);
    }
  }, [poll.stage, postId]);

  async function redrive() {
    if (!session || !postId) return;
    setRedriving(true);
    setRedriveError(null);
    try {
      await redriveProcessing(session.token, postId);
      await poll.refresh();
    } catch (reason) {
      setRedriveError(reason);
    } finally {
      setRedriving(false);
    }
  }

  const exhausted = poll.attempts >= MAX_POLL_ATTEMPTS;
  return (
    <Screen>
      <BrandHeader title="Safety check" subtitle={`Post #${postId}: ${poll.status}`} />
      {poll.error ? <GateNotice error={poll.error} /> : null}
      {redriveError ? <GateNotice error={redriveError} /> : null}
      {!foreground ? <Notice tone="info" message="Status checks pause while the app is in the background." /> : null}
      {exhausted && poll.stage === 'processing' ? <Notice tone="info" message="Automatic checks paused. You can refresh when you’re ready." /> : null}
      <Card><Text style={styles.copy}>{moderationCopy(poll.stage)}</Text></Card>
      <Button label={poll.refreshing ? 'Checking…' : 'Refresh status'} disabled={poll.refreshing} onPress={() => void poll.refresh()} />
      {poll.stage === 'retryable' ? <Button label={redriving ? 'Trying again…' : 'Try again'} variant="secondary" disabled={redriving} onPress={() => void redrive()} /> : null}
    </Screen>
  );
}

const styles = StyleSheet.create({ copy: { color: colors.ink } });
