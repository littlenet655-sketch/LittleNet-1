/**
 * Behavior tests for src/deviceAuth/parentAuthGate.ts.
 *
 * The gate keeps an in-memory ~5-minute parent authorization window backed by
 * Android system authentication. These tests mock the bridge module
 * (src/deviceAuth/parentDeviceAuth) and react-native's AppState via the
 * CommonJS module loader so the gate can be exercised in plain node.
 *
 * Run: npx tsc -p tsconfig.tests.json && node --test test-dist/tests/parentAuthGate.test.js
 */
import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const NodeModule: any = require('node:module');
const originalLoad: any = NodeModule._load;

type Gate = typeof import('../src/deviceAuth/parentAuthGate');

interface CallCounts {
  check: number;
  authenticate: number;
}

interface BridgeMock {
  calls: CallCounts;
  checkParentDeviceAuth: () => Promise<Record<string, unknown>>;
  authenticateParentDevice: () => Promise<Record<string, unknown>>;
}

function makeBridgeMock(): BridgeMock {
  const calls: CallCounts = { check: 0, authenticate: 0 };
  return {
    calls,
    checkParentDeviceAuth: async () => {
      calls.check++;
      return {
        biometricAvailable: true,
        biometricEnrolled: true,
        deviceCredentialAvailable: true,
        canAuthenticate: true,
      };
    },
    authenticateParentDevice: async () => {
      calls.authenticate++;
      return { success: true, method: 'BIOMETRIC' };
    },
  };
}

let appStateListeners: Array<(status: string) => void> = [];

function installMocks(bridgeMock: BridgeMock): void {
  appStateListeners = [];
  const rnStub = {
    NativeModules: {},
    Platform: { OS: 'android' },
    AppState: {
      addEventListener: (_event: string, handler: (status: string) => void) => {
        appStateListeners.push(handler);
        return {
          remove: () => {
            appStateListeners = appStateListeners.filter((h) => h !== handler);
          },
        };
      },
    },
  };
  NodeModule._load = function (request: string, parent: unknown, isMain: unknown): unknown {
    if (request === 'react-native') return rnStub;
    if (request === './parentDeviceAuth' || request.endsWith('/parentDeviceAuth')) return bridgeMock;
    return originalLoad.call(this, request, parent, isMain);
  };
}

function loadGate(): Gate {
  const gatePath: string = require.resolve('../src/deviceAuth/parentAuthGate');
  delete require.cache[gatePath];
  return require(gatePath) as Gate;
}

let gate: Gate;
let bridge: BridgeMock;

function freshGate(): void {
  bridge = makeBridgeMock();
  installMocks(bridge);
  gate = loadGate();
  gate.__resetParentGate();
}

beforeEach(() => {
  NodeModule._load = originalLoad;
});

