/** Kids feed/discover API (Agent C). Maps to mobile/api.py v2 routes. */
import { apiRequest, routes } from './client';

export interface FeedItem {
  source_type: 'SOCIAL' | 'CURATED';
  source_id: number;
  post_id: number;
  full_name?: string;
  avatar_url?: string | null;
  media_type?: string;
  media_url?: string | null;
  poster_url?: string | null;
  playback_expires_at?: number | null;
  title?: string;
  caption?: string;
  content_category?: string;
  likes?: number;
  comments_count?: number;
  created_at?: string;
  child_id?: number;
  is_reel?: boolean;
  moderation_status?: string;
  is_safe?: boolean;
  viewer_liked?: boolean;
  viewer_saved?: boolean;
}

export interface StoryItem {
  post_id: number;
  full_name?: string;
  avatar_url?: string | null;
  media_type?: string;
  media_url?: string | null;
  poster_url?: string | null;
  caption?: string;
}

export interface FeedPage {
  ok: boolean;
  items: FeedItem[];
  next_cursor: number;
  has_more: boolean;
  session_id: string;
}

async function get<T>(path: string, token: string, signal?: AbortSignal): Promise<T> {
  return apiRequest<T>(path, signal ? { signal } : {}, token);
}

export function fetchFeedV2(token: string, cursor: number, limit = 10, sessionId?: string, signal?: AbortSignal): Promise<FeedPage> {
  const p = new URLSearchParams({ cursor: String(cursor), limit: String(limit) });
  if (sessionId) p.set('session_id', sessionId);
  return get<FeedPage>(`${routes.feedV2}?${p.toString()}`, token, signal);
}

export function fetchReelsV2(token: string, cursor: number, limit = 10, sessionId?: string, signal?: AbortSignal): Promise<FeedPage> {
  const p = new URLSearchParams({ cursor: String(cursor), limit: String(limit) });
  if (sessionId) p.set('session_id', sessionId);
  return get<FeedPage>(`${routes.reelsV2}?${p.toString()}`, token, signal);
}

export function fetchKidsHome(token: string): Promise<{ ok: boolean; stories: StoryItem[] }> {
  return get(routes.kidsHome, token);
}
