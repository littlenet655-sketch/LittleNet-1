/** Kids v2 upload pipeline API (Agent C). Direct R2 PUT, never JSON media. */
import { apiRequest, routes } from './client';

async function postJson<T>(path: string, body: Record<string, unknown>, token: string): Promise<T> {
  return apiRequest<T>(path, { method: 'POST', body: JSON.stringify(body) }, token);
}

export interface UploadSession {
  ok: boolean;
  upload_id: string;
  upload_url: string;
  object_key: string;
  expires_at: string;
  required_headers: Record<string, string>;
}

export function requestUploadSession(token: string, input: { kind: string; filename: string; mediaType: string; sizeBytes: number; mimeType: string }): Promise<UploadSession> {
  return postJson<UploadSession>(routes.uploadSession, {
    kind: input.kind,
    filename: input.filename,
    media_type: input.mediaType,
    size_bytes: input.sizeBytes,
    mime_type: input.mimeType,
  }, token);
}

export function completeUpload(token: string, uploadId: string, input: { caption: string; contentCategory: string; tags: string[]; locationName?: string }): Promise<{ ok: boolean; post_id: number; status: string }> {
  return postJson(routes.uploadComplete(uploadId), {
    caption: input.caption,
    content_category: input.contentCategory,
    tags: input.tags,
    location_name: input.locationName ?? '',
  }, token);
}

export interface ProcessingStatus {
  ok: boolean;
  post_id: number;
  status: string;
  stage: string;
  moderation_status?: string | null;
  is_safe?: boolean;
  media_url?: string | null;
  poster_url?: string | null;
  error?: string | null;
  retryable?: boolean;
}

export function fetchProcessingStatus(token: string, postId: number): Promise<ProcessingStatus> {
  return apiRequest<ProcessingStatus>(routes.processingStatus(postId), {}, token);
}

export function redriveProcessing(token: string, postId: number): Promise<{ ok: boolean }> {
  return postJson(routes.redrive(postId), {}, token);
}
