import { useState } from 'react';
import { ScrollView } from 'react-native';
import { useQueryClient } from '@tanstack/react-query';
import { createChild } from '../api/auth';
import { useAuth } from '../auth/AuthProvider';
import type { ParentScreenProps } from '../navigation/types';
import { parentKeys } from '../query/keys';
import { BrandHeader, Button, Card, Field, Notice, Screen, errorText } from '../ui/components';

export function CreateChildScreen({ navigation }: ParentScreenProps<'CreateChild'>) {
  const { session } = useAuth();
  const queryClient = useQueryClient();
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
      await queryClient.invalidateQueries({ queryKey: parentKeys.dashboard });
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
