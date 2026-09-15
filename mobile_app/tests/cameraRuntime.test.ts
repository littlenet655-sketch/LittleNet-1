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
  }, { filename: path });
  return exports;
}

const jsx = { jsx: (type: unknown, props: unknown) => ({ type, props }), jsxs: (type: unknown, props: unknown) => ({ type, props }) };
const platform = { OS: 'android', select: (options: Record<string, string>) => options.default };
const photo = { uri: 'file:///checked.jpg', base64: 'photo', width: 1000, height: 1000 };
const face = { frame: { width: 360, height: 460, left: 320, top: 270 } };

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
  let online = true;
  const component = loadSource('src/camera/CameraCapture.tsx', {
    'react': { useRef: () => ({ current: camera }), useState: () => {
      const slot = index++;
      return [states[slot], (value: unknown) => { states[slot] = value; }];
    } },
    'react/jsx-runtime': jsx,
    'expo-camera': { useCameraPermissions: () => [{ granted: true }, async () => ({ granted: true })] }, 'react-native': native,
    '@react-native-community/netinfo': { fetch: async () => ({ isConnected: online }) },
    '../api/client': { ApiError }, './capture': {}, './facePrecheck': precheck,
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
    const tree = component.CameraCapture({ label: 'Capture', onCapture: async () => { calls.push('submit'); } });
    const button = findButton(tree, label);
    assert.ok(button, `Missing button: ${label}`);
    assert.ok(button.props.onPress);
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
    const error = run.states[2];
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
  const pending = run.states[3];
  assert.ok(pending && typeof pending === 'object');
  assert.deepEqual({ ...pending }, photo);
  run.setOnline(true);
  await run.press('Retry verification');
  assert.deepEqual(run.calls, ['camera', 'detector', 'submit']);
  assert.equal(run.states[3], null);
});
