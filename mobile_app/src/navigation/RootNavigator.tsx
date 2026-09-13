import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { useAuth } from '../auth/AuthProvider';
import { FaceEnrollScreen } from '../screens/ChildFace';
import { KidsHomeScreen, AdminHomeScreen } from '../screens/HomePlaceholders';
import { CreateChildScreen, ParentHomeScreen } from '../screens/Parent';
import { GuardianLivenessScreen, OtpVerifyScreen, ParentRegisterScreen } from '../screens/ParentOnboarding';
import { QuizScreen } from '../screens/Quiz';
import { FaceLoginScreen } from '../screens/ChildFace';
import { LoginScreen, WelcomeScreen } from '../screens/WelcomeLogin';
import { LoadingState, Screen } from '../ui/components';
import { childNextRoute } from './gates';
import type { AdminStackParamList, AuthStackParamList, ChildStackParamList, ParentStackParamList } from './types';

const AuthStack = createNativeStackNavigator<AuthStackParamList>();
const ChildStack = createNativeStackNavigator<ChildStackParamList>();
const ParentStack = createNativeStackNavigator<ParentStackParamList>();
const AdminStack = createNativeStackNavigator<AdminStackParamList>();

function AuthNavigator() {
  return (
    <AuthStack.Navigator>
      <AuthStack.Screen name="Welcome" component={WelcomeScreen} options={{ title: 'LittleNet' }} />
      <AuthStack.Screen name="Login" component={LoginScreen} options={{ title: 'Log in' }} />
      <AuthStack.Screen name="ParentRegister" component={ParentRegisterScreen} options={{ title: 'Parent sign-up' }} />
      <AuthStack.Screen name="OtpVerify" component={OtpVerifyScreen} options={{ title: 'Verify email' }} />
      <AuthStack.Screen name="GuardianLiveness" component={GuardianLivenessScreen} options={{ title: 'Adult check' }} />
      <AuthStack.Screen name="FaceLogin" component={FaceLoginScreen} options={{ title: 'Face login' }} />
    </AuthStack.Navigator>
  );
}

function ChildNavigator({ initialRoute }: { initialRoute: keyof ChildStackParamList }) {
  return (
    <ChildStack.Navigator initialRouteName={initialRoute}>
      <ChildStack.Screen name="FaceEnroll" component={FaceEnrollScreen} options={{ title: 'Face setup' }} />
      <ChildStack.Screen name="Quiz" component={QuizScreen} options={{ title: 'Safety quiz' }} />
      <ChildStack.Screen name="KidsHome" component={KidsHomeScreen} options={{ title: 'Home' }} />
    </ChildStack.Navigator>
  );
}

function ParentNavigator() {
  return (
    <ParentStack.Navigator initialRouteName="ParentHome">
      <ParentStack.Screen name="ParentHome" component={ParentHomeScreen} options={{ title: 'Parent dashboard' }} />
      <ParentStack.Screen name="CreateChild" component={CreateChildScreen} options={{ title: 'Add a child' }} />
    </ParentStack.Navigator>
  );
}

function AdminNavigator() {
  return (
    <AdminStack.Navigator>
      <AdminStack.Screen name="AdminHome" component={AdminHomeScreen} options={{ title: 'Moderation' }} />
    </AdminStack.Navigator>
  );
}

/**
 * Role-aware cold-start routing: unauthenticated -> AuthStack, CHILD ->
 * ChildStack (face gate first, then quiz gate, then home), PARENT ->
 * ParentStack, ADMIN -> AdminStack.
 */
export function RootNavigator() {
  const { status, session, onboarding } = useAuth();

  if (status === 'loading') {
    return (
      <Screen>
        <LoadingState message="Starting LittleNet…" />
      </Screen>
    );
  }

  if (status === 'signedOut' || !session) {
    return (
      <NavigationContainer>
        <AuthNavigator />
      </NavigationContainer>
    );
  }

  if (session.user.role === 'PARENT') {
    return (
      <NavigationContainer>
        <ParentNavigator />
      </NavigationContainer>
    );
  }

  if (session.user.role === 'ADMIN') {
    return (
      <NavigationContainer>
        <AdminNavigator />
      </NavigationContainer>
    );
  }

  const faceRequired = onboarding?.face_required ?? false;
  const quizRequired = onboarding?.quiz_required ?? session.user.quiz_required;
  const initialRoute = childNextRoute(faceRequired, quizRequired);
  return (
    <NavigationContainer>
      <ChildNavigator initialRoute={initialRoute} />
    </NavigationContainer>
  );
}
