import { useState } from 'react';
import { Linking } from 'react-native';
import { CameraBlockedError, CameraCancelledError, captureLivePhoto } from './livePhoto';
import type { CapturedPhoto } from './livePhoto';
import { Button, Notice, errorText } from '../ui/components';

interface CameraCaptureProps {
  label: string;
  busyLabel?: string;
  busy?: boolean;
  /** Receives the live photo. Throw to surface API errors in place. */
  onCapture: (photo: CapturedPhoto) => void | Promise<void>;
}

/**
 * Shared camera step for guardian liveness, face enrollment, and face login.
 * Distinguishes askable denial, permanent denial (with Open Settings),
 * cancellation, and launch failure. Never offers gallery selection.
 */
export function CameraCapture({ label, busyLabel, busy = false, onCapture }: CameraCaptureProps) {
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<unknown>(null);

  async function run() {
    setWorking(true);
    setError(null);
    try {
      const photo = await captureLivePhoto();
      await onCapture(photo);
    } catch (err) {
      setError(err);
    } finally {
      setWorking(false);
    }
  }

  const blocked = error instanceof CameraBlockedError;
  const cancelled = error instanceof CameraCancelledError;
  const loading = busy || working;

  return (
    <>
      {cancelled ? <Notice tone="info" message={errorText(error)} /> : null}
      {error && !cancelled ? <Notice message={errorText(error)} /> : null}
      {blocked ? (
        <Button label="Open Settings" variant="secondary" onPress={() => void Linking.openSettings()} />
      ) : null}
      <Button label={loading ? (busyLabel ?? 'Working…') : label} onPress={run} loading={loading} disabled={loading} />
    </>
  );
}
