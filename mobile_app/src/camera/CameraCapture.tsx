import { useEffect, useRef, useState } from 'react';
import { useCameraPermissions } from 'expo-camera';
import { Linking, Platform, StyleSheet, Text, View } from 'react-native';
import NetInfo from '@react-native-community/netinfo';
import { Feather } from '@expo/vector-icons';
import { ApiError } from '../api/client';
import { CameraBlockedError, CameraPermissionError } from './capture';
import type { CapturedPhoto } from './capture';
import {
  cleanupTempFrame,
  detectFacesInImage,
  evaluateLivenessFrame,
  precheckFace,
  type BlinkStage,
  type FaceChallengeAction,
  type LivenessProgress,
} from './facePrecheck';
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
  livenessAction?: FaceChallengeAction;
  autoScan?: boolean;
}

function canRetrySubmission(error: unknown): boolean {
  return error instanceof ApiError && (error.status === 0 || error.status >= 500);
}

/**
 * Real-time biometric face scanner with Google ML Kit.
 * Automatically scans the face, checks alignment & eye blink liveness,
 * and auto-captures upon confirmation without requiring manual screen taps.
 */
export function CameraCapture({
  label,
  busyLabel,
  busy = false,
  onCapture,
  validatePhoto,
  instruction,
  livenessAction = 'BLINK',
  autoScan = true,
}: CameraCaptureProps) {
  const cameraRef = useRef<React.ElementRef<typeof NativeCameraView>>(null);
  const [permission, requestPermission] = useCameraPermissions();
  const [working, setWorking] = useState(false);
  const [cameraReady, setCameraReady] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [pendingPhoto, setPendingPhoto] = useState<CapturedPhoto | null>(null);

  const [liveness, setLiveness] = useState<LivenessProgress>({
    action: livenessAction,
    step: 1,
    statusText: 'Scanning for face…',
    detailText: 'Center your face inside the oval',
    isAligned: false,
    isComplete: false,
    ovalColor: '#94A3B8',
    stage: 'WAITING_FOR_OPEN',
  });

  const loading = busy || working;
  const isScanningRef = useRef(false);
  const autoCapturedRef = useRef(false);
  const blinkStageRef = useRef<BlinkStage>('WAITING_FOR_OPEN');

  async function submit(photo: CapturedPhoto) {
    const network = await NetInfo.fetch();
    if (network.isConnected === false) {
      throw new ApiError(0, 'verification_offline', 'Internet is required to complete verification.');
    }
    await onCapture(photo);
    setPendingPhoto(null);
  }

  async function capture(autoVerified = false) {
    if (!cameraRef.current || !cameraReady || working) return;
    setWorking(true);
    setError(null);
    let capturedPhoto: CapturedPhoto | null = null;
    try {
      const shot = await cameraRef.current.takePictureAsync({
        base64: true,
        exif: false,
        quality: 0.45,
        shutterSound: false,
      });
      if (!shot?.base64) throw new Error('Could not read the camera photo. Please try again.');
      capturedPhoto = {
        base64: shot.base64,
        width: shot.width,
        height: shot.height,
        uri: shot.uri,
        ...(autoVerified ? { livenessVerified: true } : {}),
      };
      if (validatePhoto) await validatePhoto(capturedPhoto);
      else await precheckFace(capturedPhoto);
      await submit(capturedPhoto);
    } catch (err) {
      setPendingPhoto(capturedPhoto && canRetrySubmission(err) ? capturedPhoto : null);
      setError(err);
      if (typeof setTimeout !== 'undefined') {
        setTimeout(() => {
          autoCapturedRef.current = false;
        }, 3000);
      } else {
        autoCapturedRef.current = false;
      }
    } finally {
      setWorking(false);
    }
  }

  // Automatic Google ML Kit face scanner & liveness loop
  useEffect(() => {
    if (
      Platform.OS === 'web' ||
      autoScan === false ||
      !cameraReady ||
      working ||
      busy ||
      pendingPhoto !== null ||
      autoCapturedRef.current
    ) {
      return;
    }

    let isSubscribed = true;
    const interval = setInterval(async () => {
      if (!isSubscribed || isScanningRef.current || working || busy || autoCapturedRef.current) {
        return;
      }
      if (!cameraRef.current) return;

      isScanningRef.current = true;
      let tempUri: string | undefined;
      try {
        const frame = await cameraRef.current.takePictureAsync({
          quality: 0.25,
          skipProcessing: true,
          shutterSound: false,
        });

        tempUri = frame?.uri;
        if (!isSubscribed || !tempUri) return;

        const faces = await detectFacesInImage(tempUri);
        if (!isSubscribed) return;

        const progress = evaluateLivenessFrame(
          { width: frame.width, height: frame.height },
          faces,
          livenessAction,
          blinkStageRef.current,
        );

        blinkStageRef.current = progress.stage;
        setLiveness(progress);

        // Once liveness verified, trigger automatic high-res capture
        if (progress.isComplete && !autoCapturedRef.current) {
          autoCapturedRef.current = true;
          await capture(true);
        }
      } catch {
        // Non-fatal streaming analysis error
      } finally {
        if (tempUri) {
          void cleanupTempFrame(tempUri);
        }
        isScanningRef.current = false;
      }
    }, 450);

    return () => {
      isSubscribed = false;
      clearInterval(interval);
    };
  }, [cameraReady, working, busy, pendingPhoto, autoScan, livenessAction]);

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
          {/* Top real-time detection badge */}
          <View style={[styles.statusBadge, { borderColor: liveness.ovalColor }]}>
            <View style={[styles.statusPulseDot, { backgroundColor: liveness.ovalColor }]} />
            <Text style={styles.statusBadgeText}>{liveness.statusText.toUpperCase()}</Text>
          </View>

          {/* Biometric reticle oval */}
          <View
            style={[
              styles.faceOval,
              {
                borderColor: liveness.ovalColor,
                backgroundColor: liveness.isComplete
                  ? 'rgba(16, 185, 129, 0.12)'
                  : liveness.isAligned
                    ? 'rgba(56, 189, 248, 0.08)'
                    : 'rgba(0, 0, 0, 0.25)',
              },
            ]}
          >
            {/* Corner reticles for high-tech scanning feel */}
            <View style={[styles.reticleCorner, styles.reticleTopLeft, { borderColor: liveness.ovalColor }]} />
            <View style={[styles.reticleCorner, styles.reticleTopRight, { borderColor: liveness.ovalColor }]} />
            <View style={[styles.reticleCorner, styles.reticleBottomLeft, { borderColor: liveness.ovalColor }]} />
            <View style={[styles.reticleCorner, styles.reticleBottomRight, { borderColor: liveness.ovalColor }]} />
          </View>

          {/* Floating guidance pill at bottom */}
          <View style={styles.guidancePill}>
            <Feather
              name={
                liveness.isComplete
                  ? 'check-circle'
                  : liveness.stage === 'WAITING_FOR_BLINK' || liveness.stage === 'WAITING_FOR_REOPEN'
                    ? 'eye'
                    : liveness.isAligned
                      ? 'user-check'
                      : 'user'
              }
              size={13}
              color={liveness.ovalColor}
            />
            <Text style={styles.guidanceText}>{liveness.detailText}</Text>
          </View>
        </View>
      </View>

      {/* Real-time 3-step biometric tracker */}
      <View style={styles.steps}>
        <View style={styles.stepItem}>
          <Feather
            name={liveness.step > 1 ? 'check-circle' : 'search'}
            size={12}
            color={liveness.step > 1 ? '#10B981' : liveness.step === 1 ? colors.brand : colors.muted}
          />
          <Text style={liveness.step === 1 ? styles.stepActive : liveness.step > 1 ? styles.stepDone : styles.step}>
            1 Scan Face
          </Text>
        </View>
        <View style={styles.stepDivider} />
        <View style={styles.stepItem}>
          <Feather
            name={liveness.step > 2 ? 'check-circle' : 'eye'}
            size={12}
            color={liveness.step > 2 ? '#10B981' : liveness.step === 2 ? colors.brand : colors.muted}
          />
          <Text style={liveness.step === 2 ? styles.stepActive : liveness.step > 2 ? styles.stepDone : styles.step}>
            2 Blink Check
          </Text>
        </View>
        <View style={styles.stepDivider} />
        <View style={styles.stepItem}>
          <Feather
            name={liveness.isComplete ? 'check-circle' : 'shield'}
            size={12}
            color={liveness.isComplete ? '#10B981' : colors.muted}
          />
          <Text style={liveness.step === 3 ? styles.stepActive : styles.step}>
            3 Verified
          </Text>
        </View>
      </View>

      <Notice
        tone="info"
        message={
          instruction ??
          'Auto-scanning active with Google ML Kit. Position your face in the oval and blink naturally when prompted.'
        }
      />

      {error ? <Notice message={errorText(error)} /> : null}

      {pendingPhoto && canRetrySubmission(error) ? (
        <>
          <Notice tone="info" message="Your checked photo is saved on this device. Reconnect to finish verification." />
          <Button label={loading ? 'Retrying…' : 'Retry verification'} onPress={() => void retrySubmission()} loading={loading} disabled={loading} />
          <Button label="Take a new photo" variant="secondary" onPress={() => { setPendingPhoto(null); setError(null); }} disabled={loading} />
        </>
      ) : (
        <Button
          label={loading ? (busyLabel ?? 'Checking…') : liveness.isComplete ? 'Liveness Verified! Submitting…' : label}
          onPress={() => void capture(false)}
          loading={loading}
          disabled={loading || !cameraReady}
        />
      )}
    </>
  );
}

