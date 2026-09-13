/**
 * LittleNet mobile root.
 *
 * Composition only: safe-area, server-state (QueryProvider), session/auth
 * (AuthProvider), then role-aware navigation (RootNavigator). Screens live
 * under src/screens/ and all backend access goes through src/api/.
 */
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { AuthProvider } from './src/auth/AuthProvider';
import { RootNavigator } from './src/navigation/RootNavigator';
import { QueryProvider } from './src/query/client';

export default function App() {
  return (
    <SafeAreaProvider>
      <QueryProvider>
        <AuthProvider>
          <RootNavigator />
        </AuthProvider>
      </QueryProvider>
    </SafeAreaProvider>
  );
}
