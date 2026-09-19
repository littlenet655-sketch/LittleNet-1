import * as ImagePicker from 'expo-image-picker';
import { captureLivePhotoCore } from './capture';
import type { CameraDeps, CapturedPhoto } from './capture';

export * from './capture';

const expoDeps: CameraDeps = {
  getPermissions: async () => {
    const res = await ImagePicker.getCameraPermissionsAsync();
    return { granted: res.granted, canAskAgain: res.canAskAgain };
  },
  requestPermissions: async () => {
    const res = await ImagePicker.requestCameraPermissionsAsync();
    return { granted: res.granted, canAskAgain: res.canAskAgain };
  },
  launchCamera: async () => {
    // System camera only. Gallery selection is never offered for
    // guardian liveness, face enrollment, or face login.
    const result = await ImagePicker.launchCameraAsync({
      base64: true,
      quality: 0.6,
      allowsEditing: false,
      exif: false,
    });
    if (result.canceled) return { cancelled: true };
    const asset = result.assets?.[0];
    return { cancelled: false, base64: asset?.base64 ?? undefined, width: asset?.width, height: asset?.height, uri: asset?.uri };
  },
};

/** Single live camera capture for face/liveness steps. */
export async function captureLivePhoto(): Promise<CapturedPhoto> {
  return captureLivePhotoCore(expoDeps);
}
