import { useCallback, useEffect, useState } from 'react';
import { ScrollView } from 'react-native';
import { answerQuiz, fetchQuiz } from '../api/auth';
import type { QuizItem } from '../api/auth';
import { ApiError } from '../api/client';
import { useAuth } from '../auth/AuthProvider';
import { clearPendingDestination, loadPendingDestination, savePendingDestination } from '../auth/session';
import { secureStoreBackend } from '../auth/storage';
import type { ChildScreenProps } from '../navigation/types';
import { BrandHeader, Button, Card, GateNotice, LoadingState, Notice, Screen } from '../ui/components';

interface QuizScreenParams {
  /** Where to return after a required quiz completes. */
  returnTo?: string;
}

/**
 * Mandatory onboarding quiz + recurring feed quiz gate.
 * Completing a required quiz restores the saved destination.
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
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<unknown>(null);

  const load = useCallback(async () => {
    if (!session) return;
    setLoading(true);
    setError(null);
    try {
      const response = await fetchQuiz(session.token);
      setItems(response.quizzes);
      setReason(response.reason);
      setRequired(response.required);
      setIndex(0);
      if (params.returnTo) await savePendingDestination(secureStoreBackend, params.returnTo);
    } catch (err) {
      setError(err);
    } finally {
      setLoading(false);
    }
  }, [session, params.returnTo]);

  useEffect(() => {
    void load();
  }, [load]);

  async function finish() {
    const destination = (await loadPendingDestination(secureStoreBackend)) ?? 'KidsHome';
    await clearPendingDestination(secureStoreBackend);
    await refreshMe().catch(() => undefined);
    navigation.reset({ index: 0, routes: [{ name: destination as never }] });
  }

  async function submitAnswer(option: string) {
    if (!session || busy) return;
    const current = items[index];
    if (!current) return;
    setBusy(true);
    setFeedback('');
    try {
      const result = await answerQuiz(session.token, current.quiz_id, option);
      setFeedback(result.correct ? `Correct! +${result.xp} XP. ${result.explanation ?? ''}`.trim() : `Not quite. ${result.explanation ?? ''}`.trim());
      if (result.onboarding_complete || !result.required) {
        // Small beat so the child sees the result, then restore destination.
        setTimeout(() => void finish(), 900);
        return;
      }
      if (index + 1 < items.length) {
        setTimeout(() => {
          setIndex((value) => value + 1);
          setFeedback('');
        }, 900);
      } else {
        await finish();
      }
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) return;
      setFeedback(err instanceof ApiError ? err.message : 'Could not check that answer. Try again.');
    } finally {
      setBusy(false);
    }
  }

  if (loading) {
    return (
      <Screen>
        <LoadingState message="Loading your quiz…" />
      </Screen>
    );
  }

  if (error) {
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
        <Notice tone="ok" message="All done! Returning you to the fun…" />
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
        </Card>
      </ScrollView>
    </Screen>
  );
}
