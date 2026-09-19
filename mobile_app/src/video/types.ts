export type PlaybackState =
  | 'IDLE'
  | 'PREPARING'
  | 'READY'
  | 'PLAYING'
  | 'PAUSED'
  | 'BUFFERING'
  | 'ENDED'
  | 'ERROR';

export type PlaybackPolicy = 'NORMAL' | 'DATA_SAVER';

export interface ReelMetrics {
  source_type: 'SOCIAL' | 'CURATED';
  source_id: number;
  session_id?: string;
  surface: 'REELS' | 'FEED';
  watched_ms: number;
  completed: boolean;
  replay_count: number;
  liked?: boolean;
  saved?: boolean;
  ttff_ms?: number;
  rebuffer_count?: number;
  total_rebuffer_ms?: number;
  error_type?: string | null;
  credential_refreshes?: number;
}

export interface ImpressionEventPayload {
  session_id?: string;
  source_type: string;
  source_id: number;
  surface: string;
  watched_ms?: number;
  completed?: boolean;
  liked?: boolean;
  saved?: boolean;
  replay_count?: number;
}
