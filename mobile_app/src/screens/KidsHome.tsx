import { ScrollView } from 'react-native';
import { useAuth } from '../auth/AuthProvider';
import type { ChildScreenProps } from '../navigation/types';
import { BrandHeader, Button, Card, Notice, Screen } from '../ui/components';

/** Kids entry forwards to the complete tabbed product shell. */
export function KidsHomeScreen({ navigation }: ChildScreenProps<'KidsHome'>) {
  const { session, signOut } = useAuth();
  return (
    <Screen>
      <ScrollView>
        <BrandHeader title={`Hi, ${session?.user.full_name ?? 'friend'}!`} subtitle="Your safe feed is ready." />
        <Card>
          <Notice tone="ok" message="Face ✓   Quiz ✓   You are ready to explore." />
          <Button label="Open my feed" onPress={() => (navigation as unknown as { replace: (r: string, p: object) => void }).replace('KidsTabs', { tab: 'FeedTab' })} />
          <Button label="Log out" variant="secondary" onPress={() => void signOut()} />
        </Card>
      </ScrollView>
    </Screen>
  );
}
