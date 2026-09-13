import { useEffect } from 'react';
import { NavigationContainer, useNavigation } from '@react-navigation/native';
import type { NavigationProp } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { useAuth } from '../auth/AuthProvider';
import { FaceEnrollScreen, FaceLoginScreen } from '../screens/ChildFace';
import { KidsHomeScreen, AdminHomeScreen } from '../screens/HomePlaceholders';
import { KidsTabsHost } from '../screens/kids/KidsTabsHost';
import { FeedScreen } from '../screens/kids/FeedScreen';
import { StoriesScreen } from '../screens/kids/StoriesScreen';
import { ReelsScreen } from '../screens/kids/ReelsScreen';
import { DiscoverScreen } from '../screens/kids/DiscoverScreen';
import { OwnProfileScreen } from '../screens/kids/OwnProfileScreen';
import { OtherProfileScreen } from '../screens/kids/OtherProfileScreen';
import { PostDetailScreen } from '../screens/kids/PostDetailScreen';
import { NotificationsScreen } from '../screens/kids/NotificationsScreen';
import { ConversationsScreen } from '../screens/kids/ConversationsScreen';
import { ChatScreen } from '../screens/kids/ChatScreen';
import { CreateScreen } from '../screens/kids/CreateScreen';
import { ProcessingStatusScreen } from '../screens/kids/ProcessingScreen';
import { CreateChildScreen, ParentHomeScreen } from '../screens/Parent';
import { GuardianLivenessScreen, OtpVerifyScreen, ParentRegisterScreen } from '../screens/ParentOnboarding';
import { ForgotPasswordScreen, ResetPasswordScreen } from '../screens/PasswordReset';
import { QuizScreen } from '../screens/Quiz';
import { LoginScreen, WelcomeScreen } from '../screens/WelcomeLogin';
import { LoadingState, Screen } from '../ui/components';
import { resolveChildRoute } from './gates';
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
      <AuthStack.Screen name="ForgotPassword" component={ForgotPasswordScreen} options={{ title: 'Reset password' }} />
      <AuthStack.Screen name="ResetPassword" component={ResetPasswordScreen} options={{ title: 'New password' }} />
      <AuthStack.Screen name="ParentRegister" component={ParentRegisterScreen} options={{ title: 'Parent sign-up' }} />
      <AuthStack.Screen name="OtpVerify" component={OtpVerifyScreen} options={{ title: 'Verify email' }} />
      <AuthStack.Screen name="GuardianLiveness" component={GuardianLivenessScreen} options={{ title: 'Adult check' }} />
      <AuthStack.Screen name="FaceLogin" component={FaceLoginScreen} options={{ title: 'Face login' }} />
    </AuthStack.Navigator>
  );
}

/**
 * Keeps the visible child screen pinned to the authoritative gate state.
 * Runs on mount (fixes any initial-route mismatch) and on every gate change,
 * so enrollment/quiz completion transitions without manual navigation.
 */
function ChildGateSync() {
  const navigation = useNavigation<NavigationProp<ChildStackParamList>>();
  const { session } = useAuth();
  const target = resolveChildRoute(session?.onboarding, session?.user.quiz_required ?? true);

  useEffect(() => {
    const state = navigation.getState();
    const index = state?.index ?? 0;
    const current = state?.routes[index]?.name;
    if (current === target) return;
    if (target === 'Quiz' && current === 'Quiz') return;
    const currentParams =
      current === 'Quiz' ? (state?.routes[index]?.params as ChildStackParamList['Quiz']) : undefined;
    navigation.reset({
      index: 0,
      routes: [{ name: target, params: target === 'Quiz' ? currentParams : undefined } as never],
    });
  }, [navigation, target]);

  return null;
}

function ChildNavigator() {
  return (
    <ChildStack.Navigator initialRouteName="KidsHome">
      <ChildStack.Screen name="FaceEnroll" component={withGateSync(FaceEnrollScreen)} options={{ title: 'Face setup' }} />
      <ChildStack.Screen name="Quiz" component={withGateSync(QuizScreen)} options={{ title: 'Safety quiz' }} />
      <ChildStack.Screen name="KidsHome" component={withGateSync(KidsHomeScreen)} options={{ title: 'Home' }} />
      <ChildStack.Screen name="KidsTabs" component={withGateSync(KidsTabsHost)} options={{ title: 'LittleNet' }} />
      <ChildStack.Screen name="FeedTab" component={withGateSync(FeedScreen)} options={{ title: 'Home' }} />
      <ChildStack.Screen name="DiscoverTab" component={withGateSync(DiscoverScreen)} options={{ title: 'Discover' }} />
      <ChildStack.Screen name="CreateTab" component={withGateSync(CreateScreen)} options={{ title: 'Create' }} />
      <ChildStack.Screen name="ReelsTab" component={withGateSync(ReelsScreen)} options={{ title: 'Reels' }} />
      <ChildStack.Screen name="ProfileTab" component={withGateSync(OwnProfileScreen)} options={{ title: 'Profile' }} />
      <ChildStack.Screen name="Stories" component={withGateSync(StoriesScreen)} options={{ title: 'Stories' }} />
      <ChildStack.Screen name="NotificationsTab" component={withGateSync(NotificationsScreen)} options={{ title: 'Notifications' }} />
      <ChildStack.Screen name="Conversations" component={withGateSync(ConversationsScreen)} options={{ title: 'Messages' }} />
      <ChildStack.Screen name="Chat" component={withGateSync(ChatScreen)} options={{ title: 'Chat' }} />
      <ChildStack.Screen name="PostDetail" component={withGateSync(PostDetailScreen)} options={{ title: 'Post' }} />
      <ChildStack.Screen name="OtherProfile" component={withGateSync(OtherProfileScreen)} options={{ title: 'Profile' }} />
      <ChildStack.Screen name="ProcessingStatus" component={withGateSync(ProcessingStatusScreen)} options={{ title: 'Safety check' }} />
    </ChildStack.Navigator>
  );
}

/** Mounts the gate sync inside the active child screen (navigators accept only Screens). */
function withGateSync(Component: React.ComponentType<any>): React.ComponentType<any> {
  return function GatedScreen(props: any) {
    return (
      <>
        <ChildGateSync />
        <Component {...props} />
      </>
    );
  };
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
 * ChildStack (reactively pinned to face/quiz/home by ChildGateSync),
 * PARENT -> ParentStack, ADMIN -> AdminStack.
 */
export function RootNavigator() {
  const { status, session } = useAuth();

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

  return (
    <NavigationContainer>
      <ChildNavigator />
    </NavigationContainer>
  );
}