describe('parentAuthGate authorization window', () => {
  it('opens a window on success and reuses it without re-prompting', async () => {
    freshGate();
    assert.deepStrictEqual(await gate.requireParentAuth(), { ok: true });
    assert.equal(gate.isParentAuthorized(), true);
    assert.ok(gate.parentAuthRemainingMs() > 0);
    assert.deepStrictEqual(await gate.requireParentAuth(), { ok: true });
    assert.equal(bridge.calls.authenticate, 1);
    assert.equal(bridge.calls.check, 1);
  });

  it('prompts again after the window times out', async () => {
    freshGate();
    let now = 1_000_000;
    gate.__setParentGateClock(() => now);
    assert.deepStrictEqual(await gate.requireParentAuth(), { ok: true });
    assert.equal(bridge.calls.authenticate, 1);

    now += gate.PARENT_AUTH_WINDOW_MS + 1;
    assert.equal(gate.isParentAuthorized(), false);
    assert.equal(gate.parentAuthRemainingMs(), 0);
    assert.deepStrictEqual(await gate.requireParentAuth(), { ok: true });
    assert.equal(bridge.calls.authenticate, 2);
  });

  it('keeps the window valid just before expiry', async () => {
    freshGate();
    let now = 5_000_000;
    gate.__setParentGateClock(() => now);
    await gate.requireParentAuth();
    now += gate.PARENT_AUTH_WINDOW_MS - 1;
    assert.deepStrictEqual(await gate.requireParentAuth(), { ok: true });
    assert.equal(bridge.calls.authenticate, 1);
  });

  it('invalidates the window when the app backgrounds', async () => {
    freshGate();
    await gate.requireParentAuth();
    assert.equal(gate.isParentAuthorized(), true);
    gate.handleParentGateAppState('background');
    assert.equal(gate.isParentAuthorized(), false);
    assert.deepStrictEqual(await gate.requireParentAuth(), { ok: true });
    assert.equal(bridge.calls.authenticate, 2);
  });

  it('invalidates through the installed AppState listener on inactive', async () => {
    freshGate();
    const uninstall = gate.installParentGateInvalidation();
    try {
      await gate.requireParentAuth();
      assert.equal(appStateListeners.length, 1);
      const handler = appStateListeners[0];
      assert.ok(handler, 'expected a registered AppState handler');
      (handler as (status: string) => void)('inactive');
      assert.equal(gate.isParentAuthorized(), false);
    } finally {
      uninstall();
    }
  });

  it('does not invalidate on active/foreground', async () => {
    freshGate();
    await gate.requireParentAuth();
    gate.handleParentGateAppState('active');
    assert.equal(gate.isParentAuthorized(), true);
  });

  it('invalidateParentAuth forces a fresh prompt (logout / session change)', async () => {
    freshGate();
    await gate.requireParentAuth();
    gate.invalidateParentAuth();
    assert.equal(gate.isParentAuthorized(), false);
    assert.deepStrictEqual(await gate.requireParentAuth(), { ok: true });
    assert.equal(bridge.calls.authenticate, 2);
  });

  it('returns no_credential without prompting when the device has no screen lock', async () => {
    freshGate();
    bridge.checkParentDeviceAuth = async () => {
      bridge.calls.check++;
      return {
        biometricAvailable: false,
        biometricEnrolled: false,
        deviceCredentialAvailable: false,
        canAuthenticate: false,
      };
    };
    assert.deepStrictEqual(await gate.requireParentAuth(), { ok: false, reason: 'no_credential' });
    assert.equal(bridge.calls.authenticate, 0);
    assert.equal(gate.isParentAuthorized(), false);
  });

  it('surfaces user cancellation distinctly from failure', async () => {
    freshGate();
    bridge.authenticateParentDevice = async () => {
      bridge.calls.authenticate++;
      return { success: false, error: 'user_cancel' };
    };
    assert.deepStrictEqual(await gate.requireParentAuth(), { ok: false, reason: 'cancelled' });
    assert.equal(gate.isParentAuthorized(), false);
  });

  it('surfaces lockout as a failure with details', async () => {
    freshGate();
    bridge.authenticateParentDevice = async () => {
      bridge.calls.authenticate++;
      return { success: false, error: 'lockout', message: 'Too many attempts' };
    };
    assert.deepStrictEqual(await gate.requireParentAuth(), {
      ok: false,
      reason: 'failed',
      error: 'lockout',
      message: 'Too many attempts',
    });
    assert.equal(gate.isParentAuthorized(), false);
  });

  it('surfaces a failed capability check as a failure', async () => {
    freshGate();
    bridge.checkParentDeviceAuth = async () => {
      throw new Error('service down');
    };
    assert.deepStrictEqual(await gate.requireParentAuth(), {
      ok: false,
      reason: 'failed',
      error: 'failure',
      message: 'Could not query device authentication.',
    });
    assert.equal(gate.isParentAuthorized(), false);
  });

  it('keeps the window in memory only (no persistent storage)', async () => {
    freshGate();
    await gate.requireParentAuth();
    await gate.requireParentAuth();
    assert.equal(bridge.calls.authenticate, 1);

    const src: string = readFileSync(require.resolve('../src/deviceAuth/parentAuthGate'), 'utf8');
    assert.ok(!src.includes('AsyncStorage'), 'gate must not use AsyncStorage');
    assert.ok(!src.includes('SecureStore'), 'gate must not use SecureStore');
    assert.ok(!src.includes('expo-secure-store'), 'gate must not use expo-secure-store');

    gate.__resetParentGate();
    assert.equal(gate.isParentAuthorized(), false);
  });

  it('notifies subscribers on authorize and invalidate', async () => {
    freshGate();
    let notifications = 0;
    const unsubscribe = gate.subscribeParentGate(() => {
      notifications++;
    });
    try {
      await gate.requireParentAuth();
      assert.equal(notifications, 1);
      gate.invalidateParentAuth();
      assert.equal(notifications, 2);
      gate.invalidateParentAuth(); // already invalid: no extra notification
      assert.equal(notifications, 2);
    } finally {
      unsubscribe();
    }
  });
});
