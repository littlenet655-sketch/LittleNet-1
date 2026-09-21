import { useEffect, useRef, useState } from 'react';
import { useCameraPermissions } from 'expo-camera';
import { AppState, Linking, Platform, StyleSheet, Text, View } from 'react-native';
import type { AppStateStatus } from 'react-native';
import NetInfo from '@react-native-community/netinfo';
import { Feather } from '@expo/vector-icons';
import { ApiError } from '../api/client';
import { CameraBlockedError, CameraPermissionError } from './capture';
import type { CapturedPhoto } from './capture';
import {
  cleanupTempFrame,
  detectFacesOrThrow,
  evaluateLivenessFrame,
  FacePrecheckError,
  precheckFace,
  type FaceChallengeAction,
  type LivenessProgress,
  type LivenessStage,
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

/** Live-scan cadence: low-res temp frames analyzed by on-device ML Kit. */
const SCAN_INTERVAL_MS = 250;
/** Give up the automatic scan after this long and let the user retry manually. */
const SCAN_TIMEOUT_MS = 60_000;
/** Consecutive native detector failures before the scanner is declared dead. */
const MAX_CONSECUTIVE_DETECTOR_FAILURES = 3;

function canRetrySubmission(error: unknown): boolean {
  return error instanceof ApiError && (error.status === 0 || error.status >= 500);
}

function initialLiveness(action: FaceChallengeAction): LivenessProgress {
  return {
    action,
    step: 1,
    statusText: 'Scanning for face…',
    detailText: 'Center your face inside the oval',
    isAligned: false,
    isComplete: false,
    ovalColor: '#94A3B8',
    stage: 'WAITING_FOR_OPEN',
  };
}

function defaultInstructionFor(action: FaceChallengeAction): string {
  switch (action) {
    case 'TURN_LEFT':
      return 'Auto-scanning active with Google ML Kit. Position your face in the oval and turn your head left when prompted.';
    case 'TURN_RIGHT':
      return 'Auto-scanning active with Google ML Kit. Position your face in the oval and turn your head right when prompted.';
    case 'SMILE':
      return 'Auto-scanning active with Google ML Kit. Position your face in the oval and smile when prompted.';
    case 'BLINK':
    default:
      return 'Auto-scanning active with Google ML Kit. Position your face in the oval and blink naturally when prompted.';
  }
}

function stepTwoLabel(action: FaceChallengeAction): string {
  switch (action) {
    case 'TURN_LEFT':
    case 'TURN_RIGHT':
      return '2 Turn Check';
    case 'SMILE':
      return '2 Smile Check';
    case 'BLINK':
    default:
      return '2 Blink Check';
  }
}

function overlayIcon(liveness: LivenessProgress): 'check-circle' | 'eye' | 'smile' | 'rotate-ccw' | 'user-check' | 'user' {
  if (liveness.isComplete) return 'check-circle';
  switch (liveness.stage) {
    case 'WAITING_FOR_BLINK':
    case 'WAITING_FOR_REOPEN':
      return 'eye';
    case 'WAITING_FOR_SMILE':
      return 'smile';
    case 'WAITING_FOR_TURN':
    case 'WAITING_FOR_RETURN':
      return 'rotate-ccw';
    default:
      return liveness.isAligned ? 'user-check' : 'user';
  }
}

/**
 * Real-time biometric face scanner with Google ML Kit.
 * Automatically scans the face, checks alignment & liveness challenge,
 * and auto-captures upon confirmation without requiring manual screen taps.
 *
 * Challenge lifecycle guarantees:
 * - verified liveness stops the live detector before ONE final selfie capture;
 * - a failed attempt always requires a fresh challenge (no selfie/state reuse);
 * - backgrounding, unmount, detector outage, and scan timeout all reset the
 *   challenge instead of leaving stale callbacks or a stuck VERIFIED state.
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
  const [appState, setAppState] = useState<AppStateStatus>('active');
  const [scannerDead, setScannerDead] = useState(false);
  const [scanTimedOut, setScanTimedOut] = useState(false);

  const [liveness, setLiveness] = useState<LivenessProgress>(() => initialLiveness(livenessAction));

  const loading = busy || working;
  const isScanningRef = useRef(false);
  const autoCapturedRef = useRef(false);
  const blinkStageRef = useRef<LivenessStage>('WAITING_FOR_OPEN');
  /** Bumped on every reset/effect restart; async scan ticks drop stale results. */
  const generationRef = useRef(0);
  /** Synchronous re-entrancy guard: exactly one capture at a time. */
  const captureInFlightRef = useRef(false);
  const mountedRef = useRef(true);
  const scanStartRef = useRef(0);
  const detectorFailuresRef = useRef(0);
  const errorTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  function resetLivenessState() {
    generationRef.current += 1;
    blinkStageRef.current = 'WAITING_FOR_OPEN';
    autoCapturedRef.current = false;
    scanStartRef.current = 0;
    detectorFailuresRef.current = 0;
    setLiveness(initialLiveness(livenessAction));
  }

  /** Full scanner recovery: clears dead/timed-out flags and starts a fresh challenge. */
  function restartScan() {
    setScannerDead(false);
    setScanTimedOut(false);
    setError(null);
    resetLivenessState();
  }

  // Track mount so async continuations never setState after unmount, and so
  // the delayed post-failure reset timer is always cleaned up.
  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      if (errorTimerRef.current) {
        clearTimeout(errorTimerRef.current);
        errorTimerRef.current = null;
      }
    };
  }, []);

  // A challenge must not span an app backgrounding: the camera is suspended
  // and any in-flight challenge state is untrustworthy. Reset on background.
  useEffect(() => {
    if (Platform.OS === 'web') return;
    setAppState(AppState.currentState);
    const subscription = AppState.addEventListener('change', (nextState) => {
      setAppState(nextState);
      if (nextState !== 'active') {
        resetLivenessState();
      }
    });
    return () => subscription.remove();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // A new server-issued challenge action invalidates any in-progress scan.
  useEffect(() => {
    resetLivenessState();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [livenessAction]);

  async function submit(photo: CapturedPhoto) {
    const network = await NetInfo.fetch();
    if (network.isConnected === false) {
      throw new ApiError(0, 'verification_offline', 'Internet is required to complete verification.');
    }
    await onCapture(photo);
    setPendingPhoto(null);
  }

  async function capture(autoVerified = false) {
    if (!cameraRef.current || !cameraReady || working || captureInFlightRef.current) return;
    captureInFlightRef.current = true;
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
      if (!mountedRef.current) return;
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
      if (!mountedRef.current) return;
      // Only transient failures keep the locally checked photo for an offline
      // retry. Any rejection discards it: the next attempt captures fresh.
      setPendingPhoto(capturedPhoto && canRetrySubmission(err) ? capturedPhoto : null);
      setError(err);
      if (errorTimerRef.current) {
        clearTimeout(errorTimerRef.current);
      }
      errorTimerRef.current = setTimeout(() => {
        errorTimerRef.current = null;
        // A failed attempt must require a fresh local challenge instead of
        // reusing the previous VERIFIED state on the next automatic scan.
        if (mountedRef.current) resetLivenessState();
      }, 1200);
    } finally {
      captureInFlightRef.current = false;
      if (mountedRef.current) setWorking(false);
    }
  }

  // Automatic Google ML Kit face scanner & liveness loop.
  // Temp frames are low-res throwaway JPEGs deleted right after analysis;
  // only the final verified selfie is kept at capture quality.
  useEffect(() => {
    if (
      Platform.OS === 'web' ||
      autoScan === false ||
      !cameraReady ||
      working ||
      busy ||
      pendingPhoto !== null ||
      autoCapturedRef.current ||
      scannerDead ||
      scanTimedOut ||
      appState !== 'active'
    ) {
      return;
    }

    let isSubscribed = true;
    if (scanStartRef.current === 0) {
      scanStartRef.current = Date.now();
    }
    generationRef.current += 1;
    const generation = generationRef.current;

    const interval = setInterval(async () => {
      if (!isSubscribed || isScanningRef.current || working || busy || autoCapturedRef.current) {
        return;
      }
      if (generation !== generationRef.current) return;
      if (Date.now() - scanStartRef.current > SCAN_TIMEOUT_MS) {
        if (isSubscribed && generation === generationRef.current) {
          setScanTimedOut(true);
        }
        return;
      }
      if (!cameraRef.current) return;

      isScanningRef.current = true;
      let tempUri: string | undefined;
      try {
        const frame = await cameraRef.current.takePictureAsync({
          quality: 0.15,
          skipProcessing: true,
          shutterSound: false,
        });

        if (!isSubscribed || generation !== generationRef.current) return;
        tempUri = frame?.uri;
        if (!tempUri) return;

        let faces;
        try {
          faces = await detectFacesOrThrow(tempUri);
        } catch {
          // Native detector outage: surface it instead of pretending the
          // frame simply had no face.
          detectorFailuresRef.current += 1;
          if (
            detectorFailuresRef.current >= MAX_CONSECUTIVE_DETECTOR_FAILURES &&
            isSubscribed &&
            generation === generationRef.current
          ) {
            setScannerDead(true);
            setError(
              new FacePrecheckError(
                'native_unavailable',
                'The on-device face check is unavailable. Rebuild the Android app before continuing.',
              ),
            );
          }
          return;
        }
        detectorFailuresRef.current = 0;

        if (!isSubscribed || generation !== generationRef.current) return;

        const progress = evaluateLivenessFrame(
          { width: frame.width, height: frame.height },
          faces,
          livenessAction,
          blinkStageRef.current,
        );

        blinkStageRef.current = progress.stage;
        setLiveness(progress);

        // Once liveness is verified the live detector stops (gated by
        // autoCapturedRef + effect teardown) and exactly one final selfie
        // is captured and independently validated before submission.
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
    }, SCAN_INTERVAL_MS);

    return () => {
      isSubscribed = false;
      clearInterval(interval);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cameraReady, working, busy, pendingPhoto, autoScan, livenessAction, appState, scannerDead, scanTimedOut]);

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
      if (mountedRef.current) setWorking(false);
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

  // Scanner is unavailable (dead native module or timed-out scan): offer a
  // manual capture fallback backed by the full still-photo precheck.
  const manualFallback = scannerDead || scanTimedOut;

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
            <Feather name={overlayIcon(liveness)} size={13} color={liveness.ovalColor} />
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
            {stepTwoLabel(livenessAction)}
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

      <Notice tone="info" message={instruction ?? defaultInstructionFor(livenessAction)} />

      {scanTimedOut ? (
        <Notice tone="info" message="The face scan timed out. Make sure your face is well lit and centered, then restart the scan." />
      ) : null}

      {error ? <Notice message={errorText(error)} /> : null}

      {pendingPhoto && canRetrySubmission(error) ? (
        <>
          <Notice tone="info" message="Your checked photo is saved on this device. Reconnect to finish verification." />
          <Button label={loading ? 'Retrying…' : 'Retry verification'} onPress={() => void retrySubmission()} loading={loading} disabled={loading} />
          <Button
            label="Take a new photo"
            variant="secondary"
            onPress={() => {
              setPendingPhoto(null);
              setError(null);
              resetLivenessState();
            }}
            disabled={loading}
          />
        </>
      ) : (
        <>
          {manualFallback ? (
            <Button label="Restart auto-scan" variant="secondary" onPress={restartScan} disabled={loading} />
          ) : null}
          <Button
            label={loading ? (busyLabel ?? 'Checking…') : liveness.isComplete ? 'Liveness Verified! Submitting…' : label}
            onPress={() => void capture(autoScan && liveness.isComplete && !manualFallback)}
            loading={loading}
            disabled={loading || !cameraReady || (autoScan && !liveness.isComplete && !manualFallback)}
          />
        </>
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
