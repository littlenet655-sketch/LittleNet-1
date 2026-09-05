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

-- XP table for quiz rewards
CREATE TABLE IF NOT EXISTS child_xp (
  child_id  INTEGER PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
  xp        INTEGER NOT NULL DEFAULT 0 CHECK(xp >= 0),
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- Track quiz source (AI-generated vs curated)
ALTER TABLE quizzes ADD COLUMN IF NOT EXISTS source VARCHAR(10) NOT NULL DEFAULT 'SEED';

-- Parent verification and approval extensions
ALTER TABLE parent_child_map ADD COLUMN IF NOT EXISTS verification_token VARCHAR(255);
ALTER TABLE parent_child_map ADD COLUMN IF NOT EXISTS approval_status VARCHAR(64) DEFAULT 'PENDING_APPROVAL';
ALTER TABLE parent_child_map ADD COLUMN IF NOT EXISTS is_token_used BOOLEAN DEFAULT FALSE;
ALTER TABLE parent_child_map ADD COLUMN IF NOT EXISTS parent_verified BOOLEAN DEFAULT FALSE;
ALTER TABLE parent_child_map ADD COLUMN IF NOT EXISTS parent_masked_id VARCHAR(64);
ALTER TABLE parent_child_map ADD COLUMN IF NOT EXISTS parent_id_type VARCHAR(64);
ALTER TABLE parent_child_map ADD COLUMN IF NOT EXISTS verified_parent_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL;
ALTER TABLE parent_child_map ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP;
ALTER TABLE parent_child_map ADD COLUMN IF NOT EXISTS approval_token_expires_at TIMESTAMP;


CREATE TABLE IF NOT EXISTS parent_verifications (
    verification_id SERIAL PRIMARY KEY,
    parent_user_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    child_id INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    verification_provider VARCHAR(64) DEFAULT 'MOCK_CIVIC_ID',
    verification_status VARCHAR(64) DEFAULT 'PENDING',
    liveness_status VARCHAR(64),
    face_match_status VARCHAR(64),
    document_type VARCHAR(64),
    masked_id VARCHAR(64),
    consent_given BOOLEAN DEFAULT FALSE,
    consent_timestamp TIMESTAMP,
    verification_meta JSONB DEFAULT '{}'::jsonb,
    verified_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
ALTER TABLE parent_verifications ADD COLUMN IF NOT EXISTS child_id INTEGER REFERENCES users(user_id) ON DELETE CASCADE;
ALTER TABLE parent_verifications ADD COLUMN IF NOT EXISTS verification_provider VARCHAR(64) DEFAULT 'MOCK_CIVIC_ID';
ALTER TABLE parent_verifications ADD COLUMN IF NOT EXISTS document_type VARCHAR(64);
ALTER TABLE parent_verifications ADD COLUMN IF NOT EXISTS consent_given BOOLEAN DEFAULT FALSE;
ALTER TABLE parent_verifications ADD COLUMN IF NOT EXISTS consent_timestamp TIMESTAMP;
ALTER TABLE parent_verifications ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP;




-- Missing column that process_child_decision() writes to when a parent
-- declines a pending child registration.
ALTER TABLE parent_child_map ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- Feed-performance indexes: visible_posts()/active_stories() run several
-- correlated subqueries per row (like/comment counts, follow/block/mute
-- checks, skill/interest/ambition matches). These are needed once real
-- content (~1000+ posts) is loaded, not just for the current empty/demo DB.
CREATE INDEX IF NOT EXISTS idx_likes_post ON likes(post_id);
CREATE INDEX IF NOT EXISTS idx_comments_post ON comments(post_id) WHERE moderation_status='ALLOWED';
CREATE INDEX IF NOT EXISTS idx_followers_child_approved ON followers(child_id,following_child_id) WHERE approved=TRUE;
CREATE INDEX IF NOT EXISTS idx_blocked_blocker ON blocked_users(blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocked_blocked ON blocked_users(blocked_id);
CREATE INDEX IF NOT EXISTS idx_muted_muter ON muted_users(muter_id);
CREATE INDEX IF NOT EXISTS idx_child_skills_child_approved ON child_skills(child_id) WHERE approved=TRUE;
CREATE INDEX IF NOT EXISTS idx_child_interests_child_approved ON child_interests(child_id) WHERE approved=TRUE;
CREATE INDEX IF NOT EXISTS idx_child_ambitions_child_approved ON child_ambitions(child_id) WHERE approved=TRUE;
CREATE INDEX IF NOT EXISTS idx_saved_posts_child ON saved_posts(child_id);
CREATE INDEX IF NOT EXISTS idx_story_views_post_child ON story_views(post_id,child_id);

-- AI & Safety Intelligence Extensions (K2-Horizon & Enhanced Learning)
ALTER TABLE moderation_events ADD COLUMN IF NOT EXISTS pii_detected BOOLEAN DEFAULT FALSE;
ALTER TABLE moderation_events ADD COLUMN IF NOT EXISTS grooming_risk_score NUMERIC(6,2) DEFAULT 0.0;
ALTER TABLE moderation_events ADD COLUMN IF NOT EXISTS ai_model VARCHAR(50);

ALTER TABLE quizzes ADD COLUMN IF NOT EXISTS question_type VARCHAR(30) DEFAULT 'MULTIPLE_CHOICE';
ALTER TABLE quizzes ADD COLUMN IF NOT EXISTS difficulty_level VARCHAR(20) DEFAULT 'MEDIUM';
ALTER TABLE quizzes ADD COLUMN IF NOT EXISTS sub_topic VARCHAR(100);
ALTER TABLE quizzes ADD COLUMN IF NOT EXISTS explanation TEXT;
ALTER TABLE quizzes ADD COLUMN IF NOT EXISTS language VARCHAR(10) DEFAULT 'en';
ALTER TABLE quizzes ADD COLUMN IF NOT EXISTS vocabulary_word VARCHAR(100);
ALTER TABLE quizzes ADD COLUMN IF NOT EXISTS native_script VARCHAR(100);
ALTER TABLE quizzes ADD COLUMN IF NOT EXISTS pronunciation_hint VARCHAR(100);

ALTER TABLE child_profiles ADD COLUMN IF NOT EXISTS grade_level VARCHAR(30) DEFAULT 'Grade 4';
ALTER TABLE child_profiles ADD COLUMN IF NOT EXISTS preferred_language VARCHAR(20) DEFAULT 'en';
ALTER TABLE child_profiles ADD COLUMN IF NOT EXISTS learning_languages TEXT[] DEFAULT ARRAY['kn', 'hi'];

CREATE TABLE IF NOT EXISTS child_personalized_quiz_pool (
  pool_id SERIAL PRIMARY KEY,
  child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  quiz_id INTEGER NOT NULL REFERENCES quizzes(quiz_id) ON DELETE CASCADE,
  reason_for_selection VARCHAR(100),
  served BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(child_id, quiz_id)
);
CREATE INDEX IF NOT EXISTS idx_child_pool_unserved ON child_personalized_quiz_pool(child_id) WHERE served=FALSE;

CREATE TABLE IF NOT EXISTS child_vocabulary_progress (
  progress_id SERIAL PRIMARY KEY,
  child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  word VARCHAR(100) NOT NULL,
  language VARCHAR(20) NOT NULL,
  times_seen INTEGER DEFAULT 1,
  times_correct INTEGER DEFAULT 0,
  last_tested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  next_review_due TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  mastery_level VARCHAR(20) DEFAULT 'LEARNING',
  UNIQUE(child_id, word, language)
);

CREATE TABLE IF NOT EXISTS parent_weekly_digests (
  digest_id SERIAL PRIMARY KEY,
  child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  parent_id INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
  week_start_date DATE NOT NULL,
  headline VARCHAR(255),
  digest_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_parent_digests_child ON parent_weekly_digests(child_id, week_start_date DESC);
