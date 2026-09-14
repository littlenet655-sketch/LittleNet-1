import { useCallback, useEffect, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { answerQuiz, fetchQuiz } from '../api/auth';
import type { QuizItem } from '../api/auth';
import { ApiError } from '../api/client';
import { useAuth } from '../auth/AuthProvider';
import { clearPendingDestination, loadPendingDestination, savePendingDestination } from '../auth/session';
import { secureStoreBackend } from '../auth/storage';
import type { ChildScreenProps } from '../navigation/types';
import { quizLoadStatus, shouldProceedAfterRefresh } from '../quiz/decision';
import { BrandHeader, Button, Card, GateNotice, LoadingState, Notice, Screen } from '../ui/components';
import { colors, type } from '../ui/tokens';

interface QuizScreenParams {
  /** Where to return after a required quiz completes. */
  returnTo?: string;
}

type Phase = 'loading' | 'hub' | 'ready' | 'unavailable' | 'complete';

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
  const [correctCount, setCorrectCount] = useState(0);
  const [earnedXp, setEarnedXp] = useState(0);

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
       setCorrectCount(0);
       setEarnedXp(0);
       setPhase(response.required ? 'ready' : 'hub');
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
      if (result.correct) setCorrectCount((value) => value + 1);
      setEarnedXp((value) => value + result.xp);
      setFeedback(result.correct ? `Correct! +${result.xp} XP. ${result.explanation ?? ''}`.trim() : `Not quite. ${result.explanation ?? ''}`.trim());
      const lastItem = index + 1 >= items.length;
      if (result.onboarding_complete || !result.required || lastItem) {
        setTimeout(() => {
          if (required) void completeQuiz();
          else setPhase('complete');
        }, 900);
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

  if (phase === 'hub') {
    return (
      <Screen>
        <ScrollView>
          <BrandHeader title="Learning Hub" subtitle="Small lessons, clear answers, and a safer way to take a break." />
          <View style={styles.hero}>
            <Text style={styles.eyebrow}>PRACTICE BANK</Text>
            <Text style={styles.heroTitle}>Choose a quick win.</Text>
            <Text style={styles.heroBody}>These questions come from LittleNet's live learning bank. Your answers and XP are saved by the server.</Text>
          </View>
          <View style={styles.statRow}>
            <Stat value={String(items.length)} label="Questions" />
            <Stat value="5–10 min" label="Typical session" />
          </View>
          <Text style={styles.sectionTitle}>Topics in this set</Text>
          <View style={styles.topicWrap}>
            {Array.from(new Set(items.map((item) => item.category))).map((category) => (
              <View key={category} style={styles.topic}><Text style={styles.topicText}>{category}</Text></View>
            ))}
          </View>
          <View style={styles.learningNote}>
            <Text style={styles.learningNoteTitle}>Educational feed</Text>
            <Text style={styles.learningNoteBody}>A separate educational playlist is not returned by the current API, so this hub only shows verified quiz content.</Text>
          </View>
          <Button label="Start practice" onPress={() => { setIndex(0); setFeedback(''); setPhase('ready'); }} />
        </ScrollView>
      </Screen>
    );
  }

  if (phase === 'complete') {
    return (
      <Screen>
        <ScrollView>
          <BrandHeader title="Practice complete" subtitle="Your result is based on answers confirmed by LittleNet." />
          <View style={styles.resultHero}>
            <Text style={styles.resultXp}>+{earnedXp} XP</Text>
            <Text style={styles.resultScore}>{correctCount} of {items.length} correct</Text>
            <Text style={styles.heroBody}>Keep going when you are ready. Practice quizzes never change your safety access.</Text>
          </View>
          <Button label="Practice again" onPress={() => { setIndex(0); setCorrectCount(0); setEarnedXp(0); setFeedback(''); setPhase('ready'); }} />
          <Button label="Back to learning hub" variant="secondary" onPress={() => setPhase('hub')} />
        </ScrollView>
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
        <View style={styles.progressTrack} accessibilityLabel={`Question ${index + 1} of ${items.length}`}>
          <View style={[styles.progressFill, { width: `${((index + 1) / items.length) * 100}%` }]} />
        </View>
        <Card>
          <Notice tone="info" message={`Category: ${current.category}`} />
          <Text style={styles.question}>{current.question}</Text>
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

const styles = StyleSheet.create({
  question: { color: colors.ink, fontSize: type.title, fontWeight: '700', lineHeight: 26, marginTop: 16, marginBottom: 8 },
  hero: { marginHorizontal: 12, padding: 20, borderRadius: 8, backgroundColor: '#EAF4FF', borderWidth: 1, borderColor: '#B9DFFF' },
  eyebrow: { color: colors.violet, fontSize: 11, fontWeight: '900', letterSpacing: 1.4 },
  heroTitle: { color: colors.ink, fontSize: 28, fontWeight: '900', marginTop: 8, letterSpacing: -0.7 },
  heroBody: { color: colors.muted, fontSize: type.body, lineHeight: 21, marginTop: 8 },
  statRow: { flexDirection: 'row', gap: 8, marginHorizontal: 12, marginTop: 12 },
  stat: { flex: 1, padding: 12, borderWidth: 1, borderColor: colors.line, backgroundColor: colors.surface, borderRadius: 8 },
  statValue: { color: colors.brand, fontSize: 20, fontWeight: '900' },
  statLabel: { color: colors.muted, fontSize: 12, marginTop: 2 },
  sectionTitle: { color: colors.ink, fontSize: 16, fontWeight: '900', marginHorizontal: 12, marginTop: 20, marginBottom: 8 },
  topicWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginHorizontal: 12 },
  topic: { borderRadius: 999, backgroundColor: '#F1EAFE', paddingHorizontal: 12, paddingVertical: 8 },
  topicText: { color: colors.violet, fontWeight: '800', fontSize: 12 },
  learningNote: { margin: 12, padding: 12, borderLeftWidth: 3, borderLeftColor: colors.sunny, backgroundColor: '#FFF8E8' },
  learningNoteTitle: { color: colors.ink, fontWeight: '900', fontSize: 14 },
  learningNoteBody: { color: colors.muted, fontSize: 12, lineHeight: 18, marginTop: 4 },
  resultHero: { margin: 12, padding: 24, alignItems: 'center', borderRadius: 8, backgroundColor: '#E7F6EC', borderWidth: 1, borderColor: '#A9E5C0' },
  resultXp: { color: colors.teal, fontSize: 34, fontWeight: '900' },
  resultScore: { color: colors.ink, fontSize: 18, fontWeight: '800', marginTop: 4 },
  progressTrack: { height: 6, backgroundColor: colors.line, marginHorizontal: 12, borderRadius: 6, overflow: 'hidden' },
  progressFill: { height: 6, backgroundColor: colors.brand, borderRadius: 6 },
});

function Stat({ value, label }: { value: string; label: string }) {
  return <View style={styles.stat}><Text style={styles.statValue}>{value}</Text><Text style={styles.statLabel}>{label}</Text></View>;
}
