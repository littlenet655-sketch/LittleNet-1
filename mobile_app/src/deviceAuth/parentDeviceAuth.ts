/**
 * React Native bridge for the native ParentDeviceAuth module (Android).
 *
 * Contract (mirrors the native module):
 *   checkParentDeviceAuth(): {
 *     biometricAvailable: boolean;
 *     biometricEnrolled: boolean;
 *     deviceCredentialAvailable: boolean;
 *     canAuthenticate: boolean;
 *   }
 *   authenticateParentDevice(): {
 *     success: boolean;
 *     method?: 'BIOMETRIC' | 'DEVICE_CREDENTIAL';
 *     error?: string;   // user_cancel | not_enrolled | lockout | failure | unavailable | in_progress
 *     message?: string;
 *   }
 *
 * Authentication stays entirely inside the Android system prompt. The app
 * never reads or stores the PIN / pattern / password / biometric template.
 */
import { NativeModules, Platform } from 'react-native';

export interface ParentDeviceAuthStatus {
  biometricAvailable: boolean;
  biometricEnrolled: boolean;
  deviceCredentialAvailable: boolean;
  canAuthenticate: boolean;
}

export type ParentAuthMethod = 'BIOMETRIC' | 'DEVICE_CREDENTIAL';

export type ParentAuthErrorCode =
  | 'user_cancel'
  | 'not_enrolled'
  | 'lockout'
  | 'failure'
  | 'unavailable'
  | 'in_progress';

export interface ParentDeviceAuthResult {
  success: boolean;
  method?: ParentAuthMethod;
  error?: ParentAuthErrorCode | string;
  message?: string;
}

interface NativeParentDeviceAuth {
  checkParentDeviceAuth(): Promise<ParentDeviceAuthStatus>;
  authenticateParentDevice(): Promise<ParentDeviceAuthResult>;
}

const nativeModule: NativeParentDeviceAuth | null =
  Platform.OS === 'android' && NativeModules.ParentDeviceAuth
    ? (NativeModules.ParentDeviceAuth as NativeParentDeviceAuth)
    : null;

const UNAVAILABLE: ParentDeviceAuthStatus = {
  biometricAvailable: false,
  biometricEnrolled: false,
  deviceCredentialAvailable: false,
  canAuthenticate: false,
};

export function isParentDeviceAuthNativeAvailable(): boolean {
  return nativeModule !== null;
}

export async function checkParentDeviceAuth(): Promise<ParentDeviceAuthStatus> {
  if (!nativeModule) return { ...UNAVAILABLE };
  try {
    const status = await nativeModule.checkParentDeviceAuth();
    return {
      biometricAvailable: !!status.biometricAvailable,
      biometricEnrolled: !!status.biometricEnrolled,
      deviceCredentialAvailable: !!status.deviceCredentialAvailable,
      canAuthenticate: !!status.canAuthenticate,
    };
  } catch {
    return { ...UNAVAILABLE };
  }
}

export async function authenticateParentDevice(): Promise<ParentDeviceAuthResult> {
  if (!nativeModule) {
    return {
      success: false,
      error: 'unavailable',
      message: 'Device authentication is not available on this device.',
    };
  }
  try {
    const result = await nativeModule.authenticateParentDevice();
    if (result && result.success) {
      return { success: true, method: result.method };
    }
    return {
      success: false,
      error: (result && result.error) || 'failure',
      message: result && result.message,
    };
  } catch (err) {
    return {
      success: false,
      error: 'failure',
      message: err instanceof Error ? err.message : 'Authentication failed.',
    };
  }
}
