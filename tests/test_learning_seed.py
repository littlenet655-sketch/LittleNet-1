from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]

def test_seed_has_five_questions_for_each_main_child_age_group():
    text=(ROOT/'database/seed.sql').read_text(encoding='utf-8')
    block=text.split('INSERT INTO learning_challenges',1)[0]
    for age in ('6-8','9-11','12-13'):
        assert len(re.findall(rf"'{re.escape(age)}'\)",block))>=5

def test_seed_covers_science_kindness_and_digital_safety():
    text=(ROOT/'database/seed.sql').read_text(encoding='utf-8')
    for category in ("'Science'","'Kindness'","'Digital Safety'"):
        assert category in text

def test_home_has_learn_card_and_quiz_has_progress_ui():
    assert 'learn-card' in (ROOT/'child/templates/child_dashboard.html').read_text()
    quiz=(ROOT/'quiz/templates/quiz_card.html').read_text()
    assert 'quiz-progress' in quiz and 'Learning break' in quiz
