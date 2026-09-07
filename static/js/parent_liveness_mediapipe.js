import { FaceLandmarker, FilesetResolver } from '/static/vendor/mediapipe/vision_bundle.mjs';

// Parent liveness uses two independent signals:
// 1) MediaPipe eye-blink blendshapes, and
// 2) a dynamically calibrated eye-aspect-ratio (EAR) from face landmarks.
// Fixed blink thresholds alone were too brittle across webcams, lighting and faces.
const CALIBRATION_FRAMES = 12;
const CLOSED_RATIO = 0.62;
const REOPEN_RATIO = 0.82;
const BLEND_CLOSED = 0.50;
const BLEND_OPEN = 0.40;
const MIN_BLINK_MS = 45;
const MAX_BLINK_MS = 1500;
const MAX_TRANSIENT_ERRORS = 6;

const video = document.getElementById('liveVideo');
const preview = document.getElementById('livePreview');
const canvas = document.getElementById('liveCanvas');
const selfie = document.getElementById('selfieData');
const hud = document.getElementById('liveHud');
const oval = document.getElementById('liveOval');
const btn = document.getElementById('finishBtn');
const cameraError = document.getElementById('cameraError');
const form = document.getElementById('livenessForm');

let stream = null;
let faceLandmarker = null;
let rafId = null;
let verified = false;
let phase = 'WAIT_OPEN';
let closedAt = 0;
let closedFrames = 0;
let openFrames = 0;
let lastVideoTime = -1;
let calibration = [];
let openEarBaseline = null;
let transientErrors = 0;

function stopCamera() {
  if (rafId !== null) cancelAnimationFrame(rafId);
  rafId = null;
  if (stream) stream.getTracks().forEach((track) => track.stop());
  stream = null;
}

function fail(message = 'Camera/liveness verification is unavailable. Reload and try again.') {
  stopCamera();
  cameraError.textContent = message;
  cameraError.style.display = 'block';
  hud.textContent = 'LIVENESS REQUIRED';
  btn.disabled = true;
}

function blendshapeScore(categories, name) {
  const row = (categories || []).find((item) => item.categoryName === name || item.displayName === name);
  return row ? Number(row.score || 0) : 0;
}

