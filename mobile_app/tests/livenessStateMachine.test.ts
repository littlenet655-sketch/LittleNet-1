/// <reference types="node" />
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { evaluateFaceQuality } from '../src/camera/faceQuality';

// Transpile-and-load harness (same approach as cameraRuntime.test.ts): this
// verifies the real facePrecheck source with only native boundaries stubbed.
function loadSource(path: string, imports: Record<string, unknown>): unknown {
  const output = ts.transpileModule(readFileSync(resolve(path), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, jsx: ts.JsxEmit.ReactJSX },
  }).outputText;
  const exports = {};
  runInNewContext(output, {
    exports,
    require: (name: string) => {
      assert.ok(name in imports, `Unexpected dependency: ${name}`);
      return imports[name];
    },
    console,
  }, { filename: path });
  return exports;
}

const platform = { OS: 'android', select: (options: Record<string, string>) => options.default };

function loadFacePrecheck(detectImpl?: (uri: string, options: unknown) => Promise<unknown[]>) {
  const native = {
    Platform: platform,
    NativeModules: detectImpl ? { FaceDetection: { detect: detectImpl } } : {},
    StyleSheet: { create: (styles: unknown) => styles },
  };
  const mlkit = loadSource('node_modules/@react-native-ml-kit/face-detection/index.ts', {
    'react-native': native,
  });
  return loadSource('src/camera/facePrecheck.ts', {
    'react-native': native,
    '@react-native-ml-kit/face-detection': mlkit,
    './faceQuality': { evaluateFaceQuality },
    'expo-file-system': {},
  }) as typeof import('../src/camera/facePrecheck');
}

const image = { width: 1000, height: 1000 };
const baseFace = {
  frame: { width: 360, height: 460, left: 320, top: 270 },
  rotationX: 0,
  rotationY: 0,
  rotationZ: 0,
};
const eyesOpenFace = { ...baseFace, leftEyeOpenProbability: 0.95, rightEyeOpenProbability: 0.92 };
const eyesClosedFace = { ...baseFace, leftEyeOpenProbability: 0.12, rightEyeOpenProbability: 0.15 };

test('blink challenge requires the full OPEN -> CLOSED -> OPEN sequence', () => {
  const precheck = loadFacePrecheck();

  const prompted = precheck.evaluateLivenessFrame(image, [eyesOpenFace], 'BLINK', 'WAITING_FOR_OPEN');
  assert.equal(prompted.stage, 'WAITING_FOR_BLINK');
  assert.equal(prompted.isComplete, false);

  const closed = precheck.evaluateLivenessFrame(image, [eyesClosedFace], 'BLINK', prompted.stage);
  assert.equal(closed.stage, 'WAITING_FOR_REOPEN');
  assert.equal(closed.isComplete, false);
  assert.equal(closed.statusText, 'Reopen Eyes');

  const verified = precheck.evaluateLivenessFrame(image, [eyesOpenFace], 'BLINK', closed.stage);
  assert.equal(verified.stage, 'VERIFIED');
  assert.equal(verified.isComplete, true);
  assert.equal(verified.step, 3);
});

test('blink challenge rejects partial sequences', () => {
  const precheck = loadFacePrecheck();

  // Starting with eyes closed must not count as the blink: OPEN is required first.
  const closedFirst = precheck.evaluateLivenessFrame(image, [eyesClosedFace], 'BLINK', 'WAITING_FOR_OPEN');
  assert.equal(closedFirst.stage, 'WAITING_FOR_OPEN');
  assert.equal(closedFirst.isComplete, false);

  // OPEN then OPEN (never closing) must not skip to VERIFIED.
  const prompted = precheck.evaluateLivenessFrame(image, [eyesOpenFace], 'BLINK', 'WAITING_FOR_OPEN');
  const stillWaiting = precheck.evaluateLivenessFrame(image, [eyesOpenFace], 'BLINK', prompted.stage);
  assert.equal(stillWaiting.stage, 'WAITING_FOR_BLINK');
  assert.equal(stillWaiting.isComplete, false);

  // CLOSED -> OPEN only verifies when the REOPEN stage was legitimately reached
  // via a detected close; jumping straight to it is tested above.
});

