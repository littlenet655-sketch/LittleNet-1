import { ApiError, parseErrorResponse, retryDelayMs, shouldRetryRequest } from './errors';

export { ApiError };
export * from './errors';

export function apiBaseUrl(): string {
  return (process.env.EXPO_PUBLIC_API_BASE_URL ?? '').replace(/\/+$/, '');
}

/** Kept for components that only need to know whether a backend is configured. */
export const API_BASE_URL = process.env.EXPO_PUBLIC_API_BASE_URL ?? '';

export const REQUEST_TIMEOUT_MS = 15000;

/** Prefer /api/mobile/v2 where a v2 route exists; keep v1 only where no v2 exists. */
export const routes = {
  health: '/api/mobile/v1/health',
  login: '/api/mobile/v1/auth/login',
  logout: '/api/mobile/v1/auth/logout',
  faceLogin: '/api/mobile/v1/auth/face-login',
  me: '/api/mobile/v1/me',
  parentRegister: '/api/mobile/v1/auth/parent/register',
  parentVerifyEmail: '/api/mobile/v1/auth/parent/verify-email',
  parentResendEmail: '/api/mobile/v1/auth/parent/resend-email',
  parentVerifyLiveness: '/api/mobile/v1/auth/parent/verify-liveness',
  forgotPassword: '/api/mobile/v1/auth/forgot-password',
  resetPassword: '/api/mobile/v1/auth/reset-password',
  childFaceEnroll: '/api/mobile/v1/kids/face/enroll',
  quiz: '/api/mobile/v1/kids/quiz',
  quizAnswer: (quizId: number) => `/api/mobile/v1/kids/quiz/${quizId}/answer`,
  parentCreateChild: '/api/mobile/v1/parent/children',
  parentDashboard: '/api/mobile/v1/parent/dashboard',
  // v2 media pipeline (Agent C owns the posting UI; routes stay centralized here).
  feedV2: '/api/mobile/v2/kids/feed',
  reelsV2: '/api/mobile/v2/kids/reels',
  discoverV2: '/api/mobile/v2/kids/discover',
  uploadSession: '/api/mobile/v2/uploads/session',
  uploadComplete: (uploadId: string) => `/api/mobile/v2/uploads/${encodeURIComponent(uploadId)}/complete`,
  processingStatus: (postId: number) => `/api/mobile/v2/posts/${postId}/processing-status`,
} as const;

type UnauthorizedHandler = () => void;
let unauthorizedHandler: UnauthorizedHandler | null = null;

/** Centralized 401 handling: AuthProvider registers LOCAL invalidation here (never a network call). */
export function setUnauthorizedHandler(handler: UnauthorizedHandler | null): void {
  unauthorizedHandler = handler;
}

let suppressUnauthorizedDepth = 0;

/**
 * Runs fn with the centralized 401 handler suppressed. Used exactly once per
 * user-initiated sign-out so an expired token on /logout cannot recurse.
 */
export async function withoutUnauthorizedHandler<T>(fn: () => Promise<T>): Promise<T> {
  suppressUnauthorizedDepth += 1;
  try {
    return await fn();
  } finally {
    suppressUnauthorizedDepth -= 1;
  }
}

export interface RequestOptions extends RequestInit {
  timeoutMs?: number;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function apiRequest<T>(path: string, options: RequestOptions = {}, token?: string): Promise<T> {
  const baseUrl = apiBaseUrl();
  if (!baseUrl) {
    throw new ApiError(0, 'misconfigured', 'The app is not pointed at a LittleNet backend.');
  }
  const method = (options.method ?? 'GET').toUpperCase();
  const timeoutMs = options.timeoutMs ?? REQUEST_TIMEOUT_MS;

  let attempt = 0;
  for (;;) {
    if (options.signal?.aborted) {
      throw parseErrorResponse(0, { error: 'request_cancelled' });
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    const onCallerAbort = (): void => controller.abort();
    // Caller abort and timeout share one controller: either aborts the request.
    options.signal?.addEventListener('abort', onCallerAbort, { once: true });
    try {
      const headers = new Headers(options.headers);
      headers.set('Accept', 'application/json');
      if (token) headers.set('Authorization', `Bearer ${token}`);
      const body = options.body;
      if (body && !(body instanceof FormData) && !headers.has('Content-Type')) {
        headers.set('Content-Type', 'application/json');
      }
      const response = await fetch(`${baseUrl}${path}`, { ...options, headers, signal: controller.signal });
      const payload: unknown = await response.json().catch(() => ({}));
      if (!response.ok) {
        const err = parseErrorResponse(response.status, payload);
        if (response.status === 401 && suppressUnauthorizedDepth === 0) unauthorizedHandler?.();
        if (shouldRetryRequest(method, attempt, response.status)) {
          attempt += 1;
          await sleep(retryDelayMs(attempt));
          continue;
        }
        throw err;
      }
      return payload as T;
    } catch (error) {
      if (error instanceof ApiError) throw error;
      if (options.signal?.aborted) {
        // Caller cancellation is intentional: never retry, never misreport.
        throw parseErrorResponse(0, { error: 'request_cancelled' });
      }
      const aborted = error instanceof DOMException && error.name === 'AbortError';
      const networkError = parseErrorResponse(0, { error: aborted ? 'request_timeout' : 'network_unreachable' });
      if (shouldRetryRequest(method, attempt, 0)) {
        attempt += 1;
        await sleep(retryDelayMs(attempt));
        continue;
      }
      throw networkError;
    } finally {
      clearTimeout(timer);
      options.signal?.removeEventListener('abort', onCallerAbort);
    }
  }
}
