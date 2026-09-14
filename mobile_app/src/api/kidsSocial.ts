/** Kids social mutations API (Agent C). */
import { apiRequest, routes } from './client';

export interface PostDetail {
  post_id: number;
  child_id: number;
  full_name?: string;
  username?: string;
  avatar_url?: string | null;
  media_url?: string | null;
  poster_url?: string | null;
  caption?: string;
  content_category?: string;
  media_type?: string;
  likes?: number;
  comments_count?: number;
  created_at?: string;
  is_reel?: boolean;
  viewer_liked?: boolean;
  viewer_saved?: boolean;
}

export interface CommentItem {
  comment_id: number;
  post_id: number;
  child_id: number;
  comment_text: string;
  created_at?: string;
  full_name?: string;
  username?: string;
  avatar_url?: string | null;
}

export interface ReportItem {
  report_id: number;
  target_type: string;
  target_id: number;
  reason: string;
  details?: string;
  status: string;
  created_at?: string;
}

async function get<T>(path: string, token: string): Promise<T> {
  return apiRequest<T>(path, {}, token);
}

async function postJson<T>(path: string, body: Record<string, unknown>, token: string): Promise<T> {
  return apiRequest<T>(path, { method: 'POST', body: JSON.stringify(body) }, token);
}

export function fetchPostDetail(token: string, postId: number): Promise<{ ok: boolean; post: PostDetail; comments: CommentItem[] }> {
  return get(routes.postDetail(postId), token);
}

export function toggleLike(token: string, postId: number): Promise<{ ok: boolean; liked: boolean; likes: number }> {
  return postJson(routes.like(postId), {}, token);
}

export function toggleSave(token: string, postId: number): Promise<{ ok: boolean; saved: boolean }> {
  return postJson(routes.save(postId), {}, token);
}

export function fetchComments(token: string, postId: number): Promise<{ ok: boolean; comments: CommentItem[] }> {
  return get(routes.comments(postId), token);
}

export function addComment(token: string, postId: number, text: string): Promise<{ ok: boolean; status: string; comment_id: number }> {
  return postJson(routes.addComment(postId), { text }, token);
}

export function fetchSaved(token: string): Promise<{ ok: boolean; posts: PostDetail[]; reels: PostDetail[] }> {
  return get(routes.saved, token);
}

export function toggleFollow(token: string, childId: number): Promise<{ ok: boolean; status: string }> {
  return postJson(routes.follow(childId), {}, token);
}

export function profileAction(token: string, targetId: number, action: string): Promise<{ ok: boolean; action: string }> {
  return postJson(routes.profileActions(targetId), { action }, token);
}

export function blockUser(token: string, targetId: number, action: string): Promise<{ ok: boolean; blocked: boolean }> {
  return postJson(routes.block(targetId), { action }, token);
}

export function muteUser(token: string, targetId: number, action: string): Promise<{ ok: boolean; muted: boolean }> {
  return postJson(routes.mute(targetId), { action }, token);
}

export function submitReport(token: string, targetType: string, targetId: number, reason: string): Promise<{ ok: boolean }> {
  return postJson(routes.report, { target_type: targetType, target_id: targetId, reason, details: '' }, token);
}

export function fetchReports(token: string): Promise<{ ok: boolean; reports: ReportItem[] }> {
  return get(routes.reports, token);
}

export function fetchConnections(token: string): Promise<{ ok: boolean; followers: unknown[]; following: unknown[]; suggested: unknown[] }> {
  return get(routes.connections, token);
}
