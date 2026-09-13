import * as ImagePicker from 'expo-image-picker';

export interface CapturedPhoto {
  base64: string;
  width: number;
  height: number;
}

/**
 * Single live camera capture for face/liveness steps. Uses the system camera
 * (never the gallery) so every enrollment/login/liveness attempt is fresh.
 */
export async function captureLivePhoto(): Promise<CapturedPhoto> {
  const permission = await ImagePicker.requestCameraPermissionsAsync();
  if (!permission.granted) {
    throw new Error('Camera access is needed for this safety check. Allow the camera and try again.');
  }
  const result = await ImagePicker.launchCameraAsync({
    base64: true,
    quality: 0.6,
    allowsEditing: false,
    exif: false,
  });
  if (result.canceled) {
    throw new Error('Photo was cancelled. Take a live photo to continue.');
  }
  const asset = result.assets[0];
  if (!asset?.base64) {
    throw new Error('Could not read the camera photo. Please try again.');
  }
  return { base64: asset.base64, width: asset.width, height: asset.height };
}
