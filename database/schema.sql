-- LittleNet complete PostgreSQL schema. Safe to run on a fresh database.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
 user_id SERIAL PRIMARY KEY,
 username VARCHAR(50) UNIQUE NOT NULL,
 full_name VARCHAR(100) NOT NULL,
 email VARCHAR(150) UNIQUE NOT NULL,
 password_hash TEXT NOT NULL,
 role VARCHAR(20) NOT NULL CHECK (role IN ('CHILD','PARENT','ADMIN')),
 age INTEGER CHECK (age IS NULL OR age BETWEEN 4 AND 18),
 dob DATE,
 account_status VARCHAR(30) NOT NULL DEFAULT 'PENDING_APPROVAL' CHECK (account_status IN ('PENDING_APPROVAL','ACTIVE','REJECTED','SUSPENDED')),
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS parent_child_map (
 map_id SERIAL PRIMARY KEY, child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 parent_id INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
 parent_name VARCHAR(100) NOT NULL, parent_email VARCHAR(150) NOT NULL,
 approval_token UUID UNIQUE, approved BOOLEAN NOT NULL DEFAULT FALSE, approved_at TIMESTAMP,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(child_id,parent_email)
);
CREATE TABLE IF NOT EXISTS login_activity (
 login_id BIGSERIAL PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 login_method VARCHAR(20) NOT NULL DEFAULT 'PASSWORD', success BOOLEAN NOT NULL DEFAULT TRUE,
 ip_address VARCHAR(100), device_info TEXT, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS activity_logs (
 log_id BIGSERIAL PRIMARY KEY, child_id INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
 activity_type VARCHAR(80) NOT NULL, activity_data JSONB NOT NULL DEFAULT '{}'::jsonb,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS child_profiles (
 profile_id SERIAL PRIMARY KEY, child_id INTEGER UNIQUE NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 parent_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL, full_name VARCHAR(150) NOT NULL,
 date_of_birth DATE, age INTEGER, school_name VARCHAR(200), location VARCHAR(200), current_class VARCHAR(50), bio TEXT,
 profile_picture VARCHAR(500), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS child_skills (skill_id SERIAL PRIMARY KEY, child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, skill_name VARCHAR(100) NOT NULL, approved BOOLEAN NOT NULL DEFAULT FALSE);
CREATE TABLE IF NOT EXISTS child_interests (interest_id SERIAL PRIMARY KEY, child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, interest_name VARCHAR(100) NOT NULL, approved BOOLEAN NOT NULL DEFAULT FALSE);
CREATE TABLE IF NOT EXISTS child_ambitions (ambition_id SERIAL PRIMARY KEY, child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, ambition_name VARCHAR(100) NOT NULL, approved BOOLEAN NOT NULL DEFAULT FALSE);

CREATE TABLE IF NOT EXISTS posts (
 post_id BIGSERIAL PRIMARY KEY, child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 media_type VARCHAR(20) NOT NULL CHECK (media_type IN ('IMAGE','VIDEO','AUDIO','TEXT')),
 media_path VARCHAR(500), story_music_path VARCHAR(500), caption TEXT, content_category VARCHAR(100) DEFAULT 'Other', audience_age_group VARCHAR(10) NOT NULL DEFAULT 'ALL' CHECK(audience_age_group IN ('ALL','6-8','9-11','12-13','14-18')), is_story BOOLEAN NOT NULL DEFAULT FALSE,
 is_reel BOOLEAN NOT NULL DEFAULT FALSE, safety_score NUMERIC(6,2) DEFAULT 0, adult_score NUMERIC(6,2) DEFAULT 0,
 violence_score NUMERIC(6,2) DEFAULT 0, weapon_score NUMERIC(6,2) DEFAULT 0, toxicity_score NUMERIC(6,2) DEFAULT 0,
 is_safe BOOLEAN NOT NULL DEFAULT FALSE, moderation_status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (moderation_status IN ('PENDING','ALLOWED','REVIEW','BLOCKED')),
 moderation_reason TEXT, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS deleted_posts (
 deleted_post_id BIGSERIAL PRIMARY KEY, original_post_id BIGINT, child_id INTEGER, media_type VARCHAR(20), media_path VARCHAR(500), story_music_path VARCHAR(500), caption TEXT, content_category VARCHAR(100), deleted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS likes (
 like_id BIGSERIAL PRIMARY KEY, post_id BIGINT NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
 child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, UNIQUE(post_id,child_id)
);
CREATE TABLE IF NOT EXISTS comments (
 comment_id BIGSERIAL PRIMARY KEY, post_id BIGINT NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
 child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, comment_text TEXT NOT NULL,
 moderation_status VARCHAR(20) NOT NULL DEFAULT 'ALLOWED' CHECK (moderation_status IN ('PENDING','ALLOWED','REVIEW','BLOCKED')),
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS followers (
 follower_id BIGSERIAL PRIMARY KEY, child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 following_child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, approved BOOLEAN NOT NULL DEFAULT FALSE,
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, UNIQUE(child_id,following_child_id), CHECK(child_id<>following_child_id)
);
CREATE TABLE IF NOT EXISTS saved_posts (
 saved_id BIGSERIAL PRIMARY KEY, child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 post_id BIGINT NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(child_id,post_id)
);

CREATE TABLE IF NOT EXISTS story_views (
 story_view_id BIGSERIAL PRIMARY KEY, post_id BIGINT NOT NULL REFERENCES posts(post_id) ON DELETE CASCADE,
 child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, viewed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, UNIQUE(post_id,child_id)
);

CREATE TABLE IF NOT EXISTS child_conversations (
 conversation_id BIGSERIAL PRIMARY KEY, child1_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 child2_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(child1_id,child2_id), CHECK(child1_id<child2_id)
);
CREATE TABLE IF NOT EXISTS child_messages (
 child_message_id BIGSERIAL PRIMARY KEY, conversation_id BIGINT NOT NULL REFERENCES child_conversations(conversation_id) ON DELETE CASCADE,
 sender_child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, receiver_child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 message_type VARCHAR(20) NOT NULL DEFAULT 'TEXT' CHECK(message_type IN ('TEXT','IMAGE','VIDEO','VOICE','FILE','SHARED_POST')),
 message_text TEXT, media_path VARCHAR(500), shared_post_id BIGINT REFERENCES posts(post_id) ON DELETE SET NULL,
 moderation_status VARCHAR(20) NOT NULL DEFAULT 'ALLOWED' CHECK(moderation_status IN ('PENDING','ALLOWED','REVIEW','BLOCKED')),
 is_deleted BOOLEAN NOT NULL DEFAULT FALSE, is_seen BOOLEAN NOT NULL DEFAULT FALSE, delivered_at TIMESTAMP, seen_at TIMESTAMP,
 sent_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, CHECK(sender_child_id<>receiver_child_id)
);
CREATE TABLE IF NOT EXISTS blocked_users (
 block_id BIGSERIAL PRIMARY KEY, blocker_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 blocked_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(blocker_id,blocked_id), CHECK(blocker_id<>blocked_id)
);
CREATE TABLE IF NOT EXISTS muted_users (
 mute_id BIGSERIAL PRIMARY KEY, muter_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 muted_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
 UNIQUE(muter_id,muted_id), CHECK(muter_id<>muted_id)
);
CREATE TABLE IF NOT EXISTS reports (
 report_id BIGSERIAL PRIMARY KEY, reporter_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 target_type VARCHAR(20) NOT NULL CHECK(target_type IN ('USER','POST','COMMENT','MESSAGE')), target_id BIGINT NOT NULL,
 reason VARCHAR(100) NOT NULL, details TEXT, status VARCHAR(20) NOT NULL DEFAULT 'OPEN' CHECK(status IN ('OPEN','REVIEWING','RESOLVED','DISMISSED')),
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS notifications (
 notification_id BIGSERIAL PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 actor_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL, notification_type VARCHAR(50) NOT NULL,
 message TEXT NOT NULL, target_url VARCHAR(500), is_read BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS parent_notifications (
 notification_id BIGSERIAL PRIMARY KEY, parent_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, notification_type VARCHAR(50) NOT NULL,
 notification_message TEXT NOT NULL, target_url VARCHAR(500), is_read BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS child_time_limits (
 child_id INTEGER PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE, daily_limit_minutes INTEGER NOT NULL DEFAULT 60 CHECK(daily_limit_minutes BETWEEN 1 AND 1440),
 strict_mode BOOLEAN NOT NULL DEFAULT FALSE, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS child_usage_sessions (
 usage_session_id BIGSERIAL PRIMARY KEY, child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 session_key UUID NOT NULL DEFAULT gen_random_uuid(), started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 last_seen_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, ended_at TIMESTAMP, UNIQUE(session_key)
);
CREATE TABLE IF NOT EXISTS child_usage_logs (
 usage_log_id BIGSERIAL PRIMARY KEY, child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 usage_date DATE NOT NULL DEFAULT CURRENT_DATE, login_time TIMESTAMP NOT NULL, logout_time TIMESTAMP,
 duration_minutes INTEGER NOT NULL DEFAULT 0 CHECK(duration_minutes>=0)
);
CREATE TABLE IF NOT EXISTS parent_safety_settings (
 child_id INTEGER PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
 parent_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 safety_level VARCHAR(20) NOT NULL DEFAULT 'STRICT' CHECK(safety_level IN ('STANDARD','STRICT','VERY_STRICT')),
 updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

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
CREATE TABLE IF NOT EXISTS user_preferences (
 user_id INTEGER PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
 preferred_language VARCHAR(5) NOT NULL DEFAULT 'EN' CHECK(preferred_language IN ('EN','KN','HI')),
 updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS quizzes (
 quiz_id SERIAL PRIMARY KEY, category VARCHAR(100) NOT NULL, question TEXT NOT NULL,
 option_a VARCHAR(255) NOT NULL, option_b VARCHAR(255) NOT NULL, option_c VARCHAR(255) NOT NULL, option_d VARCHAR(255) NOT NULL,
 correct_answer VARCHAR(255) NOT NULL, age_group VARCHAR(10) NOT NULL CHECK(age_group IN ('6-8','9-11','12-13')), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS parent_quiz_settings (
 setting_id SERIAL PRIMARY KEY, parent_id INTEGER REFERENCES users(user_id) ON DELETE CASCADE, child_id INTEGER UNIQUE NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 quiz_frequency INTEGER NOT NULL DEFAULT 5 CHECK(quiz_frequency BETWEEN 1 AND 50), mandatory_quiz BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS child_quiz_progress (
 progress_id SERIAL PRIMARY KEY, child_id INTEGER UNIQUE NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, posts_seen INTEGER NOT NULL DEFAULT 0, last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS child_quiz_attempts (
 attempt_id BIGSERIAL PRIMARY KEY, child_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, quiz_id INTEGER NOT NULL REFERENCES quizzes(quiz_id) ON DELETE CASCADE,
 selected_answer VARCHAR(255) NOT NULL, is_correct BOOLEAN NOT NULL, attempted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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

CREATE TABLE IF NOT EXISTS face_profiles (
 face_profile_id BIGSERIAL PRIMARY KEY, child_id INTEGER UNIQUE NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 embedding JSONB NOT NULL, model_name VARCHAR(50) NOT NULL DEFAULT 'Facenet512', reference_path VARCHAR(500), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS face_login_attempts (
 attempt_id BIGSERIAL PRIMARY KEY, child_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
 success BOOLEAN NOT NULL, liveness_passed BOOLEAN, distance NUMERIC(8,5), reason VARCHAR(100), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS moderation_events (
 event_id BIGSERIAL PRIMARY KEY, child_id INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
 content_type VARCHAR(30) NOT NULL, content_id BIGINT, risk_score NUMERIC(6,2) NOT NULL DEFAULT 0,
 adult_score NUMERIC(6,2) NOT NULL DEFAULT 0, violence_score NUMERIC(6,2) NOT NULL DEFAULT 0, weapon_score NUMERIC(6,2) NOT NULL DEFAULT 0, toxicity_score NUMERIC(6,2) NOT NULL DEFAULT 0,
 decision VARCHAR(20) NOT NULL CHECK(decision IN ('ALLOW','REVIEW','BLOCK')), reason TEXT,
 signals JSONB NOT NULL DEFAULT '{}'::jsonb, status VARCHAR(20) NOT NULL DEFAULT 'OPEN' CHECK(status IN ('OPEN','RESOLVED')),
 created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS moderation_reviews (
 review_id BIGSERIAL PRIMARY KEY, event_id BIGINT UNIQUE NOT NULL REFERENCES moderation_events(event_id) ON DELETE CASCADE,
 reviewer_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE, action VARCHAR(20) NOT NULL CHECK(action IN ('APPROVE','BLOCK')),
 notes TEXT, reviewed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_posts_feed ON posts(moderation_status,is_story,is_reel,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_child ON posts(child_id,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON child_messages(conversation_id,sent_at);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id,is_read,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_parent_notifications ON parent_notifications(parent_id,is_read,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_moderation_review ON moderation_events(decision,status,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_child_date ON child_usage_logs(child_id,usage_date);


CREATE TABLE IF NOT EXISTS admin_audit_logs (
 audit_id BIGSERIAL PRIMARY KEY,
 admin_id INTEGER NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
 action VARCHAR(80) NOT NULL,
 target_type VARCHAR(40),
 target_id BIGINT,
 details JSONB NOT NULL DEFAULT '{}'::jsonb,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_admin_audit_created ON admin_audit_logs(created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_quizzes_question_age_unique ON quizzes(question,age_group);