function distance(a, b) {
  if (!a || !b) return 0;
  const dx = Number(a.x || 0) - Number(b.x || 0);
  const dy = Number(a.y || 0) - Number(b.y || 0);
  const dz = Number(a.z || 0) - Number(b.z || 0);
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

function eyeAspectRatio(points, ids) {
  const [outer, upperOuter, upperInner, inner, lowerInner, lowerOuter] = ids.map((id) => points[id]);
  const horizontal = distance(outer, inner);
  if (!horizontal) return 0;
  const verticalA = distance(upperOuter, lowerOuter);
  const verticalB = distance(upperInner, lowerInner);
  return (verticalA + verticalB) / (2 * horizontal);
}

function median(values) {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

function resetBlinkSequence({ keepCalibration = true } = {}) {
  closedAt = 0;
  closedFrames = 0;
  openFrames = 0;
  if (keepCalibration && openEarBaseline) {
    phase = 'WAIT_CLOSED';
    hud.textContent = 'BLINK ONCE NATURALLY';
  } else {
    phase = 'WAIT_OPEN';
    calibration = [];
    openEarBaseline = null;
    hud.textContent = 'KEEP EYES OPEN';
  }
}

function capture() {
  if (verified || !video.videoWidth || !video.videoHeight) return;
  verified = true;
  canvas.width = video.videoWidth;
  canvas.height = video.videoHeight;
  const ctx = canvas.getContext('2d');
  ctx.translate(canvas.width, 0);
  ctx.scale(-1, 1);
  ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
  const data = canvas.toDataURL('image/jpeg', 0.92);
  selfie.value = data;
  preview.src = data;
  preview.style.display = 'block';
  video.style.display = 'none';
  oval.style.border = '3px solid #22C55E';
  hud.textContent = '✓ LIVE BLINK CAPTURED';
  btn.disabled = false;
  stopCamera();
}

function updateBlinkState(ear, blinkScore) {
  const now = performance.now();

  if (phase === 'WAIT_OPEN') {
    // Learn the person's normal open-eye geometry before accepting a blink.
    if (ear > 0.10 && ear < 0.50 && blinkScore < BLEND_OPEN) {
      calibration.push(ear);
      hud.textContent = `KEEP EYES OPEN · ${Math.min(100, Math.round((calibration.length / CALIBRATION_FRAMES) * 100))}%`;
    }
    if (calibration.length >= CALIBRATION_FRAMES) {
      openEarBaseline = median(calibration.slice(-CALIBRATION_FRAMES));
      phase = 'WAIT_CLOSED';
      hud.textContent = 'BLINK ONCE NATURALLY';
    }
    return;
  }

  const earClosed = openEarBaseline ? ear < openEarBaseline * CLOSED_RATIO : false;
  const earOpen = openEarBaseline ? ear > openEarBaseline * REOPEN_RATIO : false;
  const eyesClosed = earClosed || blinkScore >= BLEND_CLOSED;
  const eyesOpen = earOpen && blinkScore <= BLEND_OPEN;

  if (phase === 'WAIT_CLOSED') {
    closedFrames = eyesClosed ? closedFrames + 1 : 0;
    if (closedFrames >= 2) {
      closedAt = now;
      phase = 'WAIT_REOPEN';
      openFrames = 0;
      hud.textContent = 'OPEN YOUR EYES';
    }
    return;
  }

  if (phase === 'WAIT_REOPEN') {
    const duration = now - closedAt;
    if (duration > MAX_BLINK_MS) {
      resetBlinkSequence({ keepCalibration: true });
      return;
    }
    openFrames = eyesOpen ? openFrames + 1 : 0;
    if (openFrames >= 2 && duration >= MIN_BLINK_MS) capture();
  }
}

function processResult(result) {
  const landmarks = result.faceLandmarks || [];
  if (landmarks.length !== 1) {
    hud.textContent = landmarks.length > 1 ? 'ONE FACE ONLY' : 'CENTER YOUR FACE';
    if (phase !== 'WAIT_OPEN') resetBlinkSequence({ keepCalibration: true });
    return;
  }

  const points = landmarks[0];
  if (!points || points.length < 388) {
    throw new Error('face_landmarks_incomplete');
  }

  // Standard MediaPipe Face Mesh eye landmark indices.
  const leftEar = eyeAspectRatio(points, [33, 160, 158, 133, 153, 144]);
  const rightEar = eyeAspectRatio(points, [362, 385, 387, 263, 373, 380]);
  const ear = (leftEar + rightEar) / 2;

  const blendFaces = result.faceBlendshapes || [];
  const categories = blendFaces.length === 1 ? (blendFaces[0].categories || []) : [];
  const leftBlink = blendshapeScore(categories, 'eyeBlinkLeft');
  const rightBlink = blendshapeScore(categories, 'eyeBlinkRight');
  const blinkScore = (leftBlink + rightBlink) / 2;

  updateBlinkState(ear, blinkScore);
}

function scheduleFrameLoop() {
  rafId = requestAnimationFrame(async () => {
    if (verified || !faceLandmarker || !stream) return;
    try {
      if (video.readyState >= 2 && video.videoWidth && video.currentTime !== lastVideoTime) {
        lastVideoTime = video.currentTime;
        const result = faceLandmarker.detectForVideo(video, performance.now());
        processResult(result);
        transientErrors = 0;
      }
    } catch (error) {
      transientErrors += 1;
      console.warn('LittleNet liveness frame error', error);
      if (transientErrors >= MAX_TRANSIENT_ERRORS) {
        fail('Face landmark verification stopped unexpectedly. Reload and retry with camera permission and good lighting.');
        return;
      }
    }
    scheduleFrameLoop();
  });
}

async function start() {
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
    fail('This browser does not provide secure camera access. Use a modern browser or the LittleNet Android app.');
    return;
  }

  try {
    hud.textContent = 'LOADING FACE CHECK…';
    const fileset = await FilesetResolver.forVisionTasks('/static/vendor/mediapipe/wasm');
    faceLandmarker = await FaceLandmarker.createFromOptions(fileset, {
      baseOptions: {
        modelAssetPath: '/static/vendor/mediapipe/face_landmarker.task',
        delegate: 'CPU',
      },
      runningMode: 'VIDEO',
      numFaces: 1,
      outputFaceBlendshapes: true,
      minFaceDetectionConfidence: 0.55,
      minFacePresenceConfidence: 0.55,
      minTrackingConfidence: 0.55,
    });

    stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 } },
      audio: false,
    });
    video.srcObject = stream;
    await video.play();
    resetBlinkSequence({ keepCalibration: false });
    scheduleFrameLoop();
  } catch (error) {
    console.error('LittleNet liveness initialization failed', error);
    fail('Camera and live blink verification could not start. Allow camera access, then reload this page.');
  }
}

form.addEventListener('submit', (event) => {
  if (!verified || !selfie.value) {
    event.preventDefault();
    hud.textContent = 'COMPLETE A LIVE BLINK FIRST';
    return;
  }
  btn.disabled = true;
  btn.textContent = 'Verifying adult & anti-spoof…';
});

window.addEventListener('beforeunload', () => {
  stopCamera();
  if (faceLandmarker) faceLandmarker.close();
});

start();
