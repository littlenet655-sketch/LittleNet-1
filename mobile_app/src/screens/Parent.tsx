import { useState } from 'react';
import { ScrollView } from 'react-native';
import { useQuery } from '@tanstack/react-query';
import { createChild, fetchParentDashboard } from '../api/auth';
import { useAuth } from '../auth/AuthProvider';
import { useIsOnline } from '../query/client';
import type { ParentScreenProps } from '../navigation/types';
import { BrandHeader, Button, Card, EmptyState, ErrorState, Field, LoadingState, Notice, OfflineBanner, Screen, errorText } from '../ui/components';

/** Parent dashboard entry: child overview after successful setup. */
export function ParentHomeScreen({ navigation }: ParentScreenProps<'ParentHome'>) {
  const { session, signOut } = useAuth();
  const online = useIsOnline();
  const dashboard = useQuery({
    queryKey: ['parent-dashboard'],
    queryFn: () => fetchParentDashboard(session?.token ?? ''),
    enabled: Boolean(session?.token),
  });

  return (
    <Screen>
      <ScrollView>
        <OfflineBanner online={online} />
        <BrandHeader title="Parent dashboard" subtitle="Your verified guardian home. Add a child to begin." />
        <Card>
          <Button label="Add a child" onPress={() => navigation.navigate('CreateChild')} />
          <Button label="Log out" variant="secondary" onPress={() => void signOut()} />
        </Card>
        {dashboard.isPending ? (
          <LoadingState message="Loading your family…" />
        ) : dashboard.isError ? (
          <ErrorState message={errorText(dashboard.error)} onRetry={() => void dashboard.refetch()} />
        ) : (dashboard.data?.children.length ?? 0) === 0 ? (
          <EmptyState title="No children yet" body="Add your first child to set up face login and quizzes." />
        ) : (
          <Card>
            {(dashboard.data?.children ?? []).map((child) => {
              const row = child as { user_id: number; username: string; full_name: string };
              return <Notice key={row.user_id} tone="info" message={`${row.full_name} (@${row.username})`} />;
            })}
          </Card>
        )}
      </ScrollView>
    </Screen>
  );
}

export function CreateChildScreen({ navigation }: ParentScreenProps<'CreateChild'>) {
  const { session } = useAuth();
  const [username, setUsername] = useState('');
  const [fullName, setFullName] = useState('');
  const [age, setAge] = useState('');
  const [password, setPassword] = useState('');
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function submit() {
    const problems: Record<string, string> = {};
    if (username.trim().length < 3) problems.username = 'Pick at least 3 characters.';
    if (!fullName.trim()) problems.fullName = 'Enter the child\u2019s name.';
    const ageNumber = Number(age);
    if (!Number.isInteger(ageNumber) || ageNumber < 4 || ageNumber > 18) problems.age = 'Age must be 4–18.';
    if (password.length < 8) problems.password = 'At least 8 characters.';
    setFieldErrors(problems);
    if (Object.keys(problems).length > 0 || !session) return;
    setBusy(true);
    setError('');
    try {
      await createChild(session.token, { username: username.trim(), full_name: fullName.trim(), age: ageNumber, password });
      navigation.navigate('ParentHome');
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Screen>
      <ScrollView>
        <BrandHeader title="Add a child" subtitle="Next: face enrollment, then the welcome quiz on the Kids app." />
        <Card>
          <Field label="Child username" autoCapitalize="none" autoCorrect={false} value={username} onChangeText={setUsername} error={fieldErrors.username} />
          <Field label="Child full name" value={fullName} onChangeText={setFullName} error={fieldErrors.fullName} />
          <Field label="Age (4–18)" keyboardType="number-pad" value={age} onChangeText={setAge} error={fieldErrors.age} />
          <Field label="Child password (min 8)" secureTextEntry value={password} onChangeText={setPassword} error={fieldErrors.password} />
          {error ? <Notice message={error} /> : null}
          <Button label={busy ? 'Adding…' : 'Add child'} onPress={submit} loading={busy} disabled={busy} />
        </Card>
      </ScrollView>
    </Screen>
  );
}
