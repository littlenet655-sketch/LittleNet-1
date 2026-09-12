export const API_BASE_URL = (process.env.EXPO_PUBLIC_API_BASE_URL ?? '').replace(/\/+$/, '');

export class ApiError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
    this.name = 'ApiError';
  }
}

export const routes = {
  health: '/api/mobile/v1/health',
  login: '/api/mobile/v1/auth/login',
  feed: '/api/mobile/v2/kids/feed',
  reels: '/api/mobile/v2/kids/reels',
  discover: '/api/mobile/v2/kids/discover',
  uploadSession: '/api/mobile/v2/uploads/session',
  uploadComplete: (uploadId: string) => `/api/mobile/v2/uploads/${encodeURIComponent(uploadId)}/complete`,
  processingStatus: (postId: number) => `/api/mobile/v2/posts/${postId}/processing-status`,
} as const;

export async function apiRequest<T>(
  path: string,
  options: RequestInit = {},
  token?: string,
): Promise<T> {
  if (!API_BASE_URL) {
    throw new ApiError(0, 'EXPO_PUBLIC_API_BASE_URL is not configured');
  }
  const headers = new Headers(options.headers);
  headers.set('Accept', 'application/json');
  if (token) headers.set('Authorization', `Bearer ${token}`);
  if (options.body && !(options.body instanceof FormData) && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }
  const response = await fetch(`${API_BASE_URL}${path}`, { ...options, headers });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = typeof payload?.error === 'string' ? payload.error : `Request failed (${response.status})`;
    throw new ApiError(response.status, message);
  }
  return payload as T;
}
