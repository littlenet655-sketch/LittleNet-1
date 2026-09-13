import { useCallback, useEffect, useState } from 'react';
import { ScrollView } from 'react-native';
import { answerQuiz, fetchQuiz } from '../api/auth';
import type { QuizItem } from '../api/auth';
import { ApiError } from '../api/client';
import { useAuth } from '../auth/AuthProvider';
import { clearPendingDestination, loadPendingDestination, savePendingDestination } from '../auth/session';
import { secureStoreBackend } from '../auth/storage';
import type { ChildScreenProps } from '../navigation/types';
import { quizLoadStatus, shouldProceedAfterRefresh } from '../quiz/decision';
import { BrandHeader, Button, Card, GateNotice, LoadingState, Notice, Screen } from '../ui/components';

interface QuizScreenParams {
  /** Where to return after a required quiz completes. */
  returnTo?: string;
}

type Phase = 'loading' | 'ready' | 'unavailable' | 'complete';

/**
 * Mandatory onboarding quiz + recurring feed quiz gate.
 * Forward navigation happens only after an authoritative /me refresh
 * confirms the gates are clear. Refresh failure keeps the child gated
 * with retry; an empty required bank shows unavailable, never "All done".
 */
export function QuizScreen({ navigation, route }: ChildScreenProps<'Quiz'>) {
  const { session, refreshMe } = useAuth();
  const params = (route.params ?? {}) as QuizScreenParams;
  const [items, setItems] = useState<QuizItem[]>([]);
  const [reason, setReason] = useState('');
  const [required, setRequired] = useState(true);
  const [index, setIndex] = useState(0);
  const [feedback, setFeedback] = useState('');
  const [busy, setBusy] = useState(false);
  const [phase, setPhase] = useState<Phase>('loading');
  const [error, setError] = useState<unknown>(null);
  const [gateMessage, setGateMessage] = useState('');

  const load = useCallback(async () => {
    if (!session) return;
    setPhase('loading');
    setError(null);
    setGateMessage('');
    try {
      const response = await fetchQuiz(session.token);
      if (quizLoadStatus(response.quizzes.length) === 'unavailable') {
        setPhase('unavailable');
        return;
      }
      setItems(response.quizzes);
      setReason(response.reason);
      setRequired(response.required);
      setIndex(0);
      setFeedback('');
      if (params.returnTo) await savePendingDestination(secureStoreBackend, params.returnTo);
      setPhase('ready');
    } catch (err) {
      setError(err);
      setPhase('ready');
    }
  }, [session, params.returnTo]);

  useEffect(() => {
    void load();
  }, [load]);

  /** Authoritative completion: refresh gates, proceed only when clear. */
  async function completeQuiz() {
    setBusy(true);
    setGateMessage('');
    try {
      const next = await refreshMe();
      if (!shouldProceedAfterRefresh(next.onboarding)) {
        setGateMessage('The safety check still shows a required step. Reloading your quiz…');
        await load();
        return;
      }
      const destination = (await loadPendingDestination(secureStoreBackend)) ?? 'KidsHome';
      await clearPendingDestination(secureStoreBackend);
      navigation.reset({ index: 0, routes: [{ name: destination as never }] });
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) return;
      setGateMessage('Could not confirm quiz completion. Check your connection and retry — you are still safely gated.');
    } finally {
      setBusy(false);
    }
  }

  async function submitAnswer(option: string) {
    if (!session || busy || phase !== 'ready') return;
    const current = items[index];
    if (!current) return;
    setBusy(true);
    setFeedback('');
    try {
      const result = await answerQuiz(session.token, current.quiz_id, option);
      setFeedback(result.correct ? `Correct! +${result.xp} XP. ${result.explanation ?? ''}`.trim() : `Not quite. ${result.explanation ?? ''}`.trim());
      const lastItem = index + 1 >= items.length;
      if (result.onboarding_complete || !result.required || lastItem) {
        setTimeout(() => void completeQuiz(), 900);
        return;
      }
      setTimeout(() => {
        setIndex((value) => value + 1);
        setFeedback('');
      }, 900);
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) return;
      setFeedback(err instanceof ApiError ? err.message : 'Could not check that answer. Try again.');
    } finally {
      setBusy(false);
    }
  }

  if (phase === 'loading') {
    return (
      <Screen>
        <LoadingState message="Loading your quiz…" />
      </Screen>
    );
  }

  if (phase === 'unavailable') {
    return (
      <Screen>
        <BrandHeader title="Safety quiz" subtitle="Quizzes are temporarily unavailable." />
        <Notice message="We could not load your safety quiz right now. You are still safely gated — retry in a moment." />
        <Button label="Retry" onPress={() => void load()} />
      </Screen>
    );
  }

  if (error && items.length === 0) {
    return (
      <Screen>
        <BrandHeader title="Safety quiz" />
        <GateNotice error={error} />
        <Button label="Retry" onPress={() => void load()} />
      </Screen>
    );
  }

  const current = items[index];
  if (!current) {
    return (
      <Screen>
        <BrandHeader title="Safety quiz" />
        <Notice tone="info" message="Checking your progress…" />
        <Button label={busy ? 'Checking…' : 'Continue'} onPress={() => void completeQuiz()} loading={busy} disabled={busy} />
        {gateMessage ? <Notice tone="info" message={gateMessage} /> : null}
      </Screen>
    );
  }

  return (
    <Screen>
      <ScrollView>
        <BrandHeader
          title={reason === 'onboarding' ? 'Welcome quiz' : reason === 'feed_break' ? 'Quick brain break' : 'Practice quiz'}
          subtitle={required ? `Question ${index + 1} of ${items.length} — finish to continue.` : `Question ${index + 1} of ${items.length} — practice, no pressure.`}
        />
        <Card>
          <Notice tone="info" message={`Category: ${current.category}`} />
          <BrandHeader title={current.question} />
          {current.options.map((option) => (
            <Button key={option} label={option} variant="secondary" onPress={() => void submitAnswer(option)} disabled={busy} />
          ))}
          {feedback ? <Notice tone={feedback.startsWith('Correct') ? 'ok' : 'info'} message={feedback} /> : null}
          {gateMessage ? <Notice tone="info" message={gateMessage} /> : null}
        </Card>
      </ScrollView>
    </Screen>
  );
}
