-- migrate:up
-- Compatibility fields for the child notification thumbnail query. media_url is
-- derived from the canonical media_path so there is only one writable source of
-- truth; thumbnail_url remains optional for future generated thumbnails.
ALTER TABLE posts
  ADD COLUMN IF NOT EXISTS media_url TEXT GENERATED ALWAYS AS (media_path) STORED;
ALTER TABLE posts
  ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;

-- Creation routes already use the Python PII scanner. Keep edits fail-closed at
-- the database boundary too so a later caption-edit endpoint cannot add obvious
-- phone/email/contact information after the original moderation pass.
CREATE OR REPLACE FUNCTION littlenet_caption_contact_guard()
RETURNS TRIGGER AS $$
DECLARE
  text_value TEXT := COALESCE(NEW.caption, '');
BEGIN
  IF text_value ~* '[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}'
     OR text_value ~ '(^|[^0-9])([0-9][^0-9]*){10,15}([^0-9]|$)'
     OR text_value ~* '(whatsapp|telegram|snapchat|instagram)[[:space:]:@_-]+[A-Z0-9._-]{3,}'
  THEN
    RAISE EXCEPTION 'caption_contact_sharing_blocked' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_littlenet_caption_contact_guard ON posts;
CREATE TRIGGER trg_littlenet_caption_contact_guard
BEFORE INSERT OR UPDATE OF caption ON posts
FOR EACH ROW EXECUTE FUNCTION littlenet_caption_contact_guard();

-- migrate:down
DROP TRIGGER IF EXISTS trg_littlenet_caption_contact_guard ON posts;
DROP FUNCTION IF EXISTS littlenet_caption_contact_guard();
ALTER TABLE posts DROP COLUMN IF EXISTS thumbnail_url;
ALTER TABLE posts DROP COLUMN IF EXISTS media_url;
