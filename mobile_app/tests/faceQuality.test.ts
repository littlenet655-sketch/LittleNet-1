import assert from 'node:assert/strict';
import test from 'node:test';
import { evaluateFaceQuality } from '../src/camera/faceQuality';

const image = { width: 1000, height: 1000 };
const centeredFace = { frame: { width: 360, height: 460, left: 320, top: 270 }, rotationX: 0, rotationY: 0, rotationZ: 0 };

test('face quality rejects missing and multiple faces before upload', () => {
  assert.equal(evaluateFaceQuality(image, []).failure, 'no_face');
  assert.equal(evaluateFaceQuality(image, [centeredFace, centeredFace]).failure, 'multiple_faces');
});

test('face quality rejects small and off-center faces with actionable guidance', () => {
  assert.equal(
    evaluateFaceQuality(image, [{ ...centeredFace, frame: { ...centeredFace.frame, width: 120 } }]).message,
    'Move closer.',
  );
  assert.equal(
    evaluateFaceQuality(image, [{ ...centeredFace, frame: { ...centeredFace.frame, left: 40 } }]).message,
    'Center your face in the oval.',
  );
});

test('face quality rejects extreme head pose and accepts a centered face', () => {
  assert.equal(evaluateFaceQuality(image, [{ ...centeredFace, rotationY: 35 }]).failure, 'head_pose');
  assert.deepEqual(evaluateFaceQuality(image, [centeredFace]), { ok: true });
});