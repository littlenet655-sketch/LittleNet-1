"""Regression tests for the college-submission safety blockers found in the master audit."""
from pathlib import Path
import sys
import types

import pytest


def test_empty_moderation_envelope_fails_closed():
    from safety.common import normalize_signals
    from safety.policy import decide

    signals=normalize_signals(None,category='IMAGE')
    assert signals['total_safety_failure'] is True
    assert 'invalid_signal_envelope' in signals['errors']
    assert decide(signals).action=='BLOCK'


def test_malformed_score_never_becomes_plain_allow():
    from safety.common import normalize_signals
    from safety.policy import decide

    signals=normalize_signals({'category':'TEXT','toxicity_score':'not-a-number'})
    assert signals['partial_safety_failure'] is True
    assert decide(signals).action=='REVIEW'


def test_remote_empty_signals_are_rejected():
    from safety.remote_client import _moderation_signals

    class Response:
        def json(self):return {'ok':True,'signals':{}}

    with pytest.raises(ValueError,match='moderation_signals_missing'):
        _moderation_signals(Response())


def test_mixed_video_frame_failure_routes_to_review(monkeypatch):
    import safety.remote_client as remote
    import safety.video_service as video
    from safety.common import normalize_signals
    from safety.policy import decide

    safe=normalize_signals({
        'category':'IMAGE','adult_score':0.0,'sexual_score':0.0,'violence_score':0.0,
        'weapon_score':0.0,'toxicity_score':0.0,'general_score':0.0,
        'total_safety_failure':False,'partial_safety_failure':False,'errors':[],
    },category='IMAGE')
    failed=normalize_signals({
        'category':'IMAGE','total_safety_failure':True,'errors':['frame_failed'],
    },category='IMAGE')

    monkeypatch.setattr(remote,'enabled',lambda:False)
    monkeypatch.setattr(video,'_video_sample_count',lambda path,max_frames=None:2)
    monkeypatch.setattr(video,'timed_call',lambda name,fn,seconds:([safe,failed],[0],[1]))

    signals=video.check_video('synthetic.mp4')
    assert signals['total_safety_failure'] is False
    assert signals['partial_safety_failure'] is True
    assert decide(signals).action=='REVIEW'


def test_conversation_rechecks_relationship_before_existing_lookup(monkeypatch):
    import childMessage.service as service

    called={'fetch':False}
    monkeypatch.setattr(service,'can_interact',lambda a,b:False)
    def forbidden_fetch(*args,**kwargs):
        called['fetch']=True
        raise AssertionError('existing conversation must not be looked up after revocation')
    monkeypatch.setattr(service,'fetch_one',forbidden_fetch)

    assert service.conversation(10,20) is None
    assert called['fetch'] is False


def test_messages_recheck_current_relationship(monkeypatch):
    import childMessage.service as service

    monkeypatch.setattr(service,'fetch_one',lambda *a,**k:{'child1_id':10,'child2_id':20})
    monkeypatch.setattr(service,'can_interact',lambda a,b:False)
    monkeypatch.setattr(service,'fetch_all',lambda *a,**k:(_ for _ in ()).throw(AssertionError('message rows must not be read')))
    assert service.messages(99,10)==[]


def _install_fake_deepface(monkeypatch, faces, age):
    class FakeDeepFace:
        @staticmethod
        def extract_faces(**kwargs):return faces
        @staticmethod
        def analyze(**kwargs):return [{'age':age}]
    module=types.ModuleType('deepface')
    module.DeepFace=FakeDeepFace
    monkeypatch.setitem(sys.modules,'deepface',module)


def test_guardian_empty_face_evidence_cannot_pass(monkeypatch):
    import safety.remote_client as remote
    from safety.face_service import verify_adult_face

    monkeypatch.setattr(remote,'enabled',lambda:False)
    monkeypatch.delenv('GEMINI_API_KEY',raising=False)
    monkeypatch.delenv('GOOGLE_API_KEY',raising=False)
    _install_fake_deepface(monkeypatch,[],30)
    result=verify_adult_face('synthetic.jpg')
    assert result['is_adult'] is False
    assert result['reason']=='single_face_required'


def test_guardian_missing_liveness_flag_cannot_pass(monkeypatch):
    import safety.remote_client as remote
    from safety.face_service import verify_adult_face

    monkeypatch.setattr(remote,'enabled',lambda:False)
    monkeypatch.delenv('GEMINI_API_KEY',raising=False)
    monkeypatch.delenv('GOOGLE_API_KEY',raising=False)
    _install_fake_deepface(monkeypatch,[{}],30)
    result=verify_adult_face('synthetic.jpg')
    assert result['is_adult'] is False
    assert result['reason']=='liveness_failed'


def test_guardian_age_boundary_uses_raw_age_not_rounding(monkeypatch):
    import safety.remote_client as remote
    from safety.face_service import verify_adult_face

    monkeypatch.setattr(remote,'enabled',lambda:False)
    monkeypatch.delenv('GEMINI_API_KEY',raising=False)
    monkeypatch.delenv('GOOGLE_API_KEY',raising=False)
    _install_fake_deepface(monkeypatch,[{'is_real':True}],17.6)
    result=verify_adult_face('synthetic.jpg')
    assert result['is_adult'] is False
    assert result['reason']=='under_age'


def test_short_usage_segments_are_aggregated_before_rounding(monkeypatch):
    import services.usage as usage

    totals=iter(({'total':590},{'total':0}))
    monkeypatch.setattr(usage,'fetch_one',lambda *a,**k:next(totals))
    assert usage.minutes_today(7)==9


def test_contextual_chat_records_final_decision_and_runs_unavailable_fallback():
    src=(Path(__file__).parents[1]/'childMessage/routes.py').read_text(encoding='utf-8')
    assert 'if needs_contextual_eval:' in src
    assert 'if needs_contextual_eval and ai_client.is_k2_available()' not in src
    assert "record(session['user_id'],'MESSAGE',row['child_message_id'],sig,final_decision)" in src


def test_server_recreates_missing_usage_session_before_lock_check():
    src=(Path(__file__).parents[1]/'app.py').read_text(encoding='utf-8')
    assert "if not key or heartbeat(key) is None:" in src
    assert "started=start_session(session['user_id'])" in src
    assert src.index("started=start_session(session['user_id'])") < src.index("locked,_=lock_state(session['user_id'])")


def test_parent_media_uses_canonical_ownership_helper():
    src=(Path(__file__).parents[1]/'app.py').read_text(encoding='utf-8')
    assert "from parent.service import owns" in src
    assert "if not owns(uid,p['child_id'])" in src
    assert "if not owns(uid,m['sender_child_id'])" in src
