import { useRef, useState } from 'react';
import { useCameraPermissions } from 'expo-camera';
import { Linking, Platform, StyleSheet, Text, View } from 'react-native';
import NetInfo from '@react-native-community/netinfo';
import { ApiError } from '../api/client';
import { CameraBlockedError, CameraPermissionError } from './capture';
import type { CapturedPhoto } from './capture';
import { precheckFace } from './facePrecheck';
import { Button, Notice, errorText } from '../ui/components';
import { NativeCameraView } from '../ui/nativeViews';
import { colors, radius, spacing } from '../ui/tokens';

interface CameraCaptureProps {
  label: string;
  busyLabel?: string;
  busy?: boolean;
  /** Receives the locally checked live photo. Throw to surface API errors in place. */
  onCapture: (photo: CapturedPhoto) => void | Promise<void>;
  validatePhoto?: (photo: CapturedPhoto) => void | Promise<void>;
  instruction?: string;
}

function canRetrySubmission(error: unknown): boolean {
  return error instanceof ApiError && (error.status === 0 || error.status >= 500);
}

/**
 * Shared camera step for guardian liveness, face enrollment, and face login.
 * ML Kit checks the captured frame before any bytes are sent to the backend.
 */
export function CameraCapture({ label, busyLabel, busy = false, onCapture, validatePhoto, instruction }: CameraCaptureProps) {
  const cameraRef = useRef<React.ElementRef<typeof NativeCameraView>>(null);
  const [permission, requestPermission] = useCameraPermissions();
  const [working, setWorking] = useState(false);
  const [cameraReady, setCameraReady] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [pendingPhoto, setPendingPhoto] = useState<CapturedPhoto | null>(null);
  const loading = busy || working;

  async function submit(photo: CapturedPhoto) {
    const network = await NetInfo.fetch();
    if (network.isConnected === false) {
      throw new ApiError(0, 'verification_offline', 'Internet is required to complete verification.');
    }
    await onCapture(photo);
    setPendingPhoto(null);
  }

  async function capture() {
    if (!cameraRef.current || !cameraReady) return;
    setWorking(true);
    setError(null);
    let capturedPhoto: CapturedPhoto | null = null;
    try {
      const shot = await cameraRef.current.takePictureAsync({ base64: true, exif: false, quality: 0.7 });
      if (!shot?.base64) throw new Error('Could not read the camera photo. Please try again.');
      capturedPhoto = {
        base64: shot.base64,
        width: shot.width,
        height: shot.height,
        uri: shot.uri,
      };
      if (validatePhoto) await validatePhoto(capturedPhoto);
      else await precheckFace(capturedPhoto);
      await submit(capturedPhoto);
    } catch (err) {
      setPendingPhoto(capturedPhoto && canRetrySubmission(err) ? capturedPhoto : null);
      setError(err);
    } finally {
      setWorking(false);
    }
  }

  async function retrySubmission() {
    if (!pendingPhoto) return;
    setWorking(true);
    setError(null);
    try {
      await submit(pendingPhoto);
    } catch (err) {
      setPendingPhoto(canRetrySubmission(err) ? pendingPhoto : null);
      setError(err);
    } finally {
      setWorking(false);
    }
  }

  async function grantCamera() {
    const result = await requestPermission();
    if (!result.granted && !result.canAskAgain) {
      setError(new CameraBlockedError());
    } else if (!result.granted) {
      setError(new CameraPermissionError());
    } else {
      setError(null);
    }
  }

  if (Platform.OS === 'web') {
    return <Notice tone="info" message="Use the Android build for live camera verification." />;
  }
  if (!permission) return <Notice tone="info" message="Preparing the camera…" />;
  if (!permission.granted) {
    const blocked = permission.status === 'denied' && !permission.canAskAgain;
    return (
      <>
        <Notice message={blocked ? new CameraBlockedError().message : new CameraPermissionError().message} />
        <Button label={blocked ? 'Open Settings' : 'Allow camera'} variant="secondary" onPress={() => void (blocked ? Linking.openSettings() : grantCamera())} />
      </>
    );
  }

  return (
    <>
      <View style={styles.cameraFrame}>
        <NativeCameraView
          ref={cameraRef}
          style={styles.camera}
          facing="front"
          mode="picture"
          onCameraReady={() => setCameraReady(true)}
        />
        <View pointerEvents="none" style={styles.overlay}>
          <View style={styles.faceOval} />
          <Text style={styles.overlayText}>Keep one face inside the oval</Text>
        </View>
      </View>
      <View style={styles.steps}>
        <Text style={styles.stepActive}>1 Capture</Text>
        <Text style={styles.step}>2 Check</Text>
        <Text style={styles.step}>3 Verify</Text>
      </View>
      <Notice tone="info" message={instruction ?? 'Center your face, move closer if needed, and look straight. Your photo is checked on this device before upload.'} />
      {error ? <Notice message={errorText(error)} /> : null}
      {pendingPhoto && canRetrySubmission(error) ? (
        <>
          <Notice tone="info" message="Your checked photo is saved on this device. Reconnect to finish verification." />
          <Button label={loading ? 'Retrying…' : 'Retry verification'} onPress={() => void retrySubmission()} loading={loading} disabled={loading} />
          <Button label="Take a new photo" variant="secondary" onPress={() => { setPendingPhoto(null); setError(null); }} disabled={loading} />
        </>
      ) : (
        <Button label={loading ? (busyLabel ?? 'Checking…') : label} onPress={() => void capture()} loading={loading} disabled={loading || !cameraReady} />
      )}
    </>
  );
}

const styles = StyleSheet.create({
  cameraFrame: {
    height: 320,
    overflow: 'hidden',
    borderRadius: 18,
    backgroundColor: '#0F172A',
    position: 'relative',
    borderWidth: 1,
    borderColor: '#E2E8F0',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.1,
    shadowRadius: 10,
    elevation: 3,
  },
  camera: { flex: 1 },
  overlay: { ...StyleSheet.absoluteFill, alignItems: 'center', justifyContent: 'center' },
  faceOval: {
    width: 190,
    height: 245,
    borderRadius: 120,
    borderWidth: 2.5,
    borderColor: colors.brand,
    backgroundColor: 'rgba(0, 149, 246, 0.05)',
  },
  overlayText: {
    color: '#FFFFFF',
    backgroundColor: 'rgba(15, 23, 42, 0.75)',
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: radius.pill,
    marginTop: spacing.md,
    fontWeight: '700',
    fontSize: 12,
  },
  steps: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    paddingVertical: spacing.sm,
    backgroundColor: '#F8FAFC',
    borderRadius: 12,
    marginVertical: spacing.xs,
    borderWidth: 1,
    borderColor: '#E2E8F0',
  },
  step: { color: colors.muted, fontSize: 11, fontWeight: '700', letterSpacing: 0.5 },
  stepActive: { color: colors.brand, fontSize: 11, fontWeight: '800', letterSpacing: 0.5 },
});
