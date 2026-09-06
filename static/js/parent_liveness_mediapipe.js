import { FaceLandmarker, FilesetResolver } from '/static/vendor/mediapipe/vision_bundle.mjs';

const OPEN_MAX = 0.22;
const CLOSED_MIN = 0.58;
const SAMPLE_MS = 75;
const CLOSED_WINDOW_MS = 1200;

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
let timer = null;
let verified = false;
let phase = 'WAIT_OPEN';
let closedAt = 0;
let stableOpenFrames = 0;
let stableClosedFrames = 0;
let lastVideoTime = -1;

function stopCamera() {
  if (timer) window.clearInterval(timer);
  timer = null;
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

function capture() {
  if (verified || !video.videoWidth || !video.videoHeight) return;
  verified = true;
  canvas.width = video.videoWidth;
  canvas.height = video.videoHeight;
  const ctx = canvas.getContext('2d');
  ctx.translate(canvas.width, 0);
  ctx.scale(-1, 1);
  ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
  const data = canvas.toDataURL('image/jpeg', 0.9);
  selfie.value = data;
  preview.src = data;
  preview.style.display = 'block';
  video.style.display = 'none';
  oval.style.border = '3px solid #22C55E';
  hud.textContent = '✓ REAL BLINK CAPTURED';
  btn.disabled = false;
  stopCamera();
}

function updateBlinkState(left, right) {
  const bothOpen = left < OPEN_MAX && right < OPEN_MAX;
  const bothClosed = left > CLOSED_MIN && right > CLOSED_MIN;
  const now = performance.now();

  if (phase === 'WAIT_OPEN') {
    stableOpenFrames = bothOpen ? stableOpenFrames + 1 : 0;
    if (stableOpenFrames >= 3) {
      phase = 'WAIT_CLOSED';
      stableClosedFrames = 0;
      hud.textContent = 'BLINK NATURALLY';
    }
    return;
  }

  if (phase === 'WAIT_CLOSED') {
    stableClosedFrames = bothClosed ? stableClosedFrames + 1 : 0;
    if (stableClosedFrames >= 2) {
      phase = 'WAIT_REOPEN';
      closedAt = now;
      stableOpenFrames = 0;
      hud.textContent = 'OPEN YOUR EYES';
    }
    return;
  }

  if (phase === 'WAIT_REOPEN') {
    if (now - closedAt > CLOSED_WINDOW_MS) {
      phase = 'WAIT_OPEN';
      stableOpenFrames = 0;
      stableClosedFrames = 0;
      hud.textContent = 'LOOK AT CAMERA';
      return;
    }
    stableOpenFrames = bothOpen ? stableOpenFrames + 1 : 0;
    if (stableOpenFrames >= 2) capture();
  }
}

async function analyzeFrame() {
  if (verified || !faceLandmarker || !video.videoWidth || video.readyState < 2) return;
  if (video.currentTime === lastVideoTime) return;
  lastVideoTime = video.currentTime;

  const result = faceLandmarker.detectForVideo(video, performance.now());
  const faces = result.faceBlendshapes || [];
  if (faces.length !== 1) {
    hud.textContent = faces.length > 1 ? 'ONE FACE ONLY' : 'CENTER YOUR FACE';
    phase = 'WAIT_OPEN';
    stableOpenFrames = 0;
    stableClosedFrames = 0;
    return;
  }

  const categories = faces[0].categories || [];
  const left = blendshapeScore(categories, 'eyeBlinkLeft');
  const right = blendshapeScore(categories, 'eyeBlinkRight');
  updateBlinkState(left, right);
}

async function start() {
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
      minFaceDetectionConfidence: 0.65,
      minFacePresenceConfidence: 0.65,
      minTrackingConfidence: 0.65,
    });

    stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'user', width: { ideal: 640 }, height: { ideal: 480 } },
      audio: false,
    });
    video.srcObject = stream;
    await video.play();
    hud.textContent = 'LOOK AT CAMERA';
    timer = window.setInterval(() => {
      analyzeFrame().catch(() => fail('Face landmark verification failed. Reload and retry with camera permission.'));
    }, SAMPLE_MS);
  } catch (error) {
    console.error('LittleNet liveness initialization failed', error);
    fail('Camera and real blink verification are required. Enable camera access, then reload this page.');
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