const styles = StyleSheet.create({
  cameraFrame: {
    height: 350,
    overflow: 'hidden',
    borderRadius: 20,
    backgroundColor: '#0B0F19',
    position: 'relative',
    borderWidth: 1.5,
    borderColor: '#1E293B',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 6 },
    shadowOpacity: 0.15,
    shadowRadius: 12,
    elevation: 4,
  },
  camera: { flex: 1 },
  overlay: {
    ...StyleSheet.absoluteFill,
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: spacing.md,
  },
  statusBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: 'rgba(15, 23, 42, 0.85)',
    paddingHorizontal: 12,
    paddingVertical: 5,
    borderRadius: radius.pill,
    borderWidth: 1,
  },
  statusPulseDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
  },
  statusBadgeText: {
    color: '#F8FAFC',
    fontSize: 10,
    fontWeight: '800',
    letterSpacing: 0.5,
  },
  faceOval: {
    width: 195,
    height: 250,
    borderRadius: 125,
    borderWidth: 2.5,
    position: 'relative',
  },
  reticleCorner: {
    position: 'absolute',
    width: 18,
    height: 18,
  },
  reticleTopLeft: {
    top: 25,
    left: 15,
    borderTopWidth: 2.5,
    borderLeftWidth: 2.5,
  },
  reticleTopRight: {
    top: 25,
    right: 15,
    borderTopWidth: 2.5,
    borderRightWidth: 2.5,
  },
  reticleBottomLeft: {
    bottom: 25,
    left: 15,
    borderBottomWidth: 2.5,
    borderLeftWidth: 2.5,
  },
  reticleBottomRight: {
    bottom: 25,
    right: 15,
    borderBottomWidth: 2.5,
    borderRightWidth: 2.5,
  },
  guidancePill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: 'rgba(15, 23, 42, 0.88)',
    paddingHorizontal: 14,
    paddingVertical: 7,
    borderRadius: radius.pill,
    borderWidth: 1,
    borderColor: '#334155',
    maxWidth: '90%',
  },
  guidanceText: {
    color: '#F1F5F9',
    fontSize: 12,
    fontWeight: '700',
  },
  steps: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 10,
    paddingHorizontal: 16,
    backgroundColor: '#F8FAFC',
    borderRadius: 14,
    marginVertical: spacing.xs,
    borderWidth: 1,
    borderColor: '#E2E8F0',
  },
  stepItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
  },
  stepDivider: {
    width: 14,
    height: 1,
    backgroundColor: '#CBD5E1',
  },
  step: { color: '#64748B', fontSize: 11, fontWeight: '700' },
  stepActive: { color: colors.brand, fontSize: 11, fontWeight: '800' },
  stepDone: { color: '#059669', fontSize: 11, fontWeight: '800' },
});
