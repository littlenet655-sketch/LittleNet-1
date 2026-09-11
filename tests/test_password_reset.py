import pytest
import bcrypt
from auth.password_reset import (
    request_password_reset,
    verify_and_reset_password,
    parent_reset_child_password,
    _otp_hash,
)
from database.connection import execute, fetch_one


def test_password_reset_flow():
    # Setup test parent and child
    test_p_email = "test_parent_reset@example.com"
    test_c_uname = "test_child_reset_user"

    # Cleanup any previous runs
    execute("DELETE FROM users WHERE email=%s OR username=%s", (test_p_email, test_c_uname))

    # 1. Create parent
    p_hash = bcrypt.hashpw(b"OldParentPass123!", bcrypt.gensalt()).decode("utf-8")
    execute(
        "INSERT INTO users(username, full_name, email, password_hash, role, account_status) "
        "VALUES('test_p_reset', 'Test Parent', %s, %s, 'PARENT', 'ACTIVE')",
        (test_p_email, p_hash),
    )
    p_row = fetch_one("SELECT user_id FROM users WHERE email=%s", (test_p_email,))
    assert p_row is not None
    p_id = p_row["user_id"]

    # 2. Create child linked to parent
    c_hash = bcrypt.hashpw(b"OldChildPass123!", bcrypt.gensalt()).decode("utf-8")
    execute(
        "INSERT INTO users(username, full_name, email, password_hash, role, account_status) "
        "VALUES(%s, 'Test Child', %s, %s, 'CHILD', 'ACTIVE')",
        (test_c_uname, f"{test_c_uname}@kids.littlenet.internal", c_hash),
    )
    c_row = fetch_one("SELECT user_id FROM users WHERE username=%s", (test_c_uname,))
    assert c_row is not None
    c_id = c_row["user_id"]

    execute(
        "INSERT INTO parent_child_map(parent_id, child_id, parent_name, parent_email, approved, approval_status) "
        "VALUES(%s, %s, 'Test Parent', %s, TRUE, 'APPROVED')",
        (p_id, c_id, test_p_email),
    )

    try:
        # 3. Test Parent Forgot Password (direct email)
        ok, err, info = request_password_reset(test_p_email)
        assert ok is True
        assert info["user_id"] == p_id
        assert "test_parent_reset" in info["masked_email"] or "@example.com" in info["masked_email"]
        assert info["is_parent_proxy"] is False

        # 4. Test Child Forgot Password (routes to parent email proxy)
        ok, err, info = request_password_reset(test_c_uname)
        assert ok is True
        assert info["user_id"] == c_id
        assert info["is_parent_proxy"] is True

        # 5. Verify invalid OTP rejection
        ok, msg = verify_and_reset_password(c_id, "000000", "NewChildPass123!")
        assert ok is False
        assert "Incorrect" in msg or "invalid" in msg.lower()

        # 6. Verify password too short rejection
        ok, msg = verify_and_reset_password(c_id, "123456", "short")
        assert ok is False
        assert "at least 8 characters" in msg

        # 7. Parent resets child password directly from Parent Controls
        ok, msg = parent_reset_child_password(p_id, c_id, "NewParentGivenChildPass123!")
        assert ok is True
        c_updated = fetch_one("SELECT password_hash FROM users WHERE user_id=%s", (c_id,))
        assert bcrypt.checkpw(b"NewParentGivenChildPass123!", c_updated["password_hash"].encode("utf-8"))

        # 8. Admin user deletion cascades
        execute("DELETE FROM users WHERE user_id=%s AND role<>'ADMIN'", (c_id,))
        assert fetch_one("SELECT user_id FROM users WHERE user_id=%s", (c_id,)) is None
        assert fetch_one("SELECT map_id FROM parent_child_map WHERE child_id=%s", (c_id,)) is None

    finally:
        # Cleanup
        execute("DELETE FROM users WHERE email=%s OR username=%s", (test_p_email, test_c_uname))
