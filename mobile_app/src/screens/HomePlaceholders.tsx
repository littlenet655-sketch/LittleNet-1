import { ScrollView } from 'react-native';
import { useAuth } from '../auth/AuthProvider';
import type { AdminScreenProps, ChildScreenProps } from '../navigation/types';
import { BrandHeader, Button, Card, Notice, Screen } from '../ui/components';

/**
 * Kids home placeholder owned by Agent C. The foundation guarantees auth,
 * gates, and query wiring; Agent C builds feed/stories/reels/discover here.
 */
export function KidsHomeScreen(_props: ChildScreenProps<'KidsHome'>) {
  const { session, signOut } = useAuth();
  return (
    <Screen>
      <ScrollView>
        <BrandHeader title={`Hi, ${session?.user.full_name ?? 'friend'}!`} subtitle="You passed every safety gate. The Kids feed lands here next." />
        <Card>
          <Notice tone="ok" message="Face ✓   Quiz ✓   You are ready to explore." />
          <Button label="Log out" variant="secondary" onPress={() => void signOut()} />
        </Card>
      </ScrollView>
    </Screen>
  );
}

/**
 * Admin home placeholder owned by Agent D. Auth + role routing are real;
 * the moderation queue/detail/resolve UI arrives with Agent D.
 */
export function AdminHomeScreen(_props: AdminScreenProps<'AdminHome'>) {
  const { signOut } = useAuth();
  return (
    <Screen>
      <ScrollView>
        <BrandHeader title="Moderation home" subtitle="Signed in as admin. The review queue lands here next." />
        <Card>
          <Button label="Log out" variant="secondary" onPress={() => void signOut()} />
        </Card>
      </ScrollView>
    </Screen>
  );
}
