from pathlib import Path

import pytest

from services import media_sanitizer, object_storage


class FakeS3:
    def __init__(self):self.uploads=[]
    def upload_file(self,*args,**kwargs):self.uploads.append((args,kwargs))


def test_video_is_stripped_before_r2_upload(tmp_path,monkeypatch):
    path=tmp_path/'clip.mp4';path.write_bytes(b'fake-video')
    calls=[];s3=FakeS3()
    monkeypatch.setattr(media_sanitizer,'strip_video_audio_in_place',lambda p:calls.append(p) or True)
    monkeypatch.setattr(object_storage,'_client',lambda:s3)
    monkeypatch.setenv('R2_BUCKET','test-bucket')
    ref=object_storage.upload_file(str(path),'posts/1/test.mp4')
    assert calls == [str(path)]
    assert len(s3.uploads) == 1
    assert ref == 'uploads/r2/posts/1/test.mp4'


def test_audio_strip_failure_prevents_r2_publish(tmp_path,monkeypatch):
    path=tmp_path/'clip.mp4';path.write_bytes(b'fake-video')
    s3=FakeS3()
    def fail(_):raise media_sanitizer.MediaSanitizationError('audio_stream_still_present')
    monkeypatch.setattr(media_sanitizer,'strip_video_audio_in_place',fail)
    monkeypatch.setattr(object_storage,'_client',lambda:s3)
    monkeypatch.setenv('R2_BUCKET','test-bucket')
    with pytest.raises(media_sanitizer.MediaSanitizationError):
        object_storage.upload_file(str(path),'posts/1/test.mp4')
    assert s3.uploads == []


def test_images_do_not_use_video_sanitizer(tmp_path,monkeypatch):
    path=tmp_path/'image.jpg';path.write_bytes(b'fake-image')
    s3=FakeS3()
    monkeypatch.setattr(media_sanitizer,'strip_video_audio_in_place',lambda _p:pytest.fail('image must not be video-sanitized'))
    monkeypatch.setattr(object_storage,'_client',lambda:s3)
    monkeypatch.setenv('R2_BUCKET','test-bucket')
    object_storage.upload_file(str(path),'posts/1/image.jpg')
    assert len(s3.uploads) == 1


def test_sanitizer_contract_uses_ffmpeg_an_and_verifies_audio_absent():
    source=Path(media_sanitizer.__file__).read_text(encoding='utf-8')
    assert "'ffmpeg'" in source
    assert "'-an'" in source
    assert 'has_audio_stream(tmp)' in source
    assert 'audio_stream_still_present' in source
    assert 'os.replace' in source
