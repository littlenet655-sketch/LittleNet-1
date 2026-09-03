-- Idempotent upgrades for LittleNet databases created by earlier project stages.
ALTER TABLE posts ADD COLUMN IF NOT EXISTS audience_age_group VARCHAR(10) NOT NULL DEFAULT 'ALL';
DO $$ BEGIN
  ALTER TABLE posts ADD CONSTRAINT posts_audience_age_group_check CHECK(audience_age_group IN ('ALL','6-8','9-11','12-13','14-18'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS parent_control_settings (
 child_id INTEGER PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
 parent_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 allow_reels BOOLEAN NOT NULL DEFAULT TRUE,
 allow_stories BOOLEAN NOT NULL DEFAULT TRUE,
 allow_messaging BOOLEAN NOT NULL DEFAULT TRUE,
 allow_posting BOOLEAN NOT NULL DEFAULT TRUE,
 allow_discover BOOLEAN NOT NULL DEFAULT TRUE,
 quiet_hours_enabled BOOLEAN NOT NULL DEFAULT FALSE,
 quiet_start TIME NOT NULL DEFAULT '21:00',
 quiet_end TIME NOT NULL DEFAULT '07:00',
 educational_only_feed BOOLEAN NOT NULL DEFAULT FALSE,
 allowed_categories JSONB NOT NULL DEFAULT '["Other","Science","Math","Art","Sports","Music","Technology","Education","Nature","Books","Coding","General Knowledge"]'::jsonb,
 updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE parent_control_settings ADD COLUMN IF NOT EXISTS quiet_hours_enabled BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE parent_control_settings ADD COLUMN IF NOT EXISTS quiet_start TIME NOT NULL DEFAULT '21:00';
ALTER TABLE parent_control_settings ADD COLUMN IF NOT EXISTS quiet_end TIME NOT NULL DEFAULT '07:00';
CREATE TABLE IF NOT EXISTS user_preferences (
 user_id INTEGER PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
 preferred_language VARCHAR(5) NOT NULL DEFAULT 'EN' CHECK(preferred_language IN ('EN','KN','HI')),
 updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS learning_challenges (
 challenge_id SERIAL PRIMARY KEY, title VARCHAR(150) NOT NULL, description TEXT NOT NULL,
 challenge_type VARCHAR(20) NOT NULL CHECK(challenge_type IN ('PUZZLE','ACTIVITY','CYBER_SAFETY')),
 prompt TEXT, expected_answer VARCHAR(255), age_group VARCHAR(10) NOT NULL CHECK(age_group IN ('6-8','9-11','12-13','14-18')),
 points INTEGER NOT NULL DEFAULT 10 CHECK(points BETWEEN 1 AND 100), active BOOLEAN NOT NULL DEFAULT TRUE,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS learning_challenge_attempts (
 attempt_id BIGSERIAL PRIMARY KEY, child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 challenge_id INTEGER NOT NULL REFERENCES learning_challenges(challenge_id) ON DELETE CASCADE,
 response TEXT, completed BOOLEAN NOT NULL DEFAULT TRUE, points_awarded INTEGER NOT NULL DEFAULT 0,
 completed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, UNIQUE(child_id,challenge_id)
);
