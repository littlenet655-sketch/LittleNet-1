import { File, UploadType } from 'expo-file-system';

/** Native binary upload to the v2 presigned URL; media never enters JS memory. */
export async function putFileToSignedUrl(uploadUrl: string, localUri: string, headers: Record<string, string>): Promise<void> {
  let result;
  try {
    result = await new File(localUri).upload(uploadUrl, {
      httpMethod: 'PUT',
      uploadType: UploadType.BINARY_CONTENT,
      headers,
    });
  } catch (error) {
    const detail = error instanceof Error && error.message ? ` (${error.message})` : '';
    throw new Error(`Cloudflare upload could not start. Keep the file selected and try again${detail}.`);
  }
  if (result.status < 200 || result.status >= 300) {
    throw new Error(`Cloudflare rejected the upload (status ${result.status}). Keep the file selected and try again.`);
  }
}
