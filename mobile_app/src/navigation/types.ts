import type { NativeStackScreenProps } from '@react-navigation/native-stack';

export type AuthStackParamList = {
  Welcome: undefined;
  Login: undefined;
  ParentRegister: undefined;
  OtpVerify: { pendingToken: string; emailSent?: boolean };
  GuardianLiveness: { pendingToken: string };
  FaceLogin: undefined;
};

export type ChildStackParamList = {
  FaceEnroll: undefined;
  Quiz: { returnTo?: string } | undefined;
  KidsHome: undefined;
};

export type ParentStackParamList = {
  ParentHome: undefined;
  CreateChild: undefined;
};

export type AdminStackParamList = {
  AdminHome: undefined;
};

export type AuthScreenProps<Route extends keyof AuthStackParamList> = NativeStackScreenProps<AuthStackParamList, Route>;
export type ChildScreenProps<Route extends keyof ChildStackParamList> = NativeStackScreenProps<ChildStackParamList, Route>;
export type ParentScreenProps<Route extends keyof ParentStackParamList> = NativeStackScreenProps<ParentStackParamList, Route>;
export type AdminScreenProps<Route extends keyof AdminStackParamList> = NativeStackScreenProps<AdminStackParamList, Route>;
