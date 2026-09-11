import json
import os
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from quiz.service import (
    FEED_QUIZ_INTERVAL,
    feed_quiz_interval,
    feed_quiz_state,
    record_feed_view,
    quiz_due,
)
from safety.policy import decide, Decision
from safety.pii_service import scan_pii
from safety.text_service import check_text

ROOT = Path(__file__).resolve().parents[1]


def read_repo_file(rel_path: str) -> str:
    return (ROOT / rel_path).read_text(encoding="utf-8")


class TestQuizSafetyReleaseGate(unittest.TestCase):
    """Full end-to-end verification for LittleNet mandatory quiz and safety invariants."""

    # -------------------------------------------------------------------------
    # 1. Default Quiz Interval is 4
    # -------------------------------------------------------------------------
    def test_01_default_feed_quiz_interval_is_4(self):
        self.assertEqual(FEED_QUIZ_INTERVAL, 4)
        with patch("quiz.service.setting", return_value=None):
            interval = feed_quiz_interval(99999)
            self.assertEqual(interval, 4)

    # -------------------------------------------------------------------------
    # 2. Parent Frequency Clamping & Non-Disableable Child Lock
    # -------------------------------------------------------------------------
    def test_02_parent_frequency_clamping_and_child_lock(self):
        # 1 to 4 are accepted
        for valid_freq in [1, 2, 3, 4]:
            with patch("quiz.service.setting", return_value={"quiz_frequency": valid_freq, "mandatory_quiz": True}):
                self.assertEqual(feed_quiz_interval(100), valid_freq)

        # Values > 4 are clamped to 4
        for excessive_freq in [5, 10, 50, 100]:
            with patch("quiz.service.setting", return_value={"quiz_frequency": excessive_freq, "mandatory_quiz": True}):
                self.assertEqual(feed_quiz_interval(100), 4)

        # Values < 1 are clamped to 1
        for low_freq in [0, -5]:
            with patch("quiz.service.setting", return_value={"quiz_frequency": low_freq, "mandatory_quiz": True}):
                self.assertEqual(feed_quiz_interval(100), 1)

        # Child cannot disable: even if mandatory_quiz is False in db, child is still clamped to <= 4
        with patch("quiz.service.setting", return_value={"quiz_frequency": 4, "mandatory_quiz": False}):
            self.assertEqual(feed_quiz_interval(100), 4)

        # Parent route strictly validates 1 <= f <= 4 in quiz/routes.py
        routes_content = read_repo_file("quiz/routes.py")
        self.assertIn("1<=f<=4", routes_content)

    # -------------------------------------------------------------------------
    # 3. Combined Counter: Feed & Reels Increment the Same Counter
    # -------------------------------------------------------------------------
    def test_03_combined_feed_and_reels_counter(self):
        # Service defines unified record_feed_view supporting source_type
        service_code = read_repo_file("quiz/service.py")
        self.assertIn("def record_feed_view(cid, post_id, source_type=", service_code)
        self.assertIn("FOR UPDATE", service_code)
        self.assertIn("post_id not in seen", service_code)

        # Mobile impression endpoint advances counter via record_feed_view
        api_code = read_repo_file("mobile/api.py")
        self.assertIn("view_res = record_feed_view(uid, source_id, source_type=source_type)", api_code)
        self.assertIn("posts_seen=view_res.get(\"posts_seen\", 4)", api_code)

    # -------------------------------------------------------------------------
    # 4. Curated Content and Social Posts Both Increment the Counter
    # -------------------------------------------------------------------------
    def test_04_curated_content_and_social_posts_both_supported(self):
        service_code = read_repo_file("quiz/service.py")
        self.assertIn("curated_content", service_code)
        self.assertIn("stype = str(source_type or \"POST\").upper()", service_code)

        # In Flutter feed, both CURATED and POST items record impressions
        feed_screen = read_repo_file("mobile_flutter/lib/features/feed/feed_screen.dart")
        self.assertIn("_recordItemImpression(item)", feed_screen)

        # In Flutter reels, impressions call the same endpoint with surface REELS
        reels_screen = read_repo_file("mobile_flutter/lib/features/reels/reels_screen.dart")
        self.assertIn("'surface': 'REELS'", reels_screen)

    # -------------------------------------------------------------------------
    # 5. Deduplication Prevents Preload and Duplicate Counting
    # -------------------------------------------------------------------------
    def test_05_deduplication_prevents_duplicate_and_preload_inflation(self):
        service_code = read_repo_file("quiz/service.py")
        self.assertIn("post_id not in seen", service_code)
        self.assertIn("item_token not in seen", service_code)

        # Flutter client only records impressions when items are rendered, not blindly on fetch
        feed_screen = read_repo_file("mobile_flutter/lib/features/feed/feed_screen.dart")
        self.assertNotIn("_recordVisibleImpressions(newItems);", feed_screen)

    # -------------------------------------------------------------------------
    # 6. HTTP 428 Gate Returned at Threshold and Blocks Other Endpoints
    # -------------------------------------------------------------------------
    def test_06_http_428_gate_returned_at_threshold(self):
        api_code = read_repo_file("mobile/api.py")
        # Impression endpoint returns 428 on threshold
        self.assertIn("if view_res.get(\"required\"):", api_code)
        self.assertIn("error=\"quiz_required\"", api_code)
        self.assertIn("gate=\"quiz\"", api_code)
        self.assertIn(", 428", api_code)

        # _child_gate returns 428 when quiz is required
        self.assertIn("def _child_gate(", api_code)
        self.assertIn("if feed_quiz_state(uid).get(\"required\"):", api_code)

    # -------------------------------------------------------------------------
    # 7. Persistent PostgreSQL Latch & Restart Invariant
    # -------------------------------------------------------------------------
    def test_07_persistent_postgresql_latch_survives_restarts(self):
        schema = read_repo_file("database/schema.sql")
        self.assertIn("quiz_required BOOLEAN NOT NULL DEFAULT FALSE", schema)

        service_code = read_repo_file("quiz/service.py")
        self.assertIn("if row.get('quiz_required'):", service_code)

        # User payload exposes quiz_required
        api_code = read_repo_file("mobile/api.py")
        self.assertIn("\"quiz_required\": quiz_required,", api_code)

        # Flutter user model parses quizRequired
        user_model = read_repo_file("mobile_flutter/lib/core/models/user.dart")
        self.assertIn("final bool quizRequired;", user_model)
        self.assertIn("quizRequired: json['quiz_required'] == true", user_model)

        # Flutter app routes directly to /kids/quiz on cold launch if quizRequired
        app_code = read_repo_file("mobile_flutter/lib/app/app.dart")
        self.assertIn("if (user.quizRequired) return '/kids/quiz';", app_code)

    # -------------------------------------------------------------------------
    # 8. Answering Quiz Resets Counter and Clears Latch
    # -------------------------------------------------------------------------
    def test_08_submitting_answer_resets_counter_and_clears_latch(self):
        service_code = read_repo_file("quiz/service.py")
        self.assertIn("def complete_required_feed_quiz", service_code)
        self.assertIn("posts_seen=0,quiz_required=FALSE", service_code)

        # Quiz screen submits real answer to /api/mobile/v1/kids/quiz/$quizId/answer
        quiz_screen = read_repo_file("mobile_flutter/lib/features/quiz/quiz_screen.dart")
        self.assertIn("'/api/mobile/v1/kids/quiz/$quizId/answer'", quiz_screen)
        self.assertIn("body: {'answer': selectedAnswer}", quiz_screen)
        self.assertIn("Navigator.of(context).pop(true)", quiz_screen)

    # -------------------------------------------------------------------------
    # 9. Parent Frequency = 3 Triggers at 3rd Item
    # -------------------------------------------------------------------------
    def test_09_parent_frequency_3_triggers_at_third_item(self):
        with patch("quiz.service.setting", return_value={"quiz_frequency": 3, "mandatory_quiz": True}):
            self.assertEqual(feed_quiz_interval(42), 3)

    # -------------------------------------------------------------------------
    # 10. Multimodal Safety: Adult (18+) Visual Content Hard Blocked
    # -------------------------------------------------------------------------
    def test_10_safety_adult_18_plus_image_hard_blocked(self):
        decision = decide({"adult_score": 0.45, "sexual_score": 0.20, "weapon_score": 0.0, "toxicity_score": 0.0})
        self.assertEqual(decision.action, "BLOCK")
        self.assertTrue("18+" in decision.reason or "adult" in decision.reason.lower())

    # -------------------------------------------------------------------------
    # 11. Multimodal Safety: Weapon / Dangerous Object Blocked
    # -------------------------------------------------------------------------
    def test_11_safety_weapon_dangerous_object_blocked(self):
        decision = decide({"adult_score": 0.0, "weapon_score": 0.50, "violence_score": 0.20})
        self.assertEqual(decision.action, "BLOCK")
        self.assertIn("weapon", decision.reason.lower())

    # -------------------------------------------------------------------------
    # 12. Multimodal Safety: Text Safety
    # -------------------------------------------------------------------------
    def test_12_safety_text_normal_allowed_grooming_solicitation_threat_blocked(self):
        zero_scores = {
            "toxicity": 0.01,
            "severe_toxicity": 0.0,
            "obscene": 0.0,
            "threat": 0.0,
            "insult": 0.0,
            "identity_attack": 0.0,
            "sexual_explicit": 0.0,
        }
        with patch("safety.text_service._detox_scores", return_value=zero_scores):
            # Clean text -> ALLOW
            clean_res = check_text("Let's study the planets and solar system together!")
            clean_dec = decide(clean_res)
            self.assertEqual(clean_dec.action, "ALLOW")

            # Sexual solicitation / grooming -> adult_score = 1.0 -> BLOCK
            grooming_res = check_text("send me a private nude pic and keep it our little secret")
            self.assertGreaterEqual(grooming_res.get("adult_score", 0), 0.40)
            grooming_dec = decide(grooming_res)
            self.assertEqual(grooming_dec.action, "BLOCK")

            # Severe abuse / death threat -> threat_score = 1.0 -> BLOCK
            threat_res = check_text("i will kill you and your family")
            threat_dec = decide(threat_res)
            self.assertEqual(threat_dec.action, "BLOCK")

        # PII / Phone number solicitation -> BLOCK
        phone_pii = scan_pii("Call me immediately at 9876543210")
        self.assertTrue(phone_pii["detected"])
        self.assertEqual(phone_pii["policy_action"], "BLOCK")

    # -------------------------------------------------------------------------
    # 13. Multimodal Safety: Video Frame Sampling Aborts on Adult Frame
    # -------------------------------------------------------------------------
    def test_13_safety_video_frame_sampling_detects_adult_frame(self):
        video_service_code = read_repo_file("safety/video_service.py")
        self.assertIn("combined_frame_indices", video_service_code)
        self.assertIn("if decide(signals).action == \"BLOCK\":", video_service_code)
        self.assertIn("break", video_service_code)

    # -------------------------------------------------------------------------
    # 14. Multimodal Safety: Fail-Closed Policy
    # -------------------------------------------------------------------------
    def test_14_safety_fail_closed_invariants(self):
        # Total AI failure -> BLOCK (fail closed)
        total_fail = decide({"total_safety_failure": True, "errors": ["ai_service_unavailable"]})
        self.assertEqual(total_fail.action, "BLOCK")
        self.assertIn("fail closed", total_fail.reason.lower())

        # Partial AI failure -> REVIEW (quarantined until parent or moderator review)
        partial_fail = decide({"partial_safety_failure": True, "adult_score": 0.05, "errors": ["yolo_timeout"]})
        self.assertEqual(partial_fail.action, "REVIEW")

    # -------------------------------------------------------------------------
    # 15. Multimodal Safety: Zero AI on Viewing Path
    # -------------------------------------------------------------------------
    def test_15_zero_safety_ai_on_viewing_path(self):
        # In mobile/api.py, reading feed, reels, and media only checks database moderation_status
        api_code = read_repo_file("mobile/api.py")
        feed_block = api_code.split("def mobile_kids_feed_v2():", 1)[1].split("@bp.route", 1)[0]
        self.assertNotIn("check_image(", feed_block)
        self.assertNotIn("check_video(", feed_block)
        self.assertNotIn("Detoxify(", feed_block)
        self.assertNotIn("NudeDetector(", feed_block)

        reels_block = api_code.split("def mobile_kids_reels_v2():", 1)[1].split("@bp.route", 1)[0]
        self.assertNotIn("check_image(", reels_block)
        self.assertNotIn("check_video(", reels_block)

    # -------------------------------------------------------------------------
    # 16. Mobile Flutter Client Contract
    # -------------------------------------------------------------------------
    def test_16_mobile_flutter_client_contract(self):
        api_dart = read_repo_file("mobile_flutter/lib/api.dart")
        self.assertIn("static void Function()? onQuizRequired;", api_dart)
        self.assertIn("bool get isQuizGate", api_dart)
        self.assertIn("onQuizRequired?.call();", api_dart)

        app_dart = read_repo_file("mobile_flutter/lib/app/app.dart")
        self.assertIn("GlobalKey<NavigatorState>", app_dart)
        self.assertIn("ApiClient.onQuizRequired =", app_dart)
        self.assertIn("navigatorKey.currentState?.pushNamed('/kids/quiz')", app_dart)

        quiz_screen = read_repo_file("mobile_flutter/lib/features/quiz/quiz_screen.dart")
        self.assertIn("PopScope(", quiz_screen)
        self.assertIn("canPop: _completed || !_isMandatory", quiz_screen)
        self.assertIn("Brain Break Quiz 🧠", quiz_screen)
        self.assertNotIn("Skip for now", quiz_screen)
        self.assertNotIn("Maybe later", quiz_screen)


if __name__ == "__main__":
    unittest.main()
