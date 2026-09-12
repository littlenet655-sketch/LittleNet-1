-- migrate:up
-- LittleNet P0: Upload State Machine and Face Authentication Hardening

-- 1. Ensure no invalid or empty face embeddings exist before applying constraint
DELETE FROM face_profiles
WHERE embedding IS NULL
   OR jsonb_typeof(embedding) != 'array'
   OR jsonb_array_length(embedding) < 128;

-- 2. Enforce fail-closed child face profile embedding constraint (must be array with >= 128 dimensions)
ALTER TABLE face_profiles DROP CONSTRAINT IF EXISTS face_profiles_embedding_valid_check;
ALTER TABLE face_profiles ADD CONSTRAINT face_profiles_embedding_valid_check
  CHECK (jsonb_typeof(embedding) = 'array' AND jsonb_array_length(embedding) >= 128);

-- 3. Enforce uniqueness on posts.source_media_path to eliminate duplicate post creation race condition
-- First deduplicate any pre-existing historical duplicates by preserving the latest post and appending post_id suffix
WITH ranked_dups AS (
  SELECT post_id, source_media_path,
         ROW_NUMBER() OVER (PARTITION BY source_media_path ORDER BY post_id DESC) as rn
  FROM posts
  WHERE source_media_path IS NOT NULL
)
UPDATE posts p
SET source_media_path = p.source_media_path || '-dup-' || p.post_id
FROM ranked_dups r
WHERE p.post_id = r.post_id AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_posts_source_media_path_uniq
  ON posts (source_media_path)
  WHERE source_media_path IS NOT NULL;

-- migrate:down
DROP INDEX IF EXISTS idx_posts_source_media_path_uniq;
ALTER TABLE face_profiles DROP CONSTRAINT IF EXISTS face_profiles_embedding_valid_check;

