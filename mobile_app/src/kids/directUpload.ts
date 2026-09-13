import { File, UploadType } from 'expo-file-system';

/** Native binary upload to the v2 presigned URL; media never enters JS memory. */
export async function putFileToSignedUrl(uploadUrl: string, localUri: string, headers: Record<string, string>): Promise<void> {
  const result = await new File(localUri).upload(uploadUrl, {
    httpMethod: 'PUT',
    uploadType: UploadType.BINARY_CONTENT,
    headers,
  });
  if (result.status < 200 || result.status >= 300) {
    throw new Error(`Upload failed (${result.status}). Check connection and try again.`);
  }
}
