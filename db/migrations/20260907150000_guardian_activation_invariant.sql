-- migrate:up
-- Defense in depth: HTTP routes already require verified guardian liveness, but
-- the database must also reject a future/legacy path that tries to activate a
-- pending child or approve its mapping directly.
CREATE OR REPLACE FUNCTION littlenet_guardian_verified_for_child(target_child INTEGER)
RETURNS BOOLEAN AS $$
  SELECT EXISTS(
    SELECT 1
    FROM parent_child_map pcm
    JOIN parent_verifications pv
      ON pv.child_id=pcm.child_id
     AND pv.parent_user_id=COALESCE(pcm.verified_parent_id,pcm.parent_id)
    WHERE pcm.child_id=target_child
      AND pv.verification_status='VERIFIED'
      AND COALESCE(pv.liveness_status,'')='PASSED'
  );
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION littlenet_child_activation_guard()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.role='CHILD'
     AND OLD.account_status IS DISTINCT FROM NEW.account_status
     AND NEW.account_status='ACTIVE'
     AND EXISTS(SELECT 1 FROM parent_child_map pcm WHERE pcm.child_id=NEW.user_id AND pcm.approved=FALSE)
     AND NOT littlenet_guardian_verified_for_child(NEW.user_id)
  THEN
    RAISE EXCEPTION 'verified_guardian_required_for_child_activation' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_littlenet_child_activation_guard ON users;
CREATE TRIGGER trg_littlenet_child_activation_guard
BEFORE UPDATE OF account_status ON users
FOR EACH ROW EXECUTE FUNCTION littlenet_child_activation_guard();

CREATE OR REPLACE FUNCTION littlenet_parent_child_approval_guard()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.approved=FALSE AND NEW.approved=TRUE
     AND NOT littlenet_guardian_verified_for_child(NEW.child_id)
  THEN
    RAISE EXCEPTION 'verified_guardian_required_for_child_approval' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_littlenet_parent_child_approval_guard ON parent_child_map;
CREATE TRIGGER trg_littlenet_parent_child_approval_guard
BEFORE UPDATE OF approved ON parent_child_map
FOR EACH ROW EXECUTE FUNCTION littlenet_parent_child_approval_guard();

-- migrate:down
DROP TRIGGER IF EXISTS trg_littlenet_parent_child_approval_guard ON parent_child_map;
DROP FUNCTION IF EXISTS littlenet_parent_child_approval_guard();
DROP TRIGGER IF EXISTS trg_littlenet_child_activation_guard ON users;
DROP FUNCTION IF EXISTS littlenet_child_activation_guard();
DROP FUNCTION IF EXISTS littlenet_guardian_verified_for_child(INTEGER);