test('losing the face mid-challenge resets the blink sequence', () => {
  const precheck = loadFacePrecheck();

  const noFace = precheck.evaluateLivenessFrame(image, [], 'BLINK', 'WAITING_FOR_REOPEN');
  assert.equal(noFace.stage, 'WAITING_FOR_OPEN');
  assert.equal(noFace.isComplete, false);

  const multiFace = precheck.evaluateLivenessFrame(image, [eyesOpenFace, eyesOpenFace], 'BLINK', 'WAITING_FOR_REOPEN');
  assert.equal(multiFace.stage, 'WAITING_FOR_OPEN');
  assert.equal(multiFace.statusText, 'Multiple Faces Detected');

  // A misaligned face mid-blink also restarts the sequence.
  const tooSmall = { ...eyesClosedFace, frame: { ...eyesClosedFace.frame, width: 100 } };
  const misaligned = precheck.evaluateLivenessFrame(image, [tooSmall], 'BLINK', 'WAITING_FOR_REOPEN');
  assert.equal(misaligned.stage, 'WAITING_FOR_OPEN');
  assert.equal(misaligned.isComplete, false);
});

test('TURN_LEFT accepts only a leftward (positive yaw) turn', () => {
  const precheck = loadFacePrecheck();

  const done = precheck.evaluateLivenessFrame(image, [{ ...baseFace, rotationY: 20 }], 'TURN_LEFT', 'WAITING_FOR_TURN');
  assert.equal(done.isComplete, true);
  assert.equal(done.stage, 'VERIFIED');

  const wrongWay = precheck.evaluateLivenessFrame(image, [{ ...baseFace, rotationY: -20 }], 'TURN_LEFT', 'WAITING_FOR_TURN');
  assert.equal(wrongWay.isComplete, false);
  assert.equal(wrongWay.stage, 'WAITING_FOR_TURN');
  assert.equal(wrongWay.statusText, 'Wrong Direction');

  const pending = precheck.evaluateLivenessFrame(image, [{ ...baseFace, rotationY: 8 }], 'TURN_LEFT', 'WAITING_FOR_TURN');
  assert.equal(pending.isComplete, false);
  assert.equal(pending.statusText, 'Turn Head Left');

  const straight = precheck.evaluateLivenessFrame(image, [baseFace], 'TURN_LEFT', 'WAITING_FOR_OPEN');
  assert.equal(straight.isComplete, false);
  assert.equal(straight.stage, 'WAITING_FOR_TURN');
});

test('TURN_RIGHT accepts only a rightward (negative yaw) turn', () => {
  const precheck = loadFacePrecheck();

  const done = precheck.evaluateLivenessFrame(image, [{ ...baseFace, rotationY: -20 }], 'TURN_RIGHT', 'WAITING_FOR_TURN');
  assert.equal(done.isComplete, true);
  assert.equal(done.stage, 'VERIFIED');

  const wrongWay = precheck.evaluateLivenessFrame(image, [{ ...baseFace, rotationY: 20 }], 'TURN_RIGHT', 'WAITING_FOR_TURN');
  assert.equal(wrongWay.isComplete, false);
  assert.equal(wrongWay.stage, 'WAITING_FOR_TURN');
  assert.equal(wrongWay.statusText, 'Wrong Direction');
});

test('liveness frame rejects partially visible and extra faces', () => {
  const precheck = loadFacePrecheck();

  // A second, partially visible face still counts as multiple faces.
  const extra = precheck.evaluateLivenessFrame(image, [baseFace, { ...baseFace, frame: { width: 200, height: 200, left: -50, top: 100 } }], 'BLINK', 'WAITING_FOR_OPEN');
  assert.equal(extra.statusText, 'Multiple Faces Detected');
  assert.equal(extra.isAligned, false);

  // A single face clipped by the image edge is partially visible.
  const clipped = { ...baseFace, frame: { width: 360, height: 460, left: 700, top: 270 } };
  assert.equal(evaluateFaceQuality(image, [clipped]).failure, 'partial_face');
  const clippedProgress = precheck.evaluateLivenessFrame(image, [clipped], 'BLINK', 'WAITING_FOR_OPEN');
  assert.equal(clippedProgress.isAligned, false);
  assert.equal(clippedProgress.stage, 'WAITING_FOR_OPEN');
});

test('face quality still rejects small and off-center faces', () => {
  assert.equal(
    evaluateFaceQuality(image, [{ ...baseFace, frame: { ...baseFace.frame, width: 120 } }]).failure,
    'face_too_small',
  );
  assert.equal(
    evaluateFaceQuality(image, [{ ...baseFace, frame: { ...baseFace.frame, left: 40 } }]).failure,
    'off_center',
  );
  assert.deepEqual(evaluateFaceQuality(image, [baseFace]), { ok: true });
});

test('strict detector distinguishes native outage from an empty frame', async () => {
  // Results cross a VM boundary in this harness, so compare structurally.
  const isEmptyFaceList = (value: unknown): boolean => Array.isArray(value) && value.length === 0;

  // Native module missing entirely.
  const missing = loadFacePrecheck();
  await assert.rejects(() => missing.detectFacesOrThrow('file:///frame.jpg'));
  assert.ok(isEmptyFaceList(await missing.detectFacesInImage('file:///frame.jpg')));

  // Native module present but throwing on this frame.
  const throwing = loadFacePrecheck(async () => { throw new Error('native crashed'); });
  await assert.rejects(() => throwing.detectFacesOrThrow('file:///frame.jpg'));
  assert.ok(isEmptyFaceList(await throwing.detectFacesInImage('file:///frame.jpg')));

  // Working detector passes faces through on both paths.
  const working = loadFacePrecheck(async () => [baseFace]);
  const strictFaces = await working.detectFacesOrThrow('file:///frame.jpg');
  assert.equal(strictFaces.length, 1);
  assert.equal(strictFaces[0]?.frame.width, baseFace.frame.width);
  const lenientFaces = await working.detectFacesInImage('file:///frame.jpg');
  assert.equal(lenientFaces.length, 1);
  assert.equal(lenientFaces[0]?.frame.width, baseFace.frame.width);
});

test('precheckFaceChallenge enforces the turn direction on the final selfie', async () => {
  const faces = [{ ...baseFace, rotationY: 20 }];
  const precheck = loadFacePrecheck(async () => faces);
  const photo = { base64: 'photo', width: 1000, height: 1000, uri: 'file:///selfie.jpg' };

  await precheck.precheckFaceChallenge(photo, 'TURN_LEFT');
  await assert.rejects(() => precheck.precheckFaceChallenge(photo, 'TURN_RIGHT'), /turn your head right/);

  faces[0] = { ...baseFace, rotationY: -20 };
  await precheck.precheckFaceChallenge(photo, 'TURN_RIGHT');
  await assert.rejects(() => precheck.precheckFaceChallenge(photo, 'TURN_LEFT'), /turn your head left/);
});

test('precheckFaceChallenge blink proof needs closed eyes unless already live-verified', async () => {
  const openFace = [{ ...eyesOpenFace }];
  const precheck = loadFacePrecheck(async () => openFace);
  const photo = { base64: 'photo', width: 1000, height: 1000, uri: 'file:///selfie.jpg' };

  await assert.rejects(() => precheck.precheckFaceChallenge(photo, 'BLINK'), /close both eyes/);

  openFace[0] = { ...eyesClosedFace };
  await precheck.precheckFaceChallenge(photo, 'BLINK');

  // A live-verified challenge skips the still-photo pose proof entirely.
  const dead = loadFacePrecheck();
  await dead.precheckFaceChallenge({ ...photo, livenessVerified: true }, 'BLINK');
});

// --- Face-login error normalization: the UI must never become an account /
// --- enrollment oracle, even though the client distinguishes cases internally.

class ApiError extends Error {
  status: number;
  code: string;
  gate: unknown;
  details: Record<string, unknown>;
  constructor(status: number, code: string, message: string, gate: unknown = null, details: Record<string, unknown> = {}) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.gate = gate;
    this.details = details;
  }
}

interface ChildFaceModule {
  faceLoginFailureMessage: (error: unknown) => string;
}

function loadChildFace(): ChildFaceModule {
  const jsx = { jsx: (type: unknown, props: unknown) => ({ type, props }), jsxs: (type: unknown, props: unknown) => ({ type, props }) };
  return loadSource('src/screens/ChildFace.tsx', {    'react': { useState: (initial: unknown) => [initial, () => {}] },
    'react/jsx-runtime': jsx,
    'react-native': {
      StyleSheet: { create: (styles: unknown) => styles },
      Image: 'Image',
      Pressable: 'Pressable',
      ScrollView: 'ScrollView',
      Text: 'Text',
      View: 'View',
    },
    '@expo/vector-icons': { Feather: 'Feather' },
    '../api/auth': {},
    '../api/client': { ApiError },
    '../auth/AuthProvider': {},
    '../camera/CameraCapture': {},
    '../camera/livePhoto': {},
    '../camera/facePrecheck': {},
    '../navigation/types': {},
    '../ui/components': {
      Button: 'Button',
      Card: 'Card',
      Field: 'Field',
      GateNotice: 'GateNotice',
      GuidelineChips: 'GuidelineChips',
      Notice: 'Notice',
      Screen: 'Screen',
      errorText: (error: unknown) => (error instanceof Error ? error.message : String(error)),
    },
    '../ui/tokens': { colors: {}, radius: {}, spacing: {}, type: {} },
  }) as ChildFaceModule;
}

test('face-login failures are indistinguishable in the UI (no account/enrollment oracle)', () => {
  const { faceLoginFailureMessage } = loadChildFace();

  const notEnrolled = faceLoginFailureMessage(new ApiError(404, 'face_login_failed', 'raw', null, { reason: 'not_enrolled' }));
  const noMatch = faceLoginFailureMessage(new ApiError(401, 'face_login_failed', 'raw', null, { reason: 'not_matched' }));
  const unknownAccount = faceLoginFailureMessage(new ApiError(401, 'face_login_failed', 'raw'));
  const livenessRejected = faceLoginFailureMessage(new ApiError(401, 'face_login_failed', 'raw', null, { reason: 'liveness_failed' }));

  assert.equal(notEnrolled, noMatch);
  assert.equal(noMatch, unknownAccount);
  assert.equal(unknownAccount, livenessRejected);
  assert.match(notEnrolled, /did not work/);
  assert.doesNotMatch(notEnrolled, /enroll/i);
});

test('face-login maps expired challenges, offline, and server outages distinctly', () => {
  const { faceLoginFailureMessage } = loadChildFace();

  assert.match(
    faceLoginFailureMessage(new ApiError(403, 'face_challenge_expired_or_consumed', 'raw')),
    /fresh face check/,
  );
  assert.match(
    faceLoginFailureMessage(new ApiError(403, 'challenge_already_used_replay_detected', 'raw')),
    /fresh face check/,
  );
  assert.match(
    faceLoginFailureMessage(new ApiError(0, 'verification_offline', 'raw')),
    /internet connection/i,
  );
  assert.match(
    faceLoginFailureMessage(new ApiError(503, 'server_unavailable', 'raw')),
    /temporarily unavailable/,
  );
  assert.equal(faceLoginFailureMessage(new Error('plain failure')), 'plain failure');
});
