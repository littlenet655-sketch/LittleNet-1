-- Step 6: convert one-parent follows into a two-parent friendship handshake.
-- Existing approved demo relationships are preserved as ACTIVE and mirrored so
-- friendship remains symmetric after the migration.

ALTER TABLE followers ADD COLUMN IF NOT EXISTS approval_stage VARCHAR(32) NOT NULL DEFAULT 'REQUESTED';
ALTER TABLE followers ADD COLUMN IF NOT EXISTS sender_parent_approved_at TIMESTAMP;
ALTER TABLE followers ADD COLUMN IF NOT EXISTS receiver_parent_approved_at TIMESTAMP;

DO $$ BEGIN
  ALTER TABLE followers ADD CONSTRAINT followers_approval_stage_check
    CHECK (approval_stage IN ('REQUESTED','SENDER_PARENT_APPROVED','RECEIVER_PARENT_PENDING','ACTIVE'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Any relationship that was already approved before Step 6 is grandfathered as
-- a fully active friendship. This avoids locking out existing demo/test accounts.
UPDATE followers
SET approval_stage='ACTIVE',
    sender_parent_approved_at=COALESCE(sender_parent_approved_at,created_at),
    receiver_parent_approved_at=COALESCE(receiver_parent_approved_at,created_at)
WHERE approved=TRUE;

-- Mirror existing active friendships so all feed/story/count queries are symmetric.
INSERT INTO followers(child_id,following_child_id,approved,approval_stage,sender_parent_approved_at,receiver_parent_approved_at,created_at)
SELECT following_child_id,child_id,TRUE,'ACTIVE',
       COALESCE(sender_parent_approved_at,created_at),
       COALESCE(receiver_parent_approved_at,created_at),created_at
FROM followers f
WHERE f.approved=TRUE
ON CONFLICT(child_id,following_child_id) DO UPDATE
SET approved=TRUE,
    approval_stage='ACTIVE',
    sender_parent_approved_at=COALESCE(followers.sender_parent_approved_at,EXCLUDED.sender_parent_approved_at),
    receiver_parent_approved_at=COALESCE(followers.receiver_parent_approved_at,EXCLUDED.receiver_parent_approved_at);

CREATE OR REPLACE FUNCTION littlenet_two_parent_friendship_update()
RETURNS TRIGGER AS $$
DECLARE
  reverse_row followers%ROWTYPE;
  requester_name TEXT;
BEGIN
  -- Legacy Parent Mode writes approved=TRUE. Intercept that write and turn the
  -- first approval into the sender-parent stage rather than an active friendship.
  IF OLD.approved=FALSE AND NEW.approved=TRUE THEN
    IF OLD.approval_stage='REQUESTED' THEN
      NEW.approved=FALSE;
      NEW.approval_stage='SENDER_PARENT_APPROVED';
      NEW.sender_parent_approved_at=COALESCE(NEW.sender_parent_approved_at,NOW());

      INSERT INTO followers(
        child_id,following_child_id,approved,approval_stage,
        sender_parent_approved_at,created_at
      ) VALUES(
        OLD.following_child_id,OLD.child_id,FALSE,'RECEIVER_PARENT_PENDING',
        NEW.sender_parent_approved_at,OLD.created_at
      )
      ON CONFLICT(child_id,following_child_id) DO UPDATE
      SET approved=FALSE,
          approval_stage='RECEIVER_PARENT_PENDING',
          sender_parent_approved_at=COALESCE(followers.sender_parent_approved_at,EXCLUDED.sender_parent_approved_at)
      WHERE followers.approved=FALSE;

      SELECT full_name INTO requester_name FROM users WHERE user_id=OLD.child_id;
      INSERT INTO parent_notifications(parent_id,child_id,notification_type,notification_message,target_url)
      SELECT DISTINCT pcm.parent_id,OLD.following_child_id,'INCOMING_FRIEND_REQUEST',
             COALESCE(requester_name,'A LittleNet child') || ' wants to become friends with your child. Approve in Parent Mode.',
             '/parent/follow-requests/'
      FROM parent_child_map pcm
      WHERE pcm.child_id=OLD.following_child_id AND pcm.parent_id IS NOT NULL;

      RETURN NEW;
    ELSIF OLD.approval_stage='RECEIVER_PARENT_PENDING' THEN
      -- The target child's parent is approving the reciprocal pending row.
      NEW.approved=TRUE;
      NEW.approval_stage='ACTIVE';
      NEW.receiver_parent_approved_at=COALESCE(NEW.receiver_parent_approved_at,NOW());

      UPDATE followers
      SET approved=TRUE,
          approval_stage='ACTIVE',
          receiver_parent_approved_at=NEW.receiver_parent_approved_at
      WHERE child_id=OLD.following_child_id
        AND following_child_id=OLD.child_id
        AND approval_stage='SENDER_PARENT_APPROVED'
        AND approved=FALSE;

      INSERT INTO notifications(user_id,actor_id,notification_type,message,target_url)
      VALUES
        (OLD.child_id,OLD.following_child_id,'FRIENDSHIP_ACTIVE','Your parent-approved friendship is now active.','/notifications/'),
        (OLD.following_child_id,OLD.child_id,'FRIENDSHIP_ACTIVE','Your parent-approved friendship is now active.','/notifications/');

      RETURN NEW;
    ELSIF OLD.approval_stage='SENDER_PARENT_APPROVED' THEN
      -- Internal reverse-row activation from the receiver-parent approval.
      NEW.approval_stage='ACTIVE';
      NEW.receiver_parent_approved_at=COALESCE(NEW.receiver_parent_approved_at,NOW());
      RETURN NEW;
    END IF;
  END IF;

  -- Never permit a non-ACTIVE row to become approved through an unexpected path.
  IF NEW.approved=TRUE AND NEW.approval_stage<>'ACTIVE' THEN
    NEW.approved=FALSE;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_littlenet_two_parent_friendship_update ON followers;
CREATE TRIGGER trg_littlenet_two_parent_friendship_update
BEFORE UPDATE OF approved ON followers
FOR EACH ROW EXECUTE FUNCTION littlenet_two_parent_friendship_update();

CREATE OR REPLACE FUNCTION littlenet_friendship_delete_pair()
RETURNS TRIGGER AS $$
BEGIN
  -- A pending cancellation/rejection or an active unfriend removes the paired row
  -- too, keeping the friendship state symmetric. The nested delete sees no reverse
  -- row after the first deletion and therefore terminates naturally.
  DELETE FROM followers
  WHERE child_id=OLD.following_child_id
    AND following_child_id=OLD.child_id;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_littlenet_friendship_delete_pair ON followers;
CREATE TRIGGER trg_littlenet_friendship_delete_pair
AFTER DELETE ON followers
FOR EACH ROW EXECUTE FUNCTION littlenet_friendship_delete_pair();

CREATE INDEX IF NOT EXISTS idx_followers_active_pair
  ON followers(child_id,following_child_id)
  WHERE approved=TRUE AND approval_stage='ACTIVE';
CREATE INDEX IF NOT EXISTS idx_followers_parent_stage
  ON followers(approval_stage,child_id,following_child_id)
  WHERE approved=FALSE;