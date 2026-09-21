/// <reference types="node" />
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { ApiError } from '../src/api/errors';
import { evaluateFaceQuality } from '../src/camera/faceQuality';
import type { CapturedPhoto } from '../src/camera/capture';

interface TestNode {
  type: unknown;
  props: { label?: string; onPress?: () => void; children?: TestNode | (TestNode | null | false)[] };
}
interface CameraInstance {
  _cameraRef: { current: { takePicture: () => Promise<CapturedPhoto> } | null };
  takePictureAsync: (options: { base64: boolean }) => Promise<CapturedPhoto>;
}
interface CaptureModule {
  CameraCapture: (props: { label: string; onCapture: (photo: CapturedPhoto) => Promise<void> }) => TestNode;
}

// Execute installed package/app JavaScript with only native boundaries and hooks
// substituted. This verifies the public Expo API, not an Android camera or ML Kit.
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
    // React Native always has timers; the bare VM context does not.
    setTimeout,
    clearTimeout,
  }, { filename: path });
  return exports;
}

const jsx = { jsx: (type: unknown, props: unknown) => ({ type, props }), jsxs: (type: unknown, props: unknown) => ({ type, props }) };
const platform = { OS: 'android', select: (options: Record<string, string>) => options.default };
const photo = { uri: 'file:///checked.jpg', base64: 'photo', width: 1000, height: 1000 };
const face = { frame: { width: 360, height: 460, left: 320, top: 270 }, rotationX: 0, rotationY: 0, rotationZ: 0 };

function harness(detector?: () => Promise<unknown>) {
  const calls: string[] = [];
  const { default: CameraView } = loadSource('node_modules/expo-camera/src/CameraView.tsx', {
    'react': { Component: class {}, createRef: () => ({ current: null }) },
    'react/jsx-runtime': jsx,
    'expo-modules-core': { Platform: platform },
    './ExpoCamera': {}, './ExpoCameraManager': {}, './utils/props': {},
  }) as { default: new () => CameraInstance };
  const camera = new CameraView();
  camera._cameraRef.current = { takePicture: async () => { calls.push('camera'); return photo; } };
  assert.equal(Reflect.get(camera, 'takePicture'), undefined, 'takePicture belongs to the inner native ref only');
  assert.throws(() => runInNewContext('camera.takePicture({ base64: true })', { camera }), /is not a function/);
  assert.equal(typeof camera.takePictureAsync, 'function');
  const native = { Platform: platform, StyleSheet: { create: (styles: unknown) => styles } };
  const mlkit = loadSource('node_modules/@react-native-ml-kit/face-detection/index.ts', {
    'react-native': { ...native, NativeModules: detector ? { FaceDetection: { detect: async () => { calls.push('detector'); return detector(); } } } : {} },
  });
  const precheck = loadSource('src/camera/facePrecheck.ts', {
    'react-native': native,
    '@react-native-ml-kit/face-detection': mlkit,
    './faceQuality': { evaluateFaceQuality },
  });
  const states: unknown[] = [false, true, null, null];
  let index = 0;
  let refCalls = 0;
  let online = true;
  const component = loadSource('src/camera/CameraCapture.tsx', {
    'react': {
      // The camera ref must point at the mocked native camera; every other
      // ref gets its own fresh box so guard refs (capture-in-flight, scan
      // generation, ...) behave like the real implementation.
      useRef: (initial?: unknown) => (refCalls++ === 0 ? { current: camera } : { current: initial }),
      useState: (initial?: unknown) => {
        const slot = index++;
        // Match React: invoke a lazy initializer exactly once per slot.
        if (states[slot] === undefined) states[slot] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
        return [states[slot], (value: unknown) => { states[slot] = value; }];
      },
      useEffect: () => {},
    },
    'react/jsx-runtime': jsx,
    'expo-camera': { useCameraPermissions: () => [{ granted: true }, async () => ({ granted: true })] },
    'react-native': native,
    '@react-native-community/netinfo': { fetch: async () => ({ isConnected: online }) },
    '@expo/vector-icons': { Feather: () => null },
    '../api/client': { ApiError },
    './capture': {},
    './facePrecheck': precheck,
    '../ui/components': { Button: 'Button', Notice: 'Notice', errorText: String },
    '../ui/nativeViews': { NativeCameraView: CameraView },
    '../ui/tokens': { colors: {}, radius: {}, spacing: {} },
  }) as CaptureModule;
  // Permission hook is supplied separately from the installed camera class.
  // Find and press the real component's button, preserving state across renders.
  function findButton(node: TestNode | null | false | undefined, label: string): TestNode | undefined {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Button' && node.props.label === label) return node;
    for (const child of [node.props?.children].flat()) {
      const found = findButton(child, label);
      if (found) return found;
    }
  }
  return { calls, states, setOnline: (value: boolean) => { online = value; }, async press(label: string) {
    index = 0;
    refCalls = 0;
    const tree = component.CameraCapture({ label: 'Capture', onCapture: async () => { calls.push('submit'); } });
    const button = findButton(tree, label);
    if (!button || typeof button.props?.onPress !== 'function') {
      throw new Error(`Missing button: ${label}`);
    }
    button.props.onPress();
    await new Promise<void>((done) => setImmediate(done));
  } };
}

test('installed Expo public capture method reaches ML Kit before submission', async () => {
  const run = harness(async () => [face]);
  await run.press('Capture');
  assert.deepEqual(run.calls, ['camera', 'detector', 'submit']);
  assert.equal(run.states[2], null);
});

test('detector failure and rejected faces never submit or retain retry photos', async () => {
  for (const detector of [async () => { throw new Error('native unavailable'); }, async () => [], undefined]) {
    const run = harness(detector);
    await run.press('Capture');
    assert.deepEqual(run.calls, detector ? ['camera', 'detector'] : ['camera']);
    const error = run.states[2] as { name?: string; code?: string; message?: string } | null | undefined;
    assert.ok(error && typeof error === 'object' && 'name' in error && 'code' in error && 'message' in error);
    assert.equal(error.name, 'FacePrecheckError');
    assert.ok(error.code === 'native_unavailable' || error.code === 'no_face');
    if (error.code === 'native_unavailable') {
      assert.equal(error.message, 'The on-device face check is unavailable. Rebuild the Android app before continuing.');
    }
    assert.equal(run.states[3], null);
  }
});

test('offline retry retains only the locally checked photo and submits on reconnect', async () => {
  const run = harness(async () => [face]);
  run.setOnline(false);
  await run.press('Capture');
  assert.deepEqual(run.calls, ['camera', 'detector']);
  const pending = run.states[3] as Record<string, unknown> | null | undefined;
  assert.ok(pending && typeof pending === 'object');
  assert.deepEqual({ ...pending }, photo);
  run.setOnline(true);
  await run.press('Retry verification');
  assert.deepEqual(run.calls, ['camera', 'detector', 'submit']);
  assert.equal(run.states[3], null);
});

test('Google ML Kit automated liveness scanner tracks eye-blink cycle to verification', () => {
  const native = { Platform: platform, NativeModules: {}, StyleSheet: { create: (styles: unknown) => styles } };
  const mlkit = loadSource('node_modules/@react-native-ml-kit/face-detection/index.ts', {
    'react-native': native,
  });
  const precheck = loadSource('src/camera/facePrecheck.ts', {
    'react-native': native,
    '@react-native-ml-kit/face-detection': mlkit,
    './faceQuality': { evaluateFaceQuality },
  }) as {
    evaluateLivenessFrame: typeof import('../src/camera/facePrecheck').evaluateLivenessFrame;
  };

  const image = { width: 1000, height: 1000 };

  // 1. No face
  const noFace = precheck.evaluateLivenessFrame(image, [], 'BLINK', 'WAITING_FOR_OPEN');
  assert.equal(noFace.step, 1);
  assert.equal(noFace.isAligned, false);
  assert.equal(noFace.statusText, 'Looking for face…');

  // 2. Aligned face with eyes open -> prompts to blink
  const eyesOpenFace = {
    ...face,
    leftEyeOpenProbability: 0.95,
    rightEyeOpenProbability: 0.92,
  };
  const step1 = precheck.evaluateLivenessFrame(image, [eyesOpenFace], 'BLINK', 'WAITING_FOR_OPEN');
  assert.equal(step1.step, 2);
  assert.equal(step1.isAligned, true);
  assert.equal(step1.isComplete, false);
  assert.equal(step1.stage, 'WAITING_FOR_BLINK');
  assert.equal(step1.statusText, 'Blink Both Eyes');

  // Slightly conservative ML Kit open-eye probabilities must not leave a
  // straight-facing user stuck waiting for the scanner.
  const normalOpenFace = {
    ...face,
    leftEyeOpenProbability: 0.48,
    rightEyeOpenProbability: 0.47,
  };
  const normalOpen = precheck.evaluateLivenessFrame(image, [normalOpenFace], 'BLINK', 'WAITING_FOR_OPEN');
  assert.equal(normalOpen.stage, 'WAITING_FOR_BLINK');
  assert.equal(normalOpen.isAligned, true);

  // 3. User blinks (eyes close) -> advances to WAITING_FOR_REOPEN
  const eyesClosedFace = {
    ...face,
    leftEyeOpenProbability: 0.12,
    rightEyeOpenProbability: 0.15,
  };
  const step2 = precheck.evaluateLivenessFrame(image, [eyesClosedFace], 'BLINK', 'WAITING_FOR_BLINK');
  assert.equal(step2.step, 2);
  assert.equal(step2.isAligned, true);
  assert.equal(step2.isComplete, false);
  assert.equal(step2.stage, 'WAITING_FOR_REOPEN');
  assert.equal(step2.statusText, 'Reopen Eyes');

  // 4. User opens eyes back up -> VERIFIED!
  const step3 = precheck.evaluateLivenessFrame(image, [eyesOpenFace], 'BLINK', 'WAITING_FOR_REOPEN');
  assert.equal(step3.step, 3);
  assert.equal(step3.isAligned, true);
  assert.equal(step3.isComplete, true);
  assert.equal(step3.stage, 'VERIFIED');
  assert.equal(step3.statusText, 'Blink Verified!');
  assert.equal(step3.ovalColor, '#10B981');
});

test('Google ML Kit automated liveness scanner tracks head-turn challenges', () => {
  const native = { Platform: platform, NativeModules: {}, StyleSheet: { create: (styles: unknown) => styles } };
  const mlkit = loadSource('node_modules/@react-native-ml-kit/face-detection/index.ts', {
    'react-native': native,
  });
  const precheck = loadSource('src/camera/facePrecheck.ts', {
    'react-native': native,
    '@react-native-ml-kit/face-detection': mlkit,
    './faceQuality': { evaluateFaceQuality },
  }) as {
    evaluateLivenessFrame: typeof import('../src/camera/facePrecheck').evaluateLivenessFrame;
  };

  const image = { width: 1000, height: 1000 };

  // TURN_LEFT before turn
  const straight = { ...face, rotationY: 2 };
  const turnLeftPending = precheck.evaluateLivenessFrame(image, [straight], 'TURN_LEFT', 'WAITING_FOR_OPEN');
  assert.equal(turnLeftPending.isComplete, false);
  assert.equal(turnLeftPending.statusText, 'Turn Head Left');

  // TURN_LEFT after turn (rotationY >= 18)
  const turnedLeft = { ...face, rotationY: 22 };
  const turnLeftDone = precheck.evaluateLivenessFrame(image, [turnedLeft], 'TURN_LEFT', 'WAITING_FOR_OPEN');
  assert.equal(turnLeftDone.isComplete, true);
  assert.equal(turnLeftDone.statusText, 'Position Verified!');
  assert.equal(turnLeftDone.ovalColor, '#10B981');
});
