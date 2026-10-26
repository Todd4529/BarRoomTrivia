import QRCode from 'qrcode';
import confetti from 'canvas-confetti';
import mqtt from 'mqtt';
import { createClient } from '@supabase/supabase-js';
import { fetchRealtimeTriviaQuestions, getLocalQuestions, initOpenTdbToken, resetQuestionHistory, ALL_SPECIFIC_GENRES, syncWeeklyTriviaInBackground } from './triviaDatabase.js';

// Global error handler — prevents blank screen on mobile by logging errors
window.addEventListener('error', (e) => {
  console.error('[App Error]', e.message, e.filename, e.lineno);
});
window.addEventListener('unhandledrejection', (e) => {
  console.warn('[Unhandled Promise]', e.reason);
});

const SUPABASE_URL = 'https://tzdikvbvdvgjaiznqkcd.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR6ZGlrdmJ2ZHZnamFpem5xa2NkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDAxNTMwNzksImV4cCI6MjA1NTcyOTA3OX0.12k3oY1iO6wYk_hJ8e2V0n1QY-B5-v1XyPZ47_3q1W8';
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

let mqttClient = null;
let liveRoomChannel = null;
let liveDefaultChannel = null;
let liveGlobalChannel = null;

// State & Broadcast Channel
const BROADCAST_CHANNEL_NAME = 'bar_rooms_trivia_TRIV';
let channel;
try {
  channel = new BroadcastChannel(BROADCAST_CHANNEL_NAME);
} catch (e) {
  // Fallback for environments where BroadcastChannel is unavailable
  channel = { postMessage: () => {}, onmessage: null, close: () => {} };
}

const safeStorage = {
  getItem: (key) => {
    try { return localStorage.getItem(key); } catch (_) { return null; }
  },
  setItem: (key, val) => {
    try { localStorage.setItem(key, val); } catch (_) {}
  },
  removeItem: (key) => {
    try { localStorage.removeItem(key); } catch (_) {}
  }
};

const initialUrlParams = new URLSearchParams(window.location.search);
const urlRoomCode = initialUrlParams.get('room') || initialUrlParams.get('room_id') || initialUrlParams.get('user_code');
let currentRoomCode = (urlRoomCode || safeStorage.getItem('bar_trivia_current_room') || 'TRIV').toUpperCase();
if (urlRoomCode) {
  safeStorage.setItem('bar_trivia_current_room', currentRoomCode);
}
let currentPlayer = null;
let currentQuestionIndex = 0;
let currentRound = 1;
let selectedQuestionDuration = parseInt(safeStorage.getItem('bar_trivia_question_duration') || '20', 10); // Default 20 seconds
let selectedInterRoundDuration = parseInt(safeStorage.getItem('bar_trivia_inter_round_duration') || '120', 10); // 30, 60, 120 (Default), 180, 240, 300, 600
let selectedDifficulty = 'Standard'; // Kids, Beginner, Standard, Advanced
let selectedGenreQueue = []; // Up to 10 genres in order
let currentVenueName = safeStorage.getItem('bar_trivia_venue_name') || "OUR PUB";
let customBarLogoUrl = safeStorage.getItem('bar_trivia_logo_url') || null;
let isAutomatedEngineRunning = false;
let autoEngineTimeout = null;
let countdownInterval = null;
let modalCountdownInterval = null;
let tvNextQCountdownInterval = null;
let tvWinnerOverlayTimeout = null;
let winnerCountdownInterval = null;
let lastFanfareCelebrationKey = null;
let lastFanfarePlayEpoch = 0;
let preGameCountdownInterval = null;
let lbScrollInterval = null;
let promoCarouselInterval = null;
let currentPromoSlideIndex = 1;
let playerChoiceSubmitted = null;
let isCurrentQuestionScored = false;
let lastScoredQuestionKey = null;
let currentQuestionAnswers = {};
let mockPlayerTimeouts = [];
let currentRoundQuestions = [];

let remainingTimerSeconds = 0;
let totalTimerDuration = 20;
let timerEndsAtGlobalMs = 0;
let questionStartTimeLocal = 0;
let currentQuestionData = null;
let currentGameState = 'LOBBY';

// Ad Display Signage Mode State - Default OFF when first loading host controls
let isAdModeActive = false;
let adSlideDurationSeconds = parseInt(safeStorage.getItem('bar_trivia_ad_duration') || '10', 10);
let customAdSlides = [];
let currentAdSlideIndex = 0;
let adRotationTimeout = null;
let adProgressBarInterval = null;

// Screen WakeLock to prevent mobile browsers (Safari / Chrome) from sleeping during game
let screenWakeLock = null;
async function requestScreenWakeLock() {
  try {
    if ('wakeLock' in navigator) {
      screenWakeLock = await navigator.wakeLock.request('screen');
      console.log('[WakeLock] Screen wake lock acquired');
      screenWakeLock.addEventListener('release', () => {
        console.log('[WakeLock] Screen wake lock released');
        screenWakeLock = null;
      });
    }
  } catch (err) {
    console.warn('[WakeLock] Unable to acquire wake lock:', err);
  }
}

let triggerActiveSessionSync = null;
let triggerHostActiveSessionSync = null;

async function handleAppVisibilityResume() {
  if (!screenWakeLock) {
    await requestScreenWakeLock();
  }
  if (!mqttClient || !mqttClient.connected) {
    try { initRealtimeEngine(); } catch (_) {}
  }
  if (typeof triggerActiveSessionSync === 'function') {
    triggerActiveSessionSync();
  }
  if (typeof triggerHostActiveSessionSync === 'function') {
    triggerHostActiveSessionSync();
  }
  if (currentPlayer && currentPlayer.nickname) {
    broadcastRealtimeEvent('request_state_sync', { room_code: currentRoomCode });
  }
}

document.addEventListener('visibilitychange', async () => {
  if (document.visibilityState === 'visible') {
    await handleAppVisibilityResume();
  }
});
window.addEventListener('focus', () => {
  handleAppVisibilityResume();
});
window.addEventListener('pageshow', () => {
  handleAppVisibilityResume();
});

// ==========================================
// 1. GAME SHOW SOUND ENGINE (Web Audio API)
// Synthesized in-browser with zero network latency
// ==========================================
let audioCtx = null;
let isSoundEffectsEnabled = false; // Disabled permanently per user request

function getAudioContext() {
  if (!audioCtx) {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (AudioContextClass) {
      audioCtx = new AudioContextClass();
    }
  }
  return audioCtx;
}

function unlockAudioContext(playConfirmation = true) {
  isSoundEffectsEnabled = true;
  safeStorage.setItem('bar_trivia_sound_enabled', 'true');
  const toggleSound = document.getElementById('host-toggle-sound');
  if (toggleSound) toggleSound.checked = true;

  const ctx = getAudioContext();
  if (!ctx) return Promise.resolve(false);

  // Play a 1-sample silent Web Audio buffer directly to unlock hardware on iOS / WebKit / Android TVs
  try {
    const silentBuf = ctx.createBuffer(1, 1, 22050);
    const src = ctx.createBufferSource();
    src.buffer = silentBuf;
    src.connect(ctx.destination);
    src.start(0);
  } catch (_) {}

  return ctx.resume().then(() => {
    console.log('[Audio] AudioContext successfully resumed & unlocked!');
    updateTvAudioUI();
    if (playConfirmation) {
      playSound('correct');
    }
    return true;
  }).catch(err => {
    console.warn('[Audio] Failed to resume AudioContext:', err);
    updateTvAudioUI();
    return false;
  });
}

function unlockAudioOnInteraction() {
  const events = ['click', 'touchstart', 'touchend', 'pointerdown', 'pointerup', 'keydown', 'keyup'];
  const unlock = () => {
    const ctx = getAudioContext();
    if (!ctx) return;

    try {
      const buf = ctx.createBuffer(1, 1, 22050);
      const src = ctx.createBufferSource();
      src.buffer = buf;
      src.connect(ctx.destination);
      src.start(0);
    } catch (_) {}

    ctx.resume().then(() => {
      updateTvAudioUI();
      if (ctx.state === 'running') {
        events.forEach(e => {
          window.removeEventListener(e, unlock);
          document.removeEventListener(e, unlock);
        });
      }
    }).catch(() => {});
  };

  events.forEach(e => {
    window.addEventListener(e, unlock, { passive: true });
    document.addEventListener(e, unlock, { passive: true });
  });
}
unlockAudioOnInteraction();

function updateTvAudioUI() {
  const btnTvSound = document.getElementById('btn-tv-toggle-sound');
  const banner = document.getElementById('tv-audio-unlock-banner');
  if (btnTvSound) btnTvSound.classList.add('hidden');
  if (banner) banner.classList.add('hidden');
  return;

  const isSuspended = !ctx || (ctx.state === 'suspended');
  if (isSuspended) {
    if (btnTvSound) {
      btnTvSound.className = 'tv-toggle-btn tv-sound-toggle-btn needs-unlock';
      btnTvSound.textContent = '🔇 Click to Enable Sound';
      btnTvSound.setAttribute('title', 'Browser has audio paused. Click anywhere to enable game sound effects.');
    }
    const activeView = document.body.getAttribute('data-view') || 'tv';
    if (banner && activeView === 'tv') {
      banner.classList.remove('hidden');
    }
  } else {
    if (btnTvSound) {
      btnTvSound.className = 'tv-toggle-btn tv-sound-toggle-btn sound-on';
      btnTvSound.textContent = '🔊 Sound ON';
      btnTvSound.setAttribute('title', 'Game sound effects active. Click to mute.');
    }
    if (banner) banner.classList.add('hidden');
  }
}

let cachedFanfareBuffer = null;
let cachedCorrectBuffer = null;

function getCrowdApplauseBuffer(ctx, isGrandFanfare) {
  if (isGrandFanfare && cachedFanfareBuffer) return cachedFanfareBuffer;
  if (!isGrandFanfare && cachedCorrectBuffer) return cachedCorrectBuffer;

  const sampleRate = ctx.sampleRate || 44100;
  const durationSec = isGrandFanfare ? 3.6 : 1.6;
  const numSamples = Math.floor(sampleRate * durationSec);
  const buffer = ctx.createBuffer(2, numSamples, sampleRate);
  const left = buffer.getChannelData(0);
  const right = buffer.getChannelData(1);

  let seed = isGrandFanfare ? 98765 : 43210;
  function rnd() {
    seed = (seed * 16807) % 2147483647;
    return (seed / 2147483647) * 2 - 1;
  }

  // 1. LAYER 1: MULTI-PERSON ACOUSTIC HANDCLAPPING (Authentic flesh palm-on-palm applause)
  // Each clap is a double-transient flesh impact:
  // - Transient 1: High snap of fingers hitting palm (0-8ms, noise filtered by skin)
  // - Transient 2: Fleshy heel impact (4-35ms, body resonance 370-480Hz + cupped palm cavity resonance 1000-1300Hz)
  const numClappers = isGrandFanfare ? 26 : 16;
  const people = [];
  for (let p = 0; p < numClappers; p++) {
    people.push({
      pan: (p / (numClappers - 1)) * 1.6 - 0.8,
      rate: 0.25 + (Math.abs(rnd()) * 0.12), // Natural human clap rate (~3.0 to 4.0 claps/sec)
      start: 0.01 + (Math.abs(rnd()) * 0.22),
      fBody: 370 + (Math.abs(rnd()) * 110),
      fCavity: 1000 + (Math.abs(rnd()) * 300),
      vol: 0.45 + (Math.abs(rnd()) * 0.35)
    });
  }

  people.forEach(person => {
    let t = person.start;
    while (t < durationSec - 0.12) {
      const clapTime = t + (rnd() * 0.016);
      const clapIdx = Math.floor(clapTime * sampleRate);
      if (clapIdx >= numSamples) break;

      const roomEnv = t < 0.3 ? (t / 0.3) : (t < (durationSec - 1.1) ? 1.0 : Math.max(0, 1.0 - (t - (durationSec - 1.1)) / 1.0));
      const clapGain = person.vol * roomEnv * (0.75 + Math.abs(rnd()) * 0.5);

      const lPan = (1 - person.pan) * 0.5;
      const rPan = (1 + person.pan) * 0.5;

      const clapSamples = Math.floor(sampleRate * 0.045);
      for (let s = 0; s < clapSamples; s++) {
        const outIdx = clapIdx + s;
        if (outIdx >= numSamples) break;
        const sTime = s / sampleRate;

        // Double transient
        const snap = sTime < 0.008 ? rnd() * Math.exp(-sTime * 650) * 0.5 : 0;
        const mainSlap = sTime >= 0.004 ? rnd() * Math.exp(-(sTime - 0.004) * 140) * 0.7 : 0;
        const bodyThump = Math.sin(2 * Math.PI * person.fBody * sTime) * Math.exp(-sTime * 180) * 0.4;
        const cavity = Math.sin(2 * Math.PI * person.fCavity * sTime) * Math.exp(-sTime * 240) * 0.3;

        const val = (snap + mainSlap + bodyThump + cavity) * clapGain * 0.16;
        left[outIdx] += val * lPan;
        right[outIdx] += val * rPan;
      }

      t += person.rate + (rnd() * 0.024);
    }
  });

  // 2. LAYER 2: COLLECTIVE CROWD ROAR (Formant-filtered vocal wash across the room)
  let noiseFilter = 0;
  const roarSustain = isGrandFanfare ? 1.8 : 0.8;
  const roarDecay = isGrandFanfare ? 1.5 : 0.7;
  for (let i = 0; i < numSamples; i++) {
    const t = i / sampleRate;
    const roarEnv = t < 0.28 ? (t / 0.28) : (t < roarSustain ? 1.0 : Math.max(0, 1.0 - (t - roarSustain) / roarDecay));
    if (roarEnv <= 0) continue;

    const rawNoise = rnd();
    noiseFilter = noiseFilter * 0.88 + rawNoise * 0.12;

    const v1 = Math.sin(2 * Math.PI * 650 * t) * noiseFilter * 0.5;
    const v2 = Math.sin(2 * Math.PI * 1250 * t) * noiseFilter * 0.35;
    const wash = (noiseFilter * 0.6 + v1 + v2) * roarEnv * 0.15;

    left[i] += wash * 0.52;
    right[i] += wash * 0.48;
  }

  // 3. LAYER 3: DISTINCT INDIVIDUAL EXCITED VOCAL CHEERS ("WOOO!", "YEAAAH!", "WHOO-HOO!") - AUTHENTIC CLAPPING AND CHEERING
  const cheers = isGrandFanfare ? [
    { start: 0.08, dur: 1.15, f0: 230, f1: 340, formants: [680, 1300, 2500], pan: -0.35, vol: 0.16 },
    { start: 0.18, dur: 1.35, f0: 190, f1: 270, formants: [750, 1600, 2700], pan: 0.40, vol: 0.17 },
    { start: 0.32, dur: 0.95, f0: 280, f1: 410, formants: [620, 1150, 2400], pan: 0.10, vol: 0.14 },
    { start: 0.45, dur: 1.25, f0: 165, f1: 220, formants: [580, 1050, 2200], pan: -0.50, vol: 0.15 }
  ] : [
    { start: 0.06, dur: 0.85, f0: 220, f1: 310, formants: [720, 1450, 2600], pan: -0.20, vol: 0.15 },
    { start: 0.14, dur: 0.95, f0: 185, f1: 250, formants: [680, 1300, 2500], pan: 0.30, vol: 0.16 }
  ];
  const cheerVoices = cheers;

  cheerVoices.forEach(ch => {
    const startIdx = Math.floor(ch.start * sampleRate);
    const durSamples = Math.floor(ch.dur * sampleRate);
    const lPan = (1 - ch.pan) * 0.5;
    const rPan = (1 + ch.pan) * 0.5;

    for (let s = 0; s < durSamples; s++) {
      const outIdx = startIdx + s;
      if (outIdx >= numSamples) break;
      const sT = s / durSamples;
      const tSec = s / sampleRate;

      const pitch = ch.f0 + (ch.f1 - ch.f0) * Math.sin(sT * Math.PI * 0.85);
      const vibrato = Math.sin(2 * Math.PI * 5.8 * tSec) * 4.5;
      const instFreq = pitch + vibrato;

      const ph = 2 * Math.PI * instFreq * tSec;
      const glottal = Math.sin(ph) * 0.5 + Math.sin(ph * 2) * 0.25 + Math.sin(ph * 3) * 0.12;

      let vocalFormant = 0;
      ch.formants.forEach((f, idx) => {
        const weight = [0.5, 0.35, 0.2][idx] || 0.2;
        vocalFormant += Math.sin(2 * Math.PI * f * tSec) * weight;
      });

      const breath = rnd() * 0.18;
      const amp = sT < 0.15 ? (sT / 0.15) : (sT < 0.75 ? 1.0 : (1.0 - (sT - 0.75) / 0.25));
      const voice = (glottal * 0.45 + vocalFormant * glottal * 0.45 + breath) * amp * ch.vol;

      left[outIdx] += voice * lPan;
      right[outIdx] += voice * rPan;
    }
  });

  let peak = 0;
  for (let i = 0; i < numSamples; i++) {
    peak = Math.max(peak, Math.abs(left[i]), Math.abs(right[i]));
  }
  const scale = peak > 0 ? (0.85 / peak) : 1.0;
  for (let i = 0; i < numSamples; i++) {
    left[i] = Math.tanh(left[i] * scale);
    right[i] = Math.tanh(right[i] * scale);
  }

  if (isGrandFanfare) cachedFanfareBuffer = buffer;
  else cachedCorrectBuffer = buffer;

  return buffer;
}

function playSound(type) {
  if (!isSoundEffectsEnabled) return; // Sound disabled completely per user request
  return;
  const ctx = getAudioContext();
  if (!ctx) return;

  const executePlay = () => {
    try {
      const now = Math.max(ctx.currentTime, 0.005);

      if (type === 'tick') {
        // Authentic mechanical ticking clock sound (escapement click + acoustic body + gear catch)
        const remaining = typeof param === 'number' ? param : 5;
        const isTick = (remaining % 2 !== 0); // Alternate Tick / Tock like a clock pendulum
        const baseFreq = isTick ? 1450 : 920;

        // 1. Sharp mechanical escapement click impulse (high-frequency burst)
        const clickLen = Math.floor(ctx.sampleRate * 0.015);
        const clickBuf = ctx.createBuffer(1, clickLen, ctx.sampleRate);
        const clickData = clickBuf.getChannelData(0);
        for (let i = 0; i < clickLen; i++) {
          clickData[i] = (Math.random() * 2 - 1) * Math.exp(-i / (ctx.sampleRate * 0.003));
        }
        const clickSrc = ctx.createBufferSource();
        clickSrc.buffer = clickBuf;
        const clickFilter = ctx.createBiquadFilter();
        clickFilter.type = 'bandpass';
        clickFilter.frequency.setValueAtTime(isTick ? 2800 : 2000, now);
        clickFilter.Q.setValueAtTime(5.0, now);
        const clickGain = ctx.createGain();
        clickGain.gain.setValueAtTime(0.42, now);
        clickGain.gain.linearRampToValueAtTime(0.0001, now + 0.015);
        clickSrc.connect(clickFilter);
        clickFilter.connect(clickGain);
        clickGain.connect(ctx.destination);
        clickSrc.start(now);

        // 2. Resonant wood/brass clock housing body decay
        const osc1 = ctx.createOscillator();
        const gain1 = ctx.createGain();
        osc1.type = 'sine';
        osc1.frequency.setValueAtTime(baseFreq, now);
        osc1.frequency.exponentialRampToValueAtTime(baseFreq * 0.65, now + 0.028);
        gain1.gain.setValueAtTime(0.38, now);
        gain1.gain.exponentialRampToValueAtTime(0.0001, now + 0.028);
        osc1.connect(gain1);
        gain1.connect(ctx.destination);
        osc1.start(now);
        osc1.stop(now + 0.028);

        // 3. Subtle escapement gear catch recoil at +36ms
        const rebTime = now + 0.036;
        const osc2 = ctx.createOscillator();
        const gain2 = ctx.createGain();
        osc2.type = 'triangle';
        osc2.frequency.setValueAtTime(baseFreq * 1.5, rebTime);
        osc2.frequency.exponentialRampToValueAtTime(baseFreq, rebTime + 0.012);
        gain2.gain.setValueAtTime(0.18, rebTime);
        gain2.gain.exponentialRampToValueAtTime(0.0001, rebTime + 0.012);
        osc2.connect(gain2);
        gain2.connect(ctx.destination);
        osc2.start(rebTime);
        osc2.stop(rebTime + 0.012);
      }
      if (type === 'tap') {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'triangle';
        osc.frequency.setValueAtTime(560, now);
        osc.frequency.linearRampToValueAtTime(320, now + 0.06);
        gain.gain.setValueAtTime(0.30, now);
        gain.gain.linearRampToValueAtTime(0.0001, now + 0.06);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.06);
      }
      if (type === 'question_start' || type === 'start') {
        // Uplifting 3-tone game show chord stinger: C5 (523Hz), E5 (659Hz), G5 (784Hz)
        [ { f: 523.25, t: 0, d: 0.10, g: 0.35 }, { f: 659.25, t: 0.08, d: 0.12, g: 0.38 }, { f: 783.99, t: 0.16, d: 0.28, g: 0.42 } ].forEach(n => {
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'triangle';
          osc.frequency.setValueAtTime(n.f, now + n.t);
          gain.gain.setValueAtTime(0.0001, now + n.t);
          gain.gain.linearRampToValueAtTime(n.g, now + n.t + 0.02);
          gain.gain.linearRampToValueAtTime(0.0001, now + n.t + n.d);
          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start(now + n.t);
          osc.stop(now + n.t + n.d);
        });
      }
      if (type === 'fanfare') {
        // GRAND INTER-ROUND VICTORY CELEBRATION: Realistic crowd cheering & human handclapping
        const buffer = getCrowdApplauseBuffer(ctx, true);
        const src = ctx.createBufferSource();
        const gNode = ctx.createGain();
        gNode.gain.setValueAtTime(0.85, now);
        src.buffer = buffer;
        src.connect(gNode);
        gNode.connect(ctx.destination);
        src.start(now);
      }
      if (type === 'correct') {
        // CORRECT ANSWER CELEBRATION: Realistic crowd applause & cheer
        const buffer = getCrowdApplauseBuffer(ctx, false);
        const src = ctx.createBufferSource();
        const gNode = ctx.createGain();
        gNode.gain.setValueAtTime(0.80, now);
        src.buffer = buffer;
        src.connect(gNode);
        gNode.connect(ctx.destination);
        src.start(now);
      }
      if (type === 'wrong') {
        // Classic descending buzzer (240Hz -> 140Hz)
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'sawtooth';
        osc.frequency.setValueAtTime(240, now);
        osc.frequency.linearRampToValueAtTime(140, now + 0.28);
        gain.gain.setValueAtTime(0.32, now);
        gain.gain.linearRampToValueAtTime(0.0001, now + 0.28);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now);
        osc.stop(now + 0.28);
      }
      if (type === 'buzz') {
        // Authoritative game-show buzzer: dual dissonant sawtooth (150Hz + 158Hz)
        [150, 158].forEach(freq => {
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'sawtooth';
          osc.frequency.setValueAtTime(freq, now);
          gain.gain.setValueAtTime(0.25, now);
          gain.gain.linearRampToValueAtTime(0.0001, now + 0.35);
          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start(now);
          osc.stop(now + 0.35);
        });
      }
    } catch (err) {
      console.warn('[Audio] Synthesizer error:', err);
    }
  };

  if (ctx.state === 'suspended') {
    ctx.resume().then(() => {
      updateTvAudioUI();
      executePlay();
    }).catch(() => {
      updateTvAudioUI();
    });
  } else {
    executePlay();
  }
}

function setSoundEffectsEnabled(enabled, shouldBroadcast = true) {
  isSoundEffectsEnabled = false; // Permanently disabled
  safeStorage.setItem('bar_trivia_sound_enabled', 'false');
  const toggleSound = document.getElementById('host-toggle-sound');
  if (toggleSound) toggleSound.checked = false;
  updateTvAudioUI();

  if (shouldBroadcast) {
    const payload = {
      isSoundEffectsEnabled,
      is_sound_effects_enabled: isSoundEffectsEnabled,
      is_sound_enabled: isSoundEffectsEnabled,
      sound_effects_enabled: isSoundEffectsEnabled,
      room_code: (currentRoomCode || 'TRIV').toUpperCase()
    };
    try {
      channel.postMessage({ type: 'SOUND_TOGGLED', payload });
      broadcastRealtimeEvent('sound_toggled', payload);
      broadcastRealtimeEvent('sound_effects_toggled', payload);
    } catch (_) {}

    try {
      if (typeof supabase !== 'undefined' && supabase) {
        supabase.from('game_sessions').upsert({
          room_code: (currentRoomCode || 'TRIV').toUpperCase(),
          is_sound_effects_enabled: isSoundEffectsEnabled,
          updated_at: new Date().toISOString()
        }, { onConflict: 'room_code' }).then(() => {}).catch(() => {});
      }
    } catch (_) {}
  }
}

// ==========================================
// 2. NETWORK RESILIENCE & RECONNECTION BANNER
// ==========================================
let networkBannerTimeout = null;

function showNetworkStatus(status, message, autoHideMs = 3000) {
  const banner = document.getElementById('network-status-banner');
  const text = document.getElementById('network-status-text');
  if (!banner || !text) return;

  clearTimeout(networkBannerTimeout);
  banner.className = `network-status-banner ${status}`;
  text.textContent = message;
  banner.classList.remove('hidden');

  if (autoHideMs > 0) {
    networkBannerTimeout = setTimeout(() => {
      banner.classList.add('hidden');
    }, autoHideMs);
  }
}

window.addEventListener('online', () => {
  showNetworkStatus('connected', '✓ Reconnected to Network', 2500);
  if (currentRoomCode) {
    broadcastRealtimeEvent('request_state_sync', { room_code: currentRoomCode });
  }
});

window.addEventListener('offline', () => {
  showNetworkStatus('offline', '⚠️ Network Connection Lost', 0);
});

// Robust Host Heartbeat Engine (Epoch Timestamp-Based, Immune to Mobile OS Throttling)
let hostTargetEpochMs = 0;
let hostEngineState = 'IDLE'; // 'PRE_GAME', 'QUESTION_READING', 'QUESTION_ACTIVE', 'QUESTION_REVIEW', 'ROUND_SUMMARY'
let hostGamePlayMode = 'Auto'; // 'Auto' (default) or 'Manual'
let hostHeartbeatInterval = null;

// Preserved Pause Snapshot for Resuming Where Left Off
let pausedHostEngineState = 'IDLE';
let pausedHostGamePlayMode = 'Auto';
let pausedRemainingQuestionSeconds = 0;
let pausedQuestionData = null;
let pausedQuestionIndex = 0;
let pausedRound = 1;

function startHostHeartbeatLoop() {
  if (hostHeartbeatInterval) clearInterval(hostHeartbeatInterval);
  hostHeartbeatInterval = setInterval(checkHostEngineTick, 200);
}

function stopHostHeartbeatLoop() {
  if (hostHeartbeatInterval) {
    clearInterval(hostHeartbeatInterval);
    hostHeartbeatInterval = null;
  }
  hostTargetEpochMs = 0;
  hostEngineState = 'IDLE';
}

// Auto Select Tracking across games
let shuffledAutoGenres = [...ALL_SPECIFIC_GENRES].sort(() => 0.5 - Math.random());

// GENRE ICON MAPPING (30 TOTAL GENRES)
const genreIconMap = {
  'Homebrewing Beer': '🍺',
  'Home Repair': '🛠️',
  'Finance': '💵',
  'Travel': '✈️',
  'Health': '🩺',
  'Music Lyrics': '🎶',
  'Pop Culture & Music': '🎵',
  'Movies & Hollywood': '🎬',
  '80s & 90s Nostalgia': '📺',
  'Science & Technology': '🧪',
  'World History': '📜',
  'World Geography': '🌍',
  'Sports & Stadiums': '⚽',
  'Beer, Wine & Spirits': '🍻',
  'Food & Culinary': '🍕',
  'Video Games & Gaming': '🎮',
  'Classic Literature': '📚',
  'Comics & Superheroes': '🦸',
  'Art & Architecture': '🎨',
  'Wildlife & Nature': '🦁',
  'Astronomy & Space': '🚀',
  'Automotive & Racing': '🏎️',
  'Rock & Roll Classics': '🎸',
  'Sitcoms & TV Dramas': '📺',
  'Internet & Meme Culture': '🌐',
  'Famous Landmarks': '🏙️',
  'Mind Benders & Riddles': '🧠',
  'Business & Brands': '💼',
  'Broadway & Theater': '🎭',
  'General Knowledge': '💡',
  'Auto Select': '⚡',
  'Random': '🎲'
};

// FUNNY RESULT STATEMENTS POOLS
const funnyCorrectQuotes = [
  "Nailed it! Your brain cells are firing on all cylinders! 🧠🔥",
  "Look at you, Einstein! Did you google that under the table? 😏",
  "BAM! High score locked in! Give yourself a victory cheer! 🍺🎉",
  "Genius mode activated! The bar is in awe of your intelligence! 🚀",
  "Boom! You hit that answer like a pro pub quizzer! 🎯",
  "Correct! Somebody buy this trivia mastermind a beer! 🍻",
  "Flex those brain muscles! You got it 100% right! 💪✨"
];

const funnyWrongQuotes = [
  "Oof! Missed that one. We'll blame it on the jukebox! 🎵😅",
  "Nice try! Even Wikipedia makes mistakes sometimes... 📖😜",
  "Swing and a miss! Don't worry, the next question is your specialty! ⚾💥",
  "Wrong! But hey, confidence is 90% of the game! 😎",
  "Not quite! Blame it on the room lighting or bad advice! 💡😂",
  "Close, but no cigar! Shake it off and dominate the next round! 🔮",
  "Ouch! The trivia gods demanded a sacrifice. Next one is yours! ⚡"
];

// REAL PLAYER PURGE HELPER: Filters out mock tests and host user (todd4529)
function isFictitiousPlayer(nickname) {
  if (!nickname) return true;
  const lower = nickname.toString().trim().toLowerCase();
  if (lower.startsWith('mock-test-') || lower.startsWith('test-mock-')) return true;
  if (lower === 'host' || lower === 'host user' || lower === 'todd4529' || lower.startsWith('host-') || lower.startsWith('host_')) return true;
  const savedHostEmail = safeStorage.getItem('bar_trivia_host_email');
  if (savedHostEmail) {
    const hostUser = savedHostEmail.split('@')[0].toLowerCase();
    if (lower === hostUser || lower === savedHostEmail.toLowerCase()) return true;
  }
  return false;
}

// INITIALIZE LEADERBOARD FOR REAL PLAYERS ONLY
let playersLeaderboard = [];

async function refreshHostPlayers() {
  const btnRefresh = document.getElementById('btn-refresh-players');
  if (btnRefresh) {
    btnRefresh.disabled = true;
    btnRefresh.innerHTML = '<span class="spin-icon">🔄</span> Refreshing...';
    btnRefresh.classList.add('refreshing');
  }

  const normRoom = (currentRoomCode || 'TRIV').trim().toUpperCase();

  // 1. Broadcast request state sync so connected player devices immediately re-announce themselves
  try {
    channel.postMessage({ type: 'REQUEST_STATE_SYNC', payload: { room_code: normRoom } });
    broadcastRealtimeEvent('request_state_sync', { room_code: normRoom });
  } catch (_) {}

  // 2. Fetch fresh roster from Supabase players table
  try {
    if (supabase) {
      let { data, error } = await supabase
        .from('players')
        .select('*')
        .or(`room_code.eq.${normRoom},room_code.eq.TRIV`)
        .order('cumulative_score', { ascending: false });

      if (error || !data || data.length === 0) {
        const fallbackRes = await supabase
          .from('players')
          .select('*')
          .eq('room_code', 'TRIV')
          .order('cumulative_score', { ascending: false });
        if (fallbackRes.data && fallbackRes.data.length > 0) {
          data = fallbackRes.data;
          error = null;
        }
      }

      if (!error && Array.isArray(data)) {
        const realPlayers = data.filter(p => p && p.nickname && !isFictitiousPlayer(p.nickname));
        for (const p of realPlayers) {
          const nick = (p.nickname || '').trim();
          if (!nick) continue;
          const score = Number(p.cumulative_score ?? p.score ?? 0);
          const existing = playersLeaderboard.find(x => x.nickname.toLowerCase() === nick.toLowerCase());
          if (existing) {
            existing.score = Math.max(Number(existing.score || 0), score);
            existing.cumulative_score = Math.max(Number(existing.cumulative_score || 0), score);
            existing.streak = p.streak || existing.streak || 0;
            existing.is_connected = p.is_connected !== false;
          } else {
            playersLeaderboard.push({
              id: p.id || nick,
              player_uid: p.player_uid || nick,
              room_code: normRoom,
              nickname: nick,
              score: score,
              cumulative_score: score,
              streak: p.streak || 0,
              is_connected: p.is_connected !== false,
            });
          }
        }
      }
    }
  } catch (err) {
    console.warn('[Leaderboard] Refresh players error:', err);
  }

  // 3. Purge any fictitious players & re-render host roster and leaderboard
  playersLeaderboard = playersLeaderboard.filter(p => p && p.nickname && !isFictitiousPlayer(p.nickname));
  renderLeaderboard();
  renderHostPlayersRoster();
  updateHostEngineUI(currentGameState);

  const hostPlayersRoom = document.getElementById('host-players-room-code');
  if (hostPlayersRoom) hostPlayersRoom.textContent = normRoom;

  setTimeout(() => {
    if (btnRefresh) {
      btnRefresh.disabled = false;
      btnRefresh.innerHTML = '🔄 Refresh';
      btnRefresh.classList.remove('refreshing');
    }
  }, 600);
}

function loadInitialPlayers() {
  refreshHostPlayers();
}
window.refreshHostPlayers = refreshHostPlayers;
window.loadInitialPlayers = loadInitialPlayers;

// PROGRESSIVE WEB APP (PWA) SUPPORT & INSTALL PROMPTS
let deferredPwaInstallPrompt = null;

function initPwaSupport() {
  // 1. Register Service Worker on HTTPS or localhost
  if ('serviceWorker' in navigator && (window.location.protocol === 'https:' || window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')) {
    window.addEventListener('load', () => {
      const swPath = window.location.pathname.toLowerCase().includes('/barroomtrivia') ? '/BarRoomTrivia/sw.js' : './sw.js';
      navigator.serviceWorker.register(swPath).then((reg) => {
        console.log('[PWA] Service Worker registered with scope:', reg.scope);
      }).catch((err) => {
        console.warn('[PWA] Service Worker registration failed:', err);
      });
    });
  }

  const isStandalone = window.navigator.standalone === true || window.matchMedia('(display-mode: standalone)').matches;
  const isIos = /iphone|ipad|ipod/.test(window.navigator.userAgent.toLowerCase());

  const installBanner = document.getElementById('host-pwa-install-banner');
  const btnBannerInstall = document.getElementById('btn-banner-install-pwa');
  const btnBannerDismiss = document.getElementById('btn-banner-dismiss-pwa');
  const btnSettingsInstall = document.getElementById('btn-install-pwa-host');
  const iosInstructions = document.getElementById('host-pwa-ios-instructions');
  const installedBadge = document.getElementById('host-pwa-installed-badge');

  if (isStandalone) {
    if (installBanner) installBanner.classList.add('hidden');
    if (btnSettingsInstall) btnSettingsInstall.classList.add('hidden');
    if (iosInstructions) iosInstructions.classList.add('hidden');
    if (installedBadge) installedBadge.classList.remove('hidden');
    return;
  }

  // If not standalone, configure install triggers
  const isBannerDismissed = safeStorage.getItem('host_pwa_banner_dismissed') === 'true';

  if (isIos) {
    // iOS Safari does not support beforeinstallprompt; show instructional guidance
    if (btnSettingsInstall) {
      btnSettingsInstall.textContent = '📲 How to Add to Home Screen';
      btnSettingsInstall.onclick = () => {
        if (iosInstructions) {
          iosInstructions.classList.toggle('hidden');
          iosInstructions.scrollIntoView({ behavior: 'smooth' });
        }
      };
    }
    if (installBanner && !isBannerDismissed) {
      installBanner.classList.remove('hidden');
      if (btnBannerInstall) {
        btnBannerInstall.textContent = 'How to Add';
        btnBannerInstall.onclick = () => {
          alert('To add to Home Screen:\n1. Tap the Share button at bottom of Safari\n2. Scroll down and tap "Add to Home Screen"');
        };
      }
    }
  } else {
    // Android / Desktop Chrome support beforeinstallprompt
    window.addEventListener('beforeinstallprompt', (e) => {
      e.preventDefault();
      deferredPwaInstallPrompt = e;
      if (installBanner && !isBannerDismissed) {
        installBanner.classList.remove('hidden');
      }
      if (btnSettingsInstall) {
        btnSettingsInstall.classList.remove('hidden');
      }
    });

    const triggerInstall = () => {
      if (deferredPwaInstallPrompt) {
        deferredPwaInstallPrompt.prompt();
        deferredPwaInstallPrompt.userChoice.then((choiceResult) => {
          if (choiceResult.outcome === 'accepted') {
            console.log('[PWA] User accepted the install prompt');
            if (installBanner) installBanner.classList.add('hidden');
            if (installedBadge) installedBadge.classList.remove('hidden');
            if (btnSettingsInstall) btnSettingsInstall.classList.add('hidden');
          }
          deferredPwaInstallPrompt = null;
        });
      } else {
        alert('To install this app on your device:\nOpen your browser menu (⋮) and tap "Install App" or "Add to Home screen".');
      }
    };

    if (btnBannerInstall) btnBannerInstall.onclick = triggerInstall;
    if (btnSettingsInstall) btnSettingsInstall.onclick = triggerInstall;
  }

  if (btnBannerDismiss) {
    btnBannerDismiss.onclick = () => {
      if (installBanner) installBanner.classList.add('hidden');
      safeStorage.setItem('host_pwa_banner_dismissed', 'true');
    };
  }

  window.addEventListener('appinstalled', () => {
    console.log('[PWA] Host app successfully installed');
    if (installBanner) installBanner.classList.add('hidden');
    if (installedBadge) installedBadge.classList.remove('hidden');
    if (btnSettingsInstall) btnSettingsInstall.classList.add('hidden');
    if (iosInstructions) iosInstructions.classList.add('hidden');
  });
}

// MAIN APP INITIALIZER
function initApp() {
  initPwaSupport();
  initOpenTdbToken();
  syncWeeklyTriviaInBackground();
  initNavigation();
  initAuthView();
  initQrCodes();
  initHostControls();
  initHostAdSettings();
  initPlayerControls();
  initTvModeToggle();
  initBroadcastChannelListeners();
  initRealtimeEngine();
  initIndicatorClicks();
  
  onVenueNameUpdated({ venueName: currentVenueName });
  if (customBarLogoUrl) {
    onLogoUpdated({ logoUrl: customBarLogoUrl });
    updateHostLogoPreview(customBarLogoUrl);
  }

  const savedNick = safeStorage.getItem('bar_trivia_player_nickname');
  if (savedNick && isFictitiousPlayer(savedNick)) {
    safeStorage.removeItem('bar_trivia_player_nickname');
  }
  playersLeaderboard = playersLeaderboard.filter(p => p && p.nickname && !isFictitiousPlayer(p.nickname));

  loadAdSlidesAndInit();
  startPromoCarouselRotation();
  startLeaderboardAutoScroll();
  renderLeaderboard();
  loadInitialPlayers();
  // Continuous background sync ensures players always populate even if WebSockets dropped
  setInterval(() => {
    loadInitialPlayers();
  }, 4000);
}

// HOST AUTHENTICATION LOGIC (Mobile & Web)
function initAuthView() {
  const form = document.getElementById('form-host-auth');
  const emailInput = document.getElementById('auth-email-input');
  const passwordInput = document.getElementById('auth-password-input');
  const btnSubmit = document.getElementById('btn-submit-auth');
  const btnQuickConnect = document.getElementById('btn-quick-connect');
  const btnToggleSignMode = document.getElementById('btn-toggle-sign-mode');
  const btnGoogle = document.getElementById('btn-oauth-google');
  const btnApple = document.getElementById('btn-oauth-apple');
  const alertBox = document.getElementById('auth-status-alert');
  const tvCodePill = document.getElementById('auth-tv-code-pill');
  const tvCodeLabel = document.getElementById('auth-tv-code-label');
  const subtitleText = document.getElementById('auth-subtitle-text');

  let isSignUpMode = false;

  // Extract device_token and user_code from query params, hash or pathname
  const urlParams = new URLSearchParams(window.location.search);
  const hashQuery = window.location.hash.includes('?')
    ? window.location.hash.split('?')[1]
    : (window.location.hash.startsWith('#') && window.location.hash.includes('=') ? window.location.hash.substring(1) : '');
  const hashParams = new URLSearchParams(hashQuery);

  let deviceToken = urlParams.get('device_token') || urlParams.get('deviceToken') || hashParams.get('device_token') || hashParams.get('deviceToken');
  let userCode = urlParams.get('user_code') || urlParams.get('userCode') || urlParams.get('room') || urlParams.get('room_id') || hashParams.get('user_code') || hashParams.get('userCode') || hashParams.get('room') || hashParams.get('room_id');

  // Pre-fill email from safeStorage if available
  const savedHostEmail = safeStorage.getItem('bar_trivia_host_email');
  if (savedHostEmail && emailInput && !emailInput.value) {
    emailInput.value = savedHostEmail;
  }

  if (userCode) {
    currentRoomCode = userCode.trim().toUpperCase();
    safeStorage.setItem('bar_trivia_current_room', currentRoomCode);
    if (tvCodeLabel && tvCodePill) {
      tvCodeLabel.textContent = userCode;
      tvCodePill.classList.remove('hidden');
    }
  }

  function showAlert(msg, isError = true) {
    if (!alertBox) return;
    alertBox.textContent = msg;
    alertBox.className = `auth-alert ${isError ? 'error' : 'success'}`;
    alertBox.classList.remove('hidden');
  }

  function hideAlert() {
    if (alertBox) alertBox.classList.add('hidden');
  }

  btnToggleSignMode?.addEventListener('click', (e) => {
    e.preventDefault();
    isSignUpMode = !isSignUpMode;
    if (isSignUpMode) {
      subtitleText.textContent = 'Create a Host Account to Connect TV';
      btnSubmit.textContent = 'CREATE ACCOUNT & CONNECT TV';
      btnToggleSignMode.innerHTML = 'Already have an account? <strong>Sign In</strong>';
    } else {
      subtitleText.textContent = 'Sign In as Host to Connect TV Display';
      btnSubmit.textContent = 'SIGN IN & CONNECT TV';
      btnToggleSignMode.innerHTML = "Don't have an account? <strong>Sign Up</strong>";
    }
  });

  // Pre-subscribe Realtime channels immediately so websocket is warm
  const activeToken = deviceToken || `tv_auth_${Date.now()}`;
  const authChannel = supabase.channel(`device_auth_${activeToken}`);
  authChannel.subscribe();
  const roomChannel = supabase.channel('room_TRIV');
  roomChannel.subscribe();
  let userCodeChannel = null;
  if (userCode) {
    userCodeChannel = supabase.channel(`room_${userCode.trim().toUpperCase()}`);
    userCodeChannel.subscribe();
  }
  const globalChannel = supabase.channel('tv_pairing');
  globalChannel.subscribe();

  function broadcastDeviceAuth(user) {
    const token = activeToken;
    const targetRoom = (userCode || currentRoomCode || 'TRIV').trim().toUpperCase();
    const payload = {
      device_token: token,
      user_id: user.id,
      user_code: targetRoom,
      room_code: targetRoom,
      is_ad_mode_active: isAdModeActive,
      isAdModeActive: isAdModeActive,
      user_info: {
        email: user.email || 'Host User',
        display_name: user.user_metadata?.display_name || user.email?.split('@')[0] || 'Host',
      },
      timestamp: new Date().toISOString()
    };

    function sendAll() {
      try {
        authChannel.send({
          type: 'broadcast',
          event: 'device_authorized',
          payload
        });
        roomChannel.send({
          type: 'broadcast',
          event: 'device_authorized',
          payload
        });
        userCodeChannel?.send({
          type: 'broadcast',
          event: 'device_authorized',
          payload
        });
        globalChannel.send({
          type: 'broadcast',
          event: 'device_authorized',
          payload
        });
      } catch (err) {
        console.warn('Realtime broadcast error:', err);
      }

      // Also publish via direct MQTT device token topic so TV receives instantly
      if (mqttClient && mqttClient.connected) {
        try {
          const jsonStr = JSON.stringify({
            ...payload,
            event: 'device_authorized',
            type: 'DEVICE_AUTHORIZED'
          });
          mqttClient.publish(`device_auth_${token}`, jsonStr);
          mqttClient.publish(`barrooms_trivia/room_${targetRoom}`, jsonStr);
          mqttClient.publish('barrooms_trivia/room_TRIV', jsonStr);
          mqttClient.publish('tv_pairing', jsonStr);
        } catch (e) {
          console.warn('[MQTT device auth publish error]:', e);
        }
      }

      try {
        broadcastRealtimeEvent('device_authorized', payload);
      } catch (_) {}

      try {
        channel.postMessage({
          type: 'DEVICE_AUTHORIZED',
          ...payload
        });
      } catch (_) {}
    }

    // Upsert into game_sessions for both TRIV and the specific room code
    try {
      supabase.from('game_sessions').upsert([
        {
          room_code: 'TRIV',
          host_id: user.id,
          status: 'waiting_for_host',
          is_ad_mode_active: isAdModeActive,
          updated_at: new Date().toISOString()
        },
        {
          room_code: targetRoom,
          host_id: user.id,
          status: 'waiting_for_host',
          is_ad_mode_active: isAdModeActive,
          updated_at: new Date().toISOString()
        }
      ], { onConflict: 'room_code' }).catch(() => {});
    } catch (_) {}

    // Send immediately and retry multiple times
    sendAll();
    setTimeout(sendAll, 300);
    setTimeout(sendAll, 800);
    setTimeout(sendAll, 1600);

    // If host has ads active before starting game, broadcast ad mode immediately
    if (isAdModeActive) {
      broadcastAdModeChange();
      syncTvSignageDisplay();
    }

    // Immediately show success and transition to Host Panel
    showAlert('TV Connected! Opening Host Controls...', false);
    if (btnQuickConnect) btnQuickConnect.textContent = 'CONNECTED! OPENING...';
    if (btnSubmit) btnSubmit.textContent = 'CONNECTED! OPENING...';
    setTimeout(() => {
      switchView('host');
    }, 700);
  }

  function quickConnectAsHost(e) {
    if (e) e.preventDefault();
    hideAlert();
    const email = emailInput?.value.trim() || safeStorage.getItem('bar_trivia_host_email') || 'host@venue.com';
    if (emailInput && !emailInput.value) {
      emailInput.value = email;
    }

    if (btnQuickConnect) {
      btnQuickConnect.disabled = true;
      btnQuickConnect.textContent = 'CONNECTING TV...';
    }
    if (btnSubmit) {
      btnSubmit.disabled = true;
    }

    const hostId = safeStorage.getItem('bar_trivia_host_id') || ('host_' + Date.now());
    const finalUser = {
      id: hostId,
      email: email,
      user_metadata: { display_name: email.split('@')[0] || 'Host' }
    };

    safeStorage.setItem('bar_trivia_host_email', email);
    safeStorage.setItem('bar_trivia_host_id', finalUser.id);

    broadcastDeviceAuth(finalUser);
  }

  async function handleAuthAction(e) {
    if (e) e.preventDefault();
    hideAlert();
    const email = emailInput?.value.trim() || safeStorage.getItem('bar_trivia_host_email') || 'host@venue.com';
    const password = passwordInput?.value || '123456';

    if (btnQuickConnect) btnQuickConnect.disabled = true;
    btnSubmit.disabled = true;
    btnSubmit.textContent = isSignUpMode ? 'CREATING...' : 'CONNECTING...';

    try {
      let authUser = null;

      if (isSignUpMode) {
        const signUpRes = await supabase.auth.signUp({ email, password }).catch(() => ({ error: null }));
        if (signUpRes.data?.user) {
          authUser = signUpRes.data.user;
        } else {
          const loginRes = await supabase.auth.signInWithPassword({ email, password }).catch(() => ({ error: null }));
          if (loginRes.data?.user) {
            authUser = loginRes.data.user;
          }
        }
      } else {
        const loginRes = await supabase.auth.signInWithPassword({ email, password }).catch(() => ({ error: null }));
        if (loginRes.data?.user) {
          authUser = loginRes.data.user;
        } else {
          const signUpRes = await supabase.auth.signUp({ email, password }).catch(() => ({ error: null }));
          if (signUpRes.data?.user) {
            authUser = signUpRes.data.user;
          }
        }
      }

      const finalUser = authUser || {
        id: 'host_' + Date.now(),
        email: email,
        user_metadata: { display_name: email.split('@')[0] }
      };

      safeStorage.setItem('bar_trivia_host_email', email);
      safeStorage.setItem('bar_trivia_host_id', finalUser.id);

      broadcastDeviceAuth(finalUser);
    } catch (err) {
      console.warn('Auth fallback triggered:', err);
      const fallbackUser = {
        id: 'host_' + Date.now(),
        email: email,
        user_metadata: { display_name: email.split('@')[0] }
      };
      broadcastDeviceAuth(fallbackUser);
    }
  }

  // Expose handlers globally for reliable HTML onclick/onsubmit triggering
  window.quickConnectAsHost = quickConnectAsHost;
  window.handleHostAuthSubmit = handleAuthAction;

  // Ensure inputs are interactive and clean
  if (emailInput) {
    emailInput.disabled = false;
    emailInput.readOnly = false;
  }
  if (passwordInput) {
    passwordInput.disabled = false;
    passwordInput.readOnly = false;
  }

  // Attach DOM event listeners
  btnQuickConnect?.addEventListener('click', quickConnectAsHost);
  form?.addEventListener('submit', handleAuthAction);
  btnSubmit?.addEventListener('click', handleAuthAction);
}

// TV DISPLAY MODE TOGGLE (PROMO CAROUSEL VS LIVE QUESTION STAGE)
function initTvModeToggle() {
  const btnPromo = document.getElementById('btn-tv-toggle-promo');
  const btnLive = document.getElementById('btn-tv-toggle-live');
  const tvPromoScreen = document.getElementById('tv-promo-screen');
  const tvLiveGrid = document.getElementById('tv-live-grid');

  btnPromo?.addEventListener('click', (e) => {
    e.preventDefault();
    btnPromo.classList.add('active');
    btnLive?.classList.remove('active');
    tvLiveGrid?.classList.add('hidden');

    const tvAdScreen = document.getElementById('tv-ad-signage-screen');
    const allSlides = getAllActiveAdSlides();
    if (isAdModeActive && allSlides.length > 0) {
      if (tvPromoScreen) tvPromoScreen.classList.add('hidden');
      if (tvAdScreen) tvAdScreen.classList.remove('hidden');
      startTvAdSignageRotation();
    } else {
      if (tvAdScreen) tvAdScreen.classList.add('hidden');
      stopTvAdSignageRotation();
      tvPromoScreen?.classList.remove('hidden');
    }
  });

  btnLive?.addEventListener('click', (e) => {
    e.preventDefault();
    btnLive?.classList.add('active');
    btnPromo?.classList.remove('active');
    tvPromoScreen?.classList.add('hidden');
    const tvAdScreen = document.getElementById('tv-ad-signage-screen');
    if (tvAdScreen) tvAdScreen.classList.add('hidden');
    stopTvAdSignageRotation();
    tvLiveGrid?.classList.remove('hidden');

    if (currentQuestionData) {
      const now = Date.now();
      const remainingSecs = (timerEndsAtGlobalMs && (timerEndsAtGlobalMs - now) > 2000)
        ? Math.ceil((timerEndsAtGlobalMs - now) / 1000)
        : (remainingTimerSeconds > 2 ? remainingTimerSeconds : (Number(selectedQuestionDuration) || 20));

      onQuestionStart({
        questionData: currentQuestionData,
        roundNumber: currentRound,
        questionNumberInRound: (currentQuestionIndex % 10) + 1,
        durationSeconds: remainingSecs,
        difficulty: selectedDifficulty
      });
    }
  });

  const btnTvSound = document.getElementById('btn-tv-toggle-sound');
  btnTvSound?.addEventListener('click', (e) => {
    e.preventDefault();
    e.stopPropagation();
    const ctx = getAudioContext();
    if (!isSoundEffectsEnabled || !ctx || ctx.state === 'suspended') {
      unlockAudioContext(true);
    } else {
      setSoundEffectsEnabled(false, true);
      updateTvAudioUI();
    }
  });

  const banner = document.getElementById('tv-audio-unlock-banner');
  const btnUnlock = document.getElementById('btn-tv-unlock-audio');
  banner?.addEventListener('click', () => {
    unlockAudioContext(true);
  });
  btnUnlock?.addEventListener('click', (e) => {
    e.stopPropagation();
    unlockAudioContext(true);
  });

  const tvView = document.getElementById('view-tv');
  tvView?.addEventListener('click', (e) => {
    if (e.target.closest('#btn-tv-back') || e.target.closest('#btn-tv-toggle-sound') || e.target.closest('#btn-tv-toggle-promo') || e.target.closest('#btn-tv-toggle-live') || e.target.closest('.tv-exit-dialog-card') || e.target.closest('.tv-host-qr-card')) return;
    const ctx = getAudioContext();
    if (!ctx || ctx.state === 'suspended') {
      unlockAudioContext(true);
    }
  });

  updateTvAudioUI();
  initTvExitAndRecoveryMenu();
}

// TV EXIT APPLICATION & HOST CONTROL QR RECOVERY MODAL
function initTvExitAndRecoveryMenu() {
  const btnTvBack = document.getElementById('btn-tv-back');
  const tvExitOverlay = document.getElementById('tv-exit-dialog-overlay');
  const btnTvExitCancel = document.getElementById('btn-tv-exit-cancel');
  const btnTvShowHostQr = document.getElementById('btn-tv-show-host-qr');
  const tvHostQrOverlay = document.getElementById('tv-host-qr-modal-overlay');
  const btnTvCloseHostQr = document.getElementById('btn-tv-close-host-qr');
  const btnTvCloseEmptyHostQr = document.getElementById('btn-tv-close-empty-host-qr');
  const tvHostQrActiveCard = document.getElementById('tv-host-qr-active-card');
  const tvHostQrEmptyCard = document.getElementById('tv-host-qr-empty-card');
  const tvHostQrCanvas = document.getElementById('tv-host-qr-canvas');
  const tvHostQrUrlText = document.getElementById('tv-host-qr-url-text');
  const tvHostQrRoomPill = document.getElementById('tv-host-qr-room-pill');
  const tvHostQrRoundPill = document.getElementById('tv-host-qr-round-pill');
  const tvHostQrEmptyRoom = document.getElementById('tv-host-qr-empty-room');

  function openTvExitDialog() {
    if (tvExitOverlay) tvExitOverlay.classList.remove('hidden');
  }

  function closeTvExitDialog() {
    if (tvExitOverlay) tvExitOverlay.classList.add('hidden');
  }

  function showTvHostQrRecovery() {
    closeTvExitDialog();
    const hostBaseUrl = 'https://todd4529.github.io/BarRoomTrivia';
    const hostUrl = `${hostBaseUrl}/?view=host&room=${currentRoomCode}`;

    const isRunning = isAutomatedEngineRunning ||
      (currentQuestionData !== null) ||
      (currentGameState === 'IN PROGRESS' || currentGameState === 'QUESTION_ACTIVE' || currentGameState === 'PRE_GAME') ||
      (hostEngineState && hostEngineState !== 'IDLE');

    if (isRunning) {
      if (tvHostQrRoomPill) tvHostQrRoomPill.textContent = `ROOM: ${currentRoomCode}`;
      if (tvHostQrRoundPill) tvHostQrRoundPill.textContent = `ROUND ${currentRound || 1}`;
      if (tvHostQrUrlText) tvHostQrUrlText.textContent = hostUrl;
      if (tvHostQrCanvas) {
        QRCode.toCanvas(tvHostQrCanvas, hostUrl, { width: 200, margin: 1 }, (err) => {
          if (err) console.error('Host QR render error:', err);
        });
      }
      if (tvHostQrActiveCard) tvHostQrActiveCard.classList.remove('hidden');
      if (tvHostQrEmptyCard) tvHostQrEmptyCard.classList.add('hidden');
    } else {
      if (tvHostQrEmptyRoom) tvHostQrEmptyRoom.textContent = currentRoomCode;
      if (tvHostQrActiveCard) tvHostQrActiveCard.classList.add('hidden');
      if (tvHostQrEmptyCard) tvHostQrEmptyCard.classList.remove('hidden');
    }

    if (tvHostQrOverlay) tvHostQrOverlay.classList.remove('hidden');
  }

  function closeTvHostQrRecovery() {
    if (tvHostQrOverlay) tvHostQrOverlay.classList.add('hidden');
  }

  btnTvBack?.addEventListener('click', (e) => {
    e.preventDefault();
    openTvExitDialog();
  });

  btnTvExitCancel?.addEventListener('click', closeTvExitDialog);
  btnTvShowHostQr?.addEventListener('click', showTvHostQrRecovery);
  btnTvCloseHostQr?.addEventListener('click', closeTvHostQrRecovery);
  btnTvCloseEmptyHostQr?.addEventListener('click', closeTvHostQrRecovery);

  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && document.body.getAttribute('data-view') === 'tv') {
      if (tvHostQrOverlay && !tvHostQrOverlay.classList.contains('hidden')) {
        closeTvHostQrRecovery();
      } else if (tvExitOverlay && !tvExitOverlay.classList.contains('hidden')) {
        closeTvExitDialog();
      } else {
        openTvExitDialog();
      }
    }
  });
}

// 1. NAVIGATION ROUTING & INSTANT VIEW SWITCHING
function switchView(viewName) {
  if (!viewName) return;

  // Toggle player mode on body
  document.body.classList.toggle('player-mode', viewName === 'player');
  document.body.setAttribute('data-view', viewName);

  // 1. Toggle panel visibility
  const panels = document.querySelectorAll('.view-panel');
  panels.forEach(panel => {
    const isTarget = (panel.id === `view-${viewName}`);
    if (isTarget) {
      panel.classList.add('active');
      // Auth panel uses flex layout; others use block
      panel.style.display = (panel.id === 'view-auth') ? 'flex' : 'block';
    } else {
      panel.classList.remove('active');
      panel.style.display = 'none';
    }
  });

  // 2. Toggle top nav tab active state
  const navBtns = document.querySelectorAll('.nav-btn');
  navBtns.forEach(btn => {
    const isMatch = (btn.getAttribute('data-view') === viewName);
    btn.classList.toggle('active', isMatch);
  });

  // 3. Scroll to top
  window.scrollTo(0, 0);

  // 4. TV View specific behavior: Show Live Stage or Ad Signage when switching to TV
  if (viewName === 'tv') {
    updateTvAudioUI();
    const tvPromoScreen = document.getElementById('tv-promo-screen');
    const tvLiveGrid = document.getElementById('tv-live-grid');
    const tvAdScreen = document.getElementById('tv-ad-signage-screen');
    const btnPromo = document.getElementById('btn-tv-toggle-promo');
    const btnLive = document.getElementById('btn-tv-toggle-live');

    if (currentGameState === 'QUESTION_ACTIVE' && currentQuestionData) {
      if (tvAdScreen) tvAdScreen.classList.add('hidden');
      if (tvPromoScreen) tvPromoScreen.classList.add('hidden');
      if (tvLiveGrid) tvLiveGrid.classList.remove('hidden');
      if (btnLive) btnLive.classList.add('active');
      if (btnPromo) btnPromo.classList.remove('active');
      stopTvAdSignageRotation();

      const now = Date.now();
      const remainingSecs = (timerEndsAtGlobalMs && (timerEndsAtGlobalMs - now) > 2000)
        ? Math.ceil((timerEndsAtGlobalMs - now) / 1000)
        : (remainingTimerSeconds > 2 ? remainingTimerSeconds : (Number(selectedQuestionDuration) || 20));

      onQuestionStart({
        questionData: currentQuestionData,
        roundNumber: currentRound,
        questionNumberInRound: (currentQuestionIndex % 10) + 1,
        durationSeconds: remainingSecs,
        difficulty: selectedDifficulty
      });
    } else {
      // Idle / Lobby state:
      const allSlides = getAllActiveAdSlides();
      if (isAdModeActive && allSlides && allSlides.length > 0) {
        if (tvPromoScreen) tvPromoScreen.classList.add('hidden');
        if (tvLiveGrid) tvLiveGrid.classList.add('hidden');
        if (tvAdScreen) tvAdScreen.classList.remove('hidden');
        if (btnPromo) btnPromo.classList.add('active');
        if (btnLive) btnLive.classList.remove('active');
        startTvAdSignageRotation();
      } else {
        if (tvAdScreen) tvAdScreen.classList.add('hidden');
        stopTvAdSignageRotation();
        if (tvLiveGrid) tvLiveGrid.classList.add('hidden');
        if (tvPromoScreen) tvPromoScreen.classList.remove('hidden');
        if (btnPromo) btnPromo.classList.add('active');
        if (btnLive) btnLive.classList.remove('active');
        startPromoCarouselRotation();
      }
    }
  }

  // 4b. Player View specific behavior: Show active question immediately if game in progress
  if (viewName === 'player') {
    hideWinnerModals();
    hideResultModal();
    hideInterQuestionCountdown();
    if (currentQuestionData && (currentGameState === 'QUESTION_ACTIVE' || currentGameState === 'QUESTION_READING')) {
      const now = Date.now();
      const remainingSecs = (timerEndsAtGlobalMs && (timerEndsAtGlobalMs - now) > 2000)
        ? Math.ceil((timerEndsAtGlobalMs - now) / 1000)
        : (remainingTimerSeconds > 2 ? remainingTimerSeconds : (Number(selectedQuestionDuration) || 20));

      onQuestionStart({
        questionData: currentQuestionData,
        roundNumber: currentRound,
        questionNumberInRound: (currentQuestionIndex % 10) + 1,
        durationSeconds: remainingSecs,
        totalTimerDuration: selectedQuestionDuration || 20,
        difficulty: selectedDifficulty
      });
    }
  }

  // 5. Update venue & logo
  onVenueNameUpdated({ venueName: currentVenueName });
  if (customBarLogoUrl) {
    onLogoUpdated({ logoUrl: customBarLogoUrl });
  }

  // 6. Broadcast state sync
  try {
    channel.postMessage({ type: 'REQUEST_STATE_SYNC' });
  } catch (e) {
    console.warn('Broadcast channel sync bypassed:', e);
  }
}

// Expose switchView globally
window.switchView = switchView;

function initNavigation() {
  const navBtns = document.querySelectorAll('.nav-btn');
  const targetCards = document.querySelectorAll('.target-card');
  const popoutPlayerBtn = document.getElementById('btn-popout-player');
  const popoutTvBtn = document.getElementById('btn-popout-tv');

  navBtns.forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const v = btn.getAttribute('data-view');
      if (v) switchView(v);
    });
  });

  targetCards.forEach(card => {
    card.addEventListener('click', (e) => {
      e.preventDefault();
      const v = card.getAttribute('data-view');
      if (v) switchView(v);
    });
  });

  // Browser Back / Forward button support
  window.addEventListener('popstate', (e) => {
    const view = e.state?.view || new URLSearchParams(window.location.search).get('view') || 'auth';
    switchView(view);
  });

  popoutPlayerBtn?.addEventListener('click', (e) => {
    e.preventDefault();
    const basePath = window.location.pathname.replace(/\/index\.html$/, '').replace(/\/+$/, '');
    window.open(`${window.location.origin}${basePath}/?view=player`, '_blank', 'width=420,height=800');
  });

  popoutTvBtn?.addEventListener('click', (e) => {
    e.preventDefault();
    const basePath = window.location.pathname.replace(/\/index\.html$/, '').replace(/\/+$/, '');
    window.open(`${window.location.origin}${basePath}/?view=tv`, '_blank', 'width=1280,height=720');
  });

  // Initial load view resolution (supports search query params, hash-based query params, and subpaths)
  const urlParams = new URLSearchParams(window.location.search);
  const hashQuery = window.location.hash.includes('?')
    ? window.location.hash.split('?')[1]
    : (window.location.hash.startsWith('#') && window.location.hash.includes('=') ? window.location.hash.substring(1) : '');
  const hashParams = new URLSearchParams(hashQuery);

  const roomParam = urlParams.get('room') || urlParams.get('room_id') || urlParams.get('user_code') || hashParams.get('room') || hashParams.get('room_id') || hashParams.get('user_code');
  const deviceToken = urlParams.get('device_token') || urlParams.get('deviceToken') || hashParams.get('device_token') || hashParams.get('deviceToken') || (window.location.hash.includes('device_token=') ? 'yes' : null);
  if (roomParam) {
    currentRoomCode = roomParam.toUpperCase().replace(/[^A-Z0-9-]/g, '');
    const roomInput = document.getElementById('input-room-code');
    if (roomInput) roomInput.value = currentRoomCode;
  }

  const viewParam = urlParams.get('view') || hashParams.get('view');
  const pathname = window.location.pathname.toLowerCase();
  const isPlayPath = pathname.endsWith('/play') || pathname.includes('/play/') || window.location.hash.includes('/play');
  const isTvPath = pathname.endsWith('/tv') || pathname.includes('/tv/') || window.location.hash.includes('/tv');
  const isHostPath = pathname.endsWith('/host') || pathname.includes('/host/') || window.location.hash.includes('/host');
  const isTvAuth = pathname.includes('/tv-auth') || window.location.hash.includes('tv-auth') || !!deviceToken;

  if (viewParam && ['tv', 'player', 'host', 'auth'].includes(viewParam)) {
    switchView(viewParam);
  } else if (isTvAuth) {
    switchView('auth');
  } else if (isTvPath) {
    switchView('tv');
  } else if (isHostPath) {
    switchView('host');
  } else if (isPlayPath || (roomParam && !deviceToken)) {
    switchView('player');
  } else {
    switchView('auth');
  }
}

// Global click delegate to catch inner card clicks (e.g. .target-card or .nav-btn)
document.addEventListener('click', (e) => {
  // Never intercept form controls, inputs, textareas, buttons, or labels
  if (e.target.closest('input, textarea, select, button, label, form, [contenteditable="true"]')) {
    return;
  }

  // Only target elements that are explicit navigation triggers (exclude document.body and view-panel)
  const viewTarget = e.target.closest('[data-view]:not(body):not(.view-panel)');
  if (viewTarget) {
    const viewName = viewTarget.getAttribute('data-view');
    if (viewName && viewName !== document.body.getAttribute('data-view')) {
      e.preventDefault();
      switchView(viewName);
    }
  }
});

// 2. DYNAMIC QR CODES
function initQrCodes() {
  // Always use the public GitHub website for QR code scans so mobile phones can connect
  const playBaseUrl = 'https://todd4529.github.io/BarRoomTrivia';
  const playUrl = `${playBaseUrl}/?view=player&room=${currentRoomCode}`;

  const canvasStage = document.getElementById('qr-canvas');
  if (canvasStage) {
    QRCode.toCanvas(canvasStage, playUrl, { width: 160, margin: 1 }, (err) => {
      if (err) console.error('Stage QR Code error:', err);
    });
  }

  const canvasPromo = document.getElementById('promo-qr-canvas');
  if (canvasPromo) {
    QRCode.toCanvas(canvasPromo, playUrl, { width: 130, margin: 1 }, (err) => {
      if (err) console.error('Promo QR Code error:', err);
    });
  }

  const roomLabels = document.querySelectorAll('.qr-room-code');
  roomLabels.forEach(el => {
    el.textContent = currentRoomCode;
  });
}

// 3. BROADCAST CHANNEL & MQTT WEBSOCKET REAL-TIME ENGINE
function getMqttTopic() {
  return `barrooms_trivia/room_${currentRoomCode.toUpperCase()}`;
}

function initRealtimeSupabaseChannels() {
  try {
    const norm = currentRoomCode.toUpperCase();
    if (liveRoomChannel) {
      try { supabase.removeChannel(liveRoomChannel); } catch (_) {}
    }
    if (liveDefaultChannel) {
      try { supabase.removeChannel(liveDefaultChannel); } catch (_) {}
    }
    if (liveGlobalChannel) {
      try { supabase.removeChannel(liveGlobalChannel); } catch (_) {}
    }

    function attachListener(ch) {
      ch.on('broadcast', { event: '*' }, ({ event, payload }) => {
        console.log(`[Supabase Realtime ${ch.topic}] Event:`, event, payload);
        handleRealtimeIncomingEvent(event, payload);
      });
      ch.subscribe((status, err) => {
        console.log(`[Supabase Realtime ${ch.topic}] status:`, status, err || '');
      });
    }

    liveRoomChannel = supabase.channel(`room_${norm}`);
    attachListener(liveRoomChannel);

    if (norm !== 'TRIV') {
      liveDefaultChannel = supabase.channel('room_TRIV');
      attachListener(liveDefaultChannel);
    }

    liveGlobalChannel = supabase.channel('room_GLOBAL');
    attachListener(liveGlobalChannel);

    // Active postgres_changes subscription for real-time player joins/scores
    try {
      supabase.channel('db_players_sync')
        .on('postgres_changes', { event: '*', schema: 'public', table: 'players' }, () => {
          loadInitialPlayers();
        })
        .subscribe();
    } catch (_) {}
  } catch (e) {
    console.warn('Error setting up Supabase Realtime channels:', e);
  }
}

let pendingMqttMessages = [];

function broadcastRealtimeEvent(event, payload = {}) {
  const fullPayload = {
    ...payload,
    event,
    type: event.toUpperCase(),
    room_code: currentRoomCode.toUpperCase(),
    timestamp: Date.now(),
  };

  // 1. Local BroadcastChannel
  try {
    channel.postMessage({ type: event.toUpperCase(), payload: fullPayload });
  } catch (_) {}

  // 2. Internet-Wide Realtime MQTT WebSockets
  if (mqttClient && mqttClient.connected) {
    try {
      const topic = getMqttTopic();
      const jsonStr = JSON.stringify(fullPayload);
      mqttClient.publish(topic, jsonStr);
      if (topic !== 'barrooms_trivia/room_TRIV') {
        mqttClient.publish('barrooms_trivia/room_TRIV', jsonStr);
      }
      const strippedTopic = `barrooms_trivia/room_${currentRoomCode.toUpperCase().replace(/-/g, '')}`;
      if (strippedTopic !== topic && strippedTopic !== 'barrooms_trivia/room_TRIV') {
        mqttClient.publish(strippedTopic, jsonStr);
      }
      mqttClient.publish('tv_pairing', jsonStr);
    } catch (e) {
      console.warn('[Realtime MQTT] Failed to publish:', e);
    }
  } else {
    pendingMqttMessages.push(fullPayload);
    if (pendingMqttMessages.length > 50) pendingMqttMessages.shift();
  }

  // 3. Internet-Wide Supabase Realtime Gateway
  try {
    if (!liveRoomChannel) {
      initRealtimeSupabaseChannels();
    }
    const sendObj = {
      type: 'broadcast',
      event: event,
      payload: fullPayload
    };
    liveRoomChannel?.send(sendObj);
    liveDefaultChannel?.send(sendObj);
    liveGlobalChannel?.send(sendObj);
  } catch (err) {
    console.warn('[Supabase Realtime Broadcast] Error:', err);
  }
}

// Deadline fields expressed in the SENDER's clock (TV / host device)
const SENDER_EPOCH_KEYS = [
  'timer_ends_at_epoch_ms',
  'timerEndsAtMs',
  'timer_ends_at',
  'timerEndsAtEpochMs',
  'starts_at_epoch_ms',
  'starts_at',
  'next_question_starts_at_epoch_ms',
  'nextQuestionStartsAtEpochMs',
  'next_round_starts_at_epoch_ms',
  'nextRoundStartsAtEpochMs',
];

/**
 * Re-bases absolute deadlines from the sender's clock onto this device's clock.
 * Phones and Android TV boxes often disagree by many seconds; without this, a
 * player whose clock runs ahead sees a deadline that is already past and the
 * question times out after ~1 second. Offsets under 1.5s are normal latency.
 */
function normalizeIncomingClockSkew(payload) {
  if (!payload || typeof payload !== 'object') return payload;
  const rawSent = payload.timestamp || payload.sent_at_epoch_ms || payload.updated_at;
  let sent = Number(rawSent);
  if (isNaN(sent) && typeof rawSent === 'string') {
    const parsed = Date.parse(rawSent);
    if (!isNaN(parsed) && parsed > 0) sent = parsed;
  }
  if (!sent || isNaN(sent) || sent <= 0) return payload;
  const skew = Date.now() - sent;
  if (Math.abs(skew) < 1500) return payload;
  const out = { ...payload };
  SENDER_EPOCH_KEYS.forEach(key => {
    let v = Number(out[key]);
    if (isNaN(v) && typeof out[key] === 'string') {
      const parsed = Date.parse(out[key]);
      if (!isNaN(parsed) && parsed > 0) v = parsed;
    }
    if (v > 0) out[key] = v + skew;
  });
  out.timestamp = sent + skew;
  return out;
}

function updatePlayerHeaderCard(round = currentRound, qNum = null, statusText = '') {
  const playerDispRoom = document.getElementById('player-disp-room');
  if (!playerDispRoom) return;
  const r = round || currentRound || 1;
  const room = currentRoomCode || 'TRIV';
  if (qNum) {
    playerDispRoom.textContent = `ROOM: ${room} • ROUND ${r} (Q${qNum}/10)`;
  } else if (statusText) {
    playerDispRoom.textContent = `ROOM: ${room} • ROUND ${r} (${statusText})`;
  } else {
    playerDispRoom.textContent = `ROOM: ${room} • ROUND ${r}`;
  }
}

function handleIncomingPreGameCountdown(rawPayload) {
  const payload = rawPayload?.payload || rawPayload || {};
  console.log('[Realtime] Processing pre_game_countdown:', payload);
  const countdownSecs = payload.countdown_seconds || 10;
  currentGameState = 'COUNTDOWN';
  currentQuestionData = null;
  playerChoiceSubmitted = null;
  isCurrentQuestionScored = false;

  const rNum = Number(payload.round_number || payload.roundNumber);
  if (rNum && rNum > 0) {
    if (rNum === 1) {
      currentRound = 1;
      currentQuestionIndex = 0;
    } else {
      currentRound = Math.max(currentRound, rNum);
    }
  }

  hideResultModal();
  hideWinnerModals();
  hideInterQuestionCountdown();
  clearInterval(preGameCountdownInterval);

  const rawStarts = payload.starts_at_epoch_ms || payload.startsAtMs;
  let startsAt = 0;
  if (typeof rawStarts === 'string') {
    const p = Date.parse(rawStarts);
    startsAt = !isNaN(p) ? p : Number(rawStarts);
  } else if (rawStarts) {
    startsAt = Number(rawStarts);
  }
  const now = Date.now();
  if (!startsAt || startsAt <= now) {
    startsAt = now + (countdownSecs * 1000);
  }

  const updatePreGameUI = () => {
    const rem = Math.max(0, Math.ceil((startsAt - Date.now()) / 1000));
    updatePlayerHeaderCard(currentRound, null, rem > 0 ? `Starting in ${rem}s` : 'Starting...');
    const playerTimerVal = document.getElementById('player-timer-val');
    if (playerTimerVal) {
      playerTimerVal.textContent = rem;
    }
    const playerStatusBadge = document.getElementById('player-status-badge');
    if (playerStatusBadge) {
      playerStatusBadge.className = 'status-badge status-active';
      playerStatusBadge.innerHTML = rem > 0
        ? `<span id="status-icon">🚀</span> ROUND ${currentRound} IN ${rem}s`
        : `<span id="status-icon">🎮</span> LAUNCHING ROUND ${currentRound}...`;
    }
    const playerQuestionText = document.getElementById('player-question-text');
    if (playerQuestionText) {
      playerQuestionText.textContent = rem > 0
        ? `🎮 ROUND ${currentRound} STARTING IN ${rem} SECONDS! Get ready...`
        : `🎮 ROUND ${currentRound} IS LAUNCHING NOW!`;
    }
    if (rem <= 0) {
      clearInterval(preGameCountdownInterval);
    }
  };

  updatePreGameUI();
  preGameCountdownInterval = setInterval(updatePreGameUI, 500);

  const answerBtns = document.querySelectorAll('.btn-answer');
  answerBtns.forEach(btn => {
    btn.disabled = true;
    btn.classList.remove('selected', 'unselected', 'review-correct', 'review-wrong');
  });

  // Update Host Mobile Stage Card for Countdown
  const hostStageBadge = document.getElementById('host-stage-badge');
  const hostStageQCounter = document.getElementById('host-stage-q-counter');
  const hostLiveGenrePill = document.getElementById('host-live-genre-pill');
  const hostLiveQText = document.getElementById('host-live-q-text');
  const hostTimerSecs = document.getElementById('host-live-timer-secs');
  const hostTimerFill = document.getElementById('host-timer-progress-fill');
  const btnSkip = document.getElementById('btn-skip-question');

  if (hostStageBadge) {
    hostStageBadge.className = 'stage-status-indicator stage-pregame';
    hostStageBadge.textContent = `🟡 STARTING ROUND ${currentRound}`;
  }
  if (hostStageQCounter) {
    hostStageQCounter.textContent = `Round Launch Countdown (${countdownSecs}s)`;
  }
  const preGenre = payload.genre || payload.current_genre || payload.category || 'Auto Select';
  if (hostLiveGenrePill) {
    hostLiveGenrePill.textContent = `${genreIconMap[preGenre] || '⚡'} ${preGenre.toUpperCase()}`;
  }
  if (hostLiveQText) {
    hostLiveQText.textContent = `Get ready! Round ${currentRound} is launching on TV and player devices...`;
  }
  if (hostTimerSecs) hostTimerSecs.textContent = `${countdownSecs}s`;
  if (hostTimerFill) hostTimerFill.style.width = '100%';
  isAutomatedEngineRunning = true;
  updateHostEngineUI('IN PROGRESS');

  const hostAnswerGrid = document.getElementById('host-live-answer-grid');
  if (hostAnswerGrid) hostAnswerGrid.classList.add('hidden');

  ['A', 'B', 'C', 'D'].forEach(letter => {
    const card = document.getElementById(`host-ans-${letter}`);
    const txt = document.getElementById(`host-ans-text-${letter}`);
    if (txt) txt.textContent = `Option ${letter}`;
    if (card) card.classList.remove('correct-key');
  });
}

function handleIncomingQuestionStart(rawPayload) {
  if (!rawPayload) return;
  const payload = rawPayload.payload || rawPayload;
  console.log('[Realtime] Processing question_start:', payload);

  const incomingRound = Number(payload.round_number || payload.roundNumber || (payload.cumulative_question_index ? Math.floor((payload.cumulative_question_index - 1) / 10) + 1 : 1));
  // Stale packet guard: ONLY ignore if incoming question is strictly from a past round
  if (incomingRound > 0 && currentRound > 0 && incomingRound < currentRound) {
    console.log('[Realtime] Ignoring stale question_start from previous round:', incomingRound, currentRound);
    return;
  }

  // A question_start event indicates active gameplay; dismiss all intermission and countdown overlays
  currentGameState = 'QUESTION_ACTIVE';
  clearInterval(winnerCountdownInterval);
  winnerCountdownInterval = null;
  hideWinnerModals();
  hideResultModal();
  hideInterQuestionCountdown();

  const qObj = payload.questionData || payload.question_data || payload;
  const opts = qObj.options || payload.options || {};
  const optA = payload.option_a || payload.optionA || qObj.option_a || qObj.optionA || opts.A || opts.a || (Array.isArray(opts) ? opts[0] : 'Option A');
  const optB = payload.option_b || payload.optionB || qObj.option_b || qObj.optionB || opts.B || opts.b || (Array.isArray(opts) ? opts[1] : 'Option B');
  const optC = payload.option_c || payload.optionC || qObj.option_c || qObj.option_c || opts.C || opts.c || (Array.isArray(opts) ? opts[2] : 'Option C');
  const optD = payload.option_d || payload.optionD || qObj.option_d || qObj.option_d || opts.D || opts.d || (Array.isArray(opts) ? opts[3] : 'Option D');
  const correct = (qObj.correct || qObj.correct_option || payload.correct_option || payload.correct || 'A').toUpperCase().trim();

  const questionData = {
    id: qObj.id || payload.question_id || payload.id || String(Date.now()),
    category: qObj.category || qObj.genre || payload.category || payload.genre || 'General Knowledge',
    difficulty: payload.difficulty || qObj.difficulty || selectedDifficulty || 'Standard',
    text: decodeHtmlEntities(qObj.text || qObj.question_text || payload.question_text || payload.text || payload.question || ''),
    options: {
      A: decodeHtmlEntities(optA),
      B: decodeHtmlEntities(optB),
      C: decodeHtmlEntities(optC),
      D: decodeHtmlEntities(optD),
    },
    correct: correct,
  };

  const defaultDur = selectedQuestionDuration || 20;
  const rawDur = Number(payload.time_limit_seconds || payload.total_duration || payload.totalTimerDuration || payload.duration_seconds || payload.durationSeconds);
  const durationSeconds = (!isNaN(rawDur) && rawDur >= 5) ? rawDur : defaultDur;
  const rFromPayload = Number(payload.round_number || payload.roundNumber);
  const roundNum = (rFromPayload && rFromPayload > 0)
    ? rFromPayload
    : (payload.cumulative_question_index ? Math.floor((payload.cumulative_question_index - 1) / 10) + 1 : (currentRound || 1));
  const prevRound = currentRound;
  currentRound = roundNum;

  let incomingQIndex = null;
  if (payload.cumulative_question_index !== undefined) {
    incomingQIndex = Number(payload.cumulative_question_index) - 1;
  } else if (payload.questionIndex !== undefined) {
    incomingQIndex = Number(payload.questionIndex);
  } else if (payload.question_index !== undefined) {
    const rawQ = Number(payload.question_index);
    incomingQIndex = rawQ > 10 ? rawQ - 1 : ((roundNum - 1) * 10) + (rawQ - 1);
  }

  const prevQIndex = currentQuestionIndex;
  const isDifferentIndex = (incomingQIndex !== null && prevQIndex !== null && incomingQIndex !== prevQIndex) || (prevRound !== roundNum);
  if (incomingQIndex !== null) {
    currentQuestionIndex = incomingQIndex;
  }
  const qNumInRound = Number(payload.question_number_in_round || payload.questionNumberInRound) || (((currentQuestionIndex % 10) + 1));

  // Check if player UI is currently showing waiting or blank screen
  const playerQElem = document.getElementById('player-question-text');
  const isUiWaiting = !playerQElem ||
    playerQElem.textContent.includes('Waiting for next question') ||
    playerQElem.textContent.includes('Get ready') ||
    playerQElem.textContent.includes('STARTING IN') ||
    playerQElem.textContent.includes('NEXT ROUND') ||
    playerQElem.textContent.trim() === '';

  const isSameQuestion = !isDifferentIndex && currentQuestionData && (
    (currentQuestionData.id && questionData.id && currentQuestionData.id === questionData.id) ||
    (currentQuestionData.text && questionData.text && currentQuestionData.text.trim() !== '' && currentQuestionData.text === questionData.text)
  );

  const rawTargetEpoch = payload.timer_ends_at_epoch_ms || payload.timerEndsAtMs || payload.timer_ends_at || payload.timerEndsAtEpochMs;
  const now = Date.now();
  let parsedTargetEpoch = 0;
  if (rawTargetEpoch) {
    const num = Number(rawTargetEpoch);
    if (!isNaN(num) && num > 0) {
      parsedTargetEpoch = num;
    } else {
      const parsed = Date.parse(rawTargetEpoch);
      if (!isNaN(parsed) && parsed > 0) parsedTargetEpoch = parsed;
    }
  }

  if (parsedTargetEpoch && parsedTargetEpoch > now) {
    timerEndsAtGlobalMs = parsedTargetEpoch;
  } else {
    timerEndsAtGlobalMs = now + (durationSeconds * 1000);
  }
  let remainingSecs = Math.max(0, Math.ceil((timerEndsAtGlobalMs - now) / 1000));
  if (remainingSecs <= 4 && durationSeconds > 4) {
    remainingSecs = durationSeconds;
    timerEndsAtGlobalMs = now + (durationSeconds * 1000);
  }

  if (isUiWaiting) {
    // Current UI is stuck on waiting or blank - clear submitted choice so question displays immediately
    playerChoiceSubmitted = null;
  }
  if (isSameQuestion && !isUiWaiting && playerChoiceSubmitted !== null) { // if (isSameQuestion && playerChoiceSubmitted !== null)
    // Current question is already active and answer submitted.
    // Preserve their answer selection and do not wipe question scored state
    currentQuestionData = questionData;
    if (remainingSecs > 0 && currentGameState !== 'QUESTION_REVIEW') {
      startCountdown(remainingSecs);
    }
    return;
  }
  if (isSameQuestion && !isUiWaiting && (isCurrentQuestionScored || currentGameState === 'QUESTION_REVIEW')) {
    currentQuestionData = questionData;
    return;
  }

  currentQuestionData = questionData;
  currentGameState = 'QUESTION_ACTIVE';
  playerChoiceSubmitted = null;
  isCurrentQuestionScored = false;
  lastScoredQuestionKey = null;
  currentQuestionAnswers = {};

  isAutomatedEngineRunning = true;
  updateHostEngineUI('IN PROGRESS');

  onQuestionStart({
    questionData,
    roundNumber: roundNum,
    questionNumberInRound: qNumInRound,
    durationSeconds: remainingSecs,
    totalTimerDuration: durationSeconds,
    difficulty: questionData.difficulty,
  });
}

function handleIncomingManualTimerStarted(rawPayload) {
  const payload = rawPayload?.payload || rawPayload || {};
  console.log('[Realtime] Processing manual_timer_started:', payload);
  const now = Date.now();
  const dur = Math.max(5, Number(payload.duration_seconds || payload.time_limit_seconds || selectedQuestionDuration || 20));
  let endsAt = Number(payload.timer_ends_at_epoch_ms || payload.timerEndsAtMs || 0);
  if (!endsAt || endsAt <= now) {
    endsAt = now + (dur * 1000);
  }
  timerEndsAtGlobalMs = endsAt;
  totalTimerDuration = dur;
  currentGameState = 'QUESTION_ACTIVE';
  const rem = Math.max(0, Math.ceil((timerEndsAtGlobalMs - now) / 1000));
  startCountdown(rem);
}

function handleIncomingTimerExpired(rawPayload) {
  const payload = rawPayload?.payload || rawPayload || {};
  console.log('[Realtime] Processing timer_expired:', payload);

  const nextEpoch = payload.next_question_starts_at_epoch_ms || 
                    payload.nextQuestionStartsAtEpochMs || 
                    (Date.now() + 15000);
  onTimerExpired({
    correctOption: payload.correct_option || payload.correctOption || payload.correct,
    correctText: payload.correctText,
    next_question_starts_at_epoch_ms: nextEpoch,
    nextQuestionStartsAtEpochMs: nextEpoch,
    game_play_mode: payload.game_play_mode || 'Auto',
  });
}

function handleRealtimeIncomingEvent(event, data) {
  const normEvent = (event || '').toLowerCase();
  const payload = normalizeIncomingClockSkew(data.payload || data);

  if (normEvent === 'pre_game_countdown') {
    handleIncomingPreGameCountdown(payload);
  } else if (normEvent === 'question_start') {
    handleIncomingQuestionStart(payload);
  } else if (normEvent === 'manual_timer_started') {
    handleIncomingManualTimerStarted(payload);
  } else if (normEvent === 'timer_expired') {
    handleIncomingTimerExpired(payload);
  } else if (normEvent === 'round_completed' || normEvent === 'round_winner') {
    const rawCompleted = payload?.completed_round || payload?.round_number || payload?.roundNumber;
    const rawNext = payload?.next_round || payload?.nextRound;
    const nextR = Number(rawNext || (rawCompleted ? Number(rawCompleted) + 1 : currentRound));
    currentRound = Math.max(currentRound, nextR);
    const list = payload?.top3Winners || payload?.top_3_winners || payload?.top3_winners || [];
    const delaySecs = Number(payload?.delaySeconds || payload?.delay_seconds || payload?.duration_seconds || selectedInterRoundDuration || 60);
    const startsAtEpoch = payload?.next_round_starts_at_epoch_ms || payload?.starts_at_epoch_ms;
    onRoundWinner({
      top3Winners: list,
      delaySeconds: delaySecs,
      starts_at_epoch_ms: startsAtEpoch,
      next_round_starts_at_epoch_ms: startsAtEpoch,
      roundNumber: currentRound
    });
  } else if (normEvent === 'game_paused') {
    onGamePaused(payload);
  } else if (normEvent === 'game_resuming') {
    onGameResuming(payload);
  } else if (normEvent === 'game_reset') {
    onGameReset();
  } else if (normEvent === 'request_state_sync') {
    if (isAutomatedEngineRunning) {
      if (hostEngineState === 'PRE_GAME') {
        const rem = Math.max(1, Math.ceil((hostTargetEpochMs - Date.now()) / 1000));
        broadcastRealtimeEvent('pre_game_countdown', {
          countdown_seconds: rem,
          starts_at_epoch_ms: hostTargetEpochMs,
          round_number: currentRound,
          roundNumber: currentRound,
          room_code: currentRoomCode
        });
      } else if (currentGameState === 'QUESTION_ACTIVE' && currentQuestionData) {
        const remainingMs = timerEndsAtGlobalMs - Date.now();
        const defaultDur = selectedQuestionDuration || 20;
        const rem = (remainingMs > 2000) ? Math.ceil(remainingMs / 1000) : defaultDur;
        const targetEpoch = (remainingMs > 2000) ? timerEndsAtGlobalMs : (Date.now() + defaultDur * 1000);
        broadcastRealtimeEvent('question_start', {
          question_index: (currentQuestionIndex % 10) + 1,
          cumulative_question_index: currentQuestionIndex + 1,
          question_number_in_round: (currentQuestionIndex % 10) + 1,
          round_number: currentRound,
          roundNumber: currentRound,
          total_questions: 10,
          total_questions_in_round: 10,
          id: currentQuestionData.id,
          question_id: currentQuestionData.id,
          duration_seconds: defaultDur,
          remaining_seconds: rem,
          time_limit_seconds: defaultDur,
          total_duration: defaultDur,
          totalTimerDuration: defaultDur,
          timer_ends_at_epoch_ms: targetEpoch,
          timerEndsAtMs: targetEpoch,
          category: currentQuestionData.category,
          difficulty: selectedDifficulty,
          question_text: currentQuestionData.text,
          option_a: currentQuestionData.options.A,
          option_b: currentQuestionData.options.B,
          option_c: currentQuestionData.options.C,
          option_d: currentQuestionData.options.D,
          options: currentQuestionData.options,
          questionData: currentQuestionData,
          correct_option: currentQuestionData.correct,
        });
      } else if (hostEngineState === 'QUESTION_REVIEW' && currentQuestionData) {
        broadcastRealtimeEvent('timer_expired', {
          correct_option: currentQuestionData.correct,
          correctText: `${currentQuestionData.correct}) ${currentQuestionData.options[currentQuestionData.correct]}`,
          next_question_starts_at_epoch_ms: hostTargetEpochMs,
        });
      } else if (hostEngineState === 'ROUND_SUMMARY') {
        const rem = Math.max(1, Math.ceil((hostTargetEpochMs - Date.now()) / 1000));
        broadcastRealtimeEvent('round_completed', {
          round_number: currentRound,
          roundNumber: currentRound,
          completed_round: currentRound,
          next_round: currentRound + 1,
          nextRound: currentRound + 1,
          top3_winners: playersLeaderboard.slice(0, 3),
          top_3_winners: playersLeaderboard.slice(0, 3),
          top3Winners: playersLeaderboard.slice(0, 3),
          delay_seconds: rem,
          delaySeconds: rem,
          duration_seconds: rem,
          starts_at_epoch_ms: hostTargetEpochMs,
          next_round_starts_at_epoch_ms: hostTargetEpochMs,
          room_code: currentRoomCode
        });
      }

      broadcastRealtimeEvent('leaderboard_updated', {
        players: playersLeaderboard,
        leaderboard: playersLeaderboard,
        room_code: currentRoomCode
      });
    }

    // Active player announces presence on state sync so fresh TV sessions see them
    if (currentPlayer && currentPlayer.nickname && !isFictitiousPlayer(currentPlayer.nickname)) {
      broadcastRealtimeEvent('player_joined', {
        nickname: currentPlayer.nickname,
        score: Number(currentPlayer.score ?? 0),
        room_code: currentRoomCode,
      });
    }
  } else if (normEvent === 'player_joined') {
    onPlayerJoined(payload);
  } else if (normEvent === 'answer_submitted') {
    onAnswerSubmitted(payload);
  } else if (normEvent === 'player_score_updated') {
    onPlayerScoreUpdated(payload);
  } else if (normEvent === 'leaderboard_updated') {
    mergeIncomingLeaderboard(payload?.players || payload?.leaderboard);
  } else if (normEvent === 'ad_mode_toggled') {
    onAdModeToggled(payload);
  } else if (normEvent === 'ad_slides_updated') {
    onAdSlidesUpdated(payload);
  } else if (normEvent === 'device_authorized') {
    if (payload && (payload.isAdModeActive !== undefined || payload.is_ad_mode_active !== undefined)) {
      onAdModeToggled({
        isAdModeActive: payload.isAdModeActive ?? payload.is_ad_mode_active
      });
    }
    syncTvSignageDisplay();
  } else if (normEvent === 'sound_toggled' || normEvent === 'sound_effects_toggled') {
    if (payload && (payload.isSoundEffectsEnabled !== undefined || payload.is_sound_effects_enabled !== undefined || payload.is_sound_enabled !== undefined)) {
      const val = payload.isSoundEffectsEnabled !== undefined
        ? payload.isSoundEffectsEnabled
        : (payload.is_sound_effects_enabled !== undefined ? payload.is_sound_effects_enabled : payload.is_sound_enabled);
      setSoundEffectsEnabled(Boolean(val), false);
    }
  }
}

function initRealtimeEngine() {
  // Always initialize Supabase Realtime Channels for Internet-wide broadcasting
  initRealtimeSupabaseChannels();

  const topic = getMqttTopic();
  const norm = currentRoomCode.toUpperCase();
  const stripped = norm.replace(/-/g, '');
  const topicsToSub = [topic, 'barrooms_trivia/room_TRIV', 'tv_pairing'];
  if (stripped !== norm) {
    topicsToSub.push(`barrooms_trivia/room_${stripped}`);
  }
  if (!norm.includes('-') && norm.startsWith('TRIV') && norm.length > 4) {
    topicsToSub.push(`barrooms_trivia/room_TRIV-${norm.slice(4)}`);
  }

  if (mqttClient && mqttClient.connected) {
    console.log(`[Realtime Engine] Already connected, subscribing to ${topicsToSub.join(', ')}...`);
    mqttClient.subscribe(topicsToSub, { qos: 0 });
    return;
  }

  if (mqttClient) {
    try { mqttClient.end(true); } catch (_) {}
  }

  console.log(`[Realtime Engine] Connecting to MQTT broker for ${topic}...`);

  try {
    mqttClient = mqtt.connect('wss://broker.emqx.io:8084/mqtt', {
      clientId: `barrooms_${Math.random().toString(16).substring(2, 10)}`,
      keepalive: 30,
      reconnectPeriod: 2000,
    });

    mqttClient.on('connect', () => {
      console.log(`[Realtime Engine] Connected! Subscribing to room topics...`);
      mqttClient.subscribe(topicsToSub, { qos: 0 }, (err) => {
        if (!err) {
          console.log(`[Realtime Engine] Subscribed to ${topicsToSub.join(', ')}!`);
          broadcastRealtimeEvent('request_state_sync', { room_code: currentRoomCode });

          // Flush any queued messages
          if (pendingMqttMessages.length > 0) {
            const queued = [...pendingMqttMessages];
            pendingMqttMessages = [];
            queued.forEach(p => {
              try {
                // Re-stamp with the actual send time; deadlines stay absolute so
                // receivers correctly treat stale queued events as expired.
                const jsonStr = JSON.stringify({ ...p, timestamp: Date.now() });
                mqttClient.publish(topic, jsonStr);
                if (topic !== 'barrooms_trivia/room_TRIV') mqttClient.publish('barrooms_trivia/room_TRIV', jsonStr);
                mqttClient.publish('tv_pairing', jsonStr);
              } catch (_) {}
            });
          }

          // If active real player joined on this device, guarantee TV receives player_joined
          if (currentPlayer && currentPlayer.nickname && !isFictitiousPlayer(currentPlayer.nickname)) {
            broadcastRealtimeEvent('player_joined', {
              nickname: currentPlayer.nickname,
              score: Number(currentPlayer.score ?? 0),
              room_code: currentRoomCode,
            });
          }
        }
      });
    });

    mqttClient.on('message', (receivedTopic, message) => {
      const normRoom = currentRoomCode.toUpperCase();
      const strippedRoom = normRoom.replace(/-/g, '');
      const isAllowed = (
        receivedTopic === topic ||
        receivedTopic === 'barrooms_trivia/room_TRIV' ||
        receivedTopic === 'tv_pairing' ||
        receivedTopic === `barrooms_trivia/room_${normRoom}` ||
        receivedTopic === `barrooms_trivia/room_${strippedRoom}` ||
        (!normRoom.includes('-') && normRoom.startsWith('TRIV') && normRoom.length > 4 && receivedTopic === `barrooms_trivia/room_TRIV-${normRoom.slice(4)}`)
      );
      if (!isAllowed) return;
      try {
        const data = JSON.parse(message.toString());
        const event = data.event || data.type || '';
        handleRealtimeIncomingEvent(event, data);
      } catch (err) {
        console.warn('[Realtime Engine] Failed to parse message:', err);
      }
    });

    mqttClient.on('error', (err) => {
      console.warn('[Realtime Engine] Error:', err);
    });
  } catch (err) {
    console.error('[Realtime Engine] Init failed:', err);
  }
}

function initBroadcastChannelListeners() {
  channel.onmessage = (event) => {
    const { type, payload } = event.data;

    if (type === 'REQUEST_STATE_SYNC') {
      channel.postMessage({
        type: 'STATE_SYNC_RESPONSE',
        payload: {
          currentGameState,
          currentQuestionData,
          currentQuestionIndex,
          currentRound,
          roundNumber: currentRound,
          selectedDifficulty,
          selectedQuestionDuration,
          currentVenueName,
          customBarLogoUrl,
          playersLeaderboard,
          timerEndsAtGlobalMs,
          totalTimerDuration,
          isAdModeActive,
          adSlideDurationSeconds,
          isSoundEffectsEnabled
        }
      });
    } else if (type === 'STATE_SYNC_RESPONSE') {
      onStateSyncResponse(payload);
    } else if (type === 'QUESTION_START') {
      handleIncomingQuestionStart(payload);
    } else if (type === 'TIMER_EXPIRED') {
      onTimerExpired(payload);
    } else if (type === 'ROUND_SUMMARY') {
      onRoundSummary(payload);
    } else if (type === 'ROUND_WINNER') {
      onRoundWinner(payload);
    } else if (type === 'PLAYER_JOINED') {
      onPlayerJoined(payload);
    } else if (type === 'ANSWER_SUBMITTED') {
      onAnswerSubmitted(payload);
    } else if (type === 'PLAYER_SCORE_UPDATED') {
      onPlayerScoreUpdated(payload);
    } else if (type === 'LEADERBOARD_UPDATED') {
      mergeIncomingLeaderboard(payload?.players || payload?.leaderboard);
    } else if (type === 'GAME_PAUSED') {
      onGamePaused(payload);
    } else if (type === 'GAME_RESUMING') {
      onGameResuming(payload);
    } else if (type === 'GAME_RESET') {
      onGameReset(payload);
    } else if (type === 'LOGO_UPDATED') {
      onLogoUpdated(payload);
    } else if (type === 'VENUE_NAME_UPDATED') {
      onVenueNameUpdated(payload);
    } else if (type === 'AD_MODE_TOGGLED') {
      onAdModeToggled(payload);
    } else if (type === 'AD_SLIDES_UPDATED') {
      onAdSlidesUpdated(payload);
    } else if (type === 'SOUND_TOGGLED' || type === 'SOUND_EFFECTS_TOGGLED') {
      if (payload && (payload.isSoundEffectsEnabled !== undefined || payload.is_sound_effects_enabled !== undefined || payload.is_sound_enabled !== undefined)) {
        const val = payload.isSoundEffectsEnabled !== undefined
          ? payload.isSoundEffectsEnabled
          : (payload.is_sound_effects_enabled !== undefined ? payload.is_sound_effects_enabled : payload.is_sound_enabled);
        setSoundEffectsEnabled(Boolean(val), false);
      }
    }
  };
}

function onStateSyncResponse(payload) {
  if (!payload) return;

  if (payload.isSoundEffectsEnabled !== undefined || payload.is_sound_effects_enabled !== undefined || payload.is_sound_enabled !== undefined) {
    const val = payload.isSoundEffectsEnabled !== undefined
      ? payload.isSoundEffectsEnabled
      : (payload.is_sound_effects_enabled !== undefined ? payload.is_sound_effects_enabled : payload.is_sound_enabled);
    setSoundEffectsEnabled(Boolean(val), false);
  }

  if (payload.currentVenueName) {
    currentVenueName = payload.currentVenueName;
    safeStorage.setItem('bar_trivia_venue_name', currentVenueName);
    onVenueNameUpdated({ venueName: currentVenueName });
  }

  if (payload.customBarLogoUrl !== undefined) {
    customBarLogoUrl = payload.customBarLogoUrl;
    if (customBarLogoUrl) safeStorage.setItem('bar_trivia_logo_url', customBarLogoUrl);
    else safeStorage.removeItem('bar_trivia_logo_url');
    onLogoUpdated({ logoUrl: customBarLogoUrl });
  }

  if (payload.playersLeaderboard) {
    playersLeaderboard = payload.playersLeaderboard;
    renderLeaderboard();
  }

  if (payload.isAdModeActive !== undefined) {
    isAdModeActive = Boolean(payload.isAdModeActive);
    safeStorage.setItem('bar_trivia_ad_mode_active', String(isAdModeActive));
    const toggle = document.getElementById('host-toggle-ad-mode');
    if (toggle) toggle.checked = isAdModeActive;
  }

  if (payload.adSlideDurationSeconds !== undefined) {
    adSlideDurationSeconds = parseInt(payload.adSlideDurationSeconds, 10);
    safeStorage.setItem('bar_trivia_ad_duration', String(adSlideDurationSeconds));
    const durChips = document.querySelectorAll('.ad-dur-chip');
    durChips.forEach(chip => {
      chip.classList.toggle('active', parseInt(chip.dataset.dur, 10) === adSlideDurationSeconds);
    });
  }

  syncTvSignageDisplay();

  if (payload.currentGameState === 'QUESTION_ACTIVE' && payload.currentQuestionData) {
    currentGameState = payload.currentGameState;
    currentQuestionData = payload.currentQuestionData;
    currentQuestionIndex = payload.currentQuestionIndex || 0;
    const now = Date.now();
    const fallbackDur = Math.max(5, Number(payload.totalTimerDuration || selectedQuestionDuration || 20));
    let rawEnds = payload.timerEndsAtGlobalMs || 0;
    if (typeof rawEnds === 'string') {
      const p = Date.parse(rawEnds);
      rawEnds = !isNaN(p) ? p : Number(rawEnds);
    }
    const remainingMs = rawEnds > 0 ? (rawEnds - now) : 0;
    const remainingSecs = remainingMs > 2000 ? Math.ceil(remainingMs / 1000) : fallbackDur;
    if (remainingMs <= 2000) {
      timerEndsAtGlobalMs = now + (fallbackDur * 1000);
    } else {
      timerEndsAtGlobalMs = rawEnds;
    }

    const syncRound = Number(payload.round_number || payload.roundNumber || Math.floor((payload.currentQuestionIndex || 0) / 10) + 1);
    currentRound = Math.max(currentRound, syncRound);

    onQuestionStart({
      questionData: payload.currentQuestionData,
      roundNumber: currentRound,
      questionNumberInRound: (payload.currentQuestionIndex % 10) + 1,
      durationSeconds: remainingSecs,
      difficulty: payload.selectedDifficulty
    });
  }
}

// 4. HOST CONTROLS, QUESTION TIMER SELECTOR, DIFFICULTY & MULTI-GENRE QUEUE
function initHostControls() {
  const btnStartAuto = document.getElementById('btn-start-auto');
  const btnPauseAuto = document.getElementById('btn-pause-auto');
  const btnResetGame = document.getElementById('btn-reset-game');
  const btnClearQueue = document.getElementById('btn-clear-queue');
  const diffChips = document.querySelectorAll('.diff-chip');
  const timerChips = document.querySelectorAll('.timer-chip');
  const genreChips = document.querySelectorAll('.genre-chip');
  const hostLogoInput = document.getElementById('host-logo-input');
  const btnRemoveLogo = document.getElementById('btn-remove-logo');
  const hostVenueInput = document.getElementById('host-venue-name-input');

  // Initialize input value from stored state
  if (hostVenueInput) hostVenueInput.value = currentVenueName;

  // TAB SWITCHING (Live Stage, Playlist, Connected Players, Settings)
  const hostTabBtns = document.querySelectorAll('.host-tab-btn');
  const hostTabPanes = document.querySelectorAll('.host-tab-pane');
  const btnGotoPlaylist = document.getElementById('btn-host-goto-playlist');

  function switchHostTab(tabName) {
    if (!tabName) return;
    hostTabBtns.forEach(btn => {
      const isTarget = btn.getAttribute('data-tab') === tabName;
      btn.classList.toggle('active', isTarget);
      btn.setAttribute('aria-selected', isTarget ? 'true' : 'false');
    });

    hostTabPanes.forEach(pane => {
      const isTarget = pane.id === `host-pane-${tabName}`;
      pane.classList.toggle('active', isTarget);
    });

    if (tabName === 'players') {
      renderHostPlayersRoster();
      refreshHostPlayers();
    }
  }

  const statPillTimer = document.getElementById('stat-pill-timer');
  const statPillDiff = document.getElementById('stat-pill-diff');

  function navigateToSettingsControl(controlId) {
    switchHostTab('settings');
    setTimeout(() => {
      const el = document.getElementById(controlId);
      if (el) {
        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
        el.classList.remove('control-pulse-highlight');
        void el.offsetWidth;
        el.classList.add('control-pulse-highlight');
      }
    }, 120);
  }

  statPillTimer?.addEventListener('click', (e) => {
    e.preventDefault();
    navigateToSettingsControl('timer-chips-container');
  });

  statPillDiff?.addEventListener('click', (e) => {
    e.preventDefault();
    navigateToSettingsControl('difficulty-chips-container');
  });

  hostTabBtns.forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      const tab = btn.getAttribute('data-tab');
      switchHostTab(tab);
    });
  });

  btnGotoPlaylist?.addEventListener('click', (e) => {
    e.preventDefault();
    switchHostTab('playlist');
  });

  // GENRE SEARCH & CATEGORY FILTERING
  const genreSearchInput = document.getElementById('host-genre-search-input');
  const btnClearSearch = document.getElementById('btn-clear-genre-search');
  const catPills = document.querySelectorAll('.genre-cat-pill');
  let activeCategoryFilter = 'all';

  function filterGenreChips() {
    const query = (genreSearchInput?.value || '').toLowerCase().trim();
    if (btnClearSearch) {
      btnClearSearch.classList.toggle('hidden', !query);
    }

    genreChips.forEach(chip => {
      const gName = (chip.dataset.genre || chip.textContent || '').toLowerCase();
      const gCat = chip.dataset.cat || 'all';

      const matchesCat = (activeCategoryFilter === 'all') || (gCat === activeCategoryFilter) || (chip.dataset.genre === 'Auto Select' || chip.dataset.genre === 'Random');
      const matchesQuery = !query || gName.includes(query);

      chip.style.display = (matchesCat && matchesQuery) ? '' : 'none';
    });
  }

  genreSearchInput?.addEventListener('input', filterGenreChips);
  btnClearSearch?.addEventListener('click', () => {
    if (genreSearchInput) genreSearchInput.value = '';
    filterGenreChips();
  });

  catPills.forEach(pill => {
    pill.addEventListener('click', (e) => {
      e.preventDefault();
      catPills.forEach(p => p.classList.remove('active'));
      pill.classList.add('active');
      activeCategoryFilter = pill.dataset.cat || 'all';
      filterGenreChips();
    });
  });

  // Venue Name Input Handler
  hostVenueInput?.addEventListener('input', (e) => {
    currentVenueName = e.target.value.trim() || "OUR PUB";
    safeStorage.setItem('bar_trivia_venue_name', currentVenueName);
    onVenueNameUpdated({ venueName: currentVenueName });
    channel.postMessage({ type: 'VENUE_NAME_UPDATED', payload: { venueName: currentVenueName } });
  });

  // Host Logo Upload Handler
  hostLogoInput?.addEventListener('change', (e) => {
    const file = e.target.files?.[0];
    if (file) {
      const reader = new FileReader();
      reader.onload = (evt) => {
        customBarLogoUrl = evt.target.result;
        safeStorage.setItem('bar_trivia_logo_url', customBarLogoUrl);
        updateHostLogoPreview(customBarLogoUrl);
        channel.postMessage({ type: 'LOGO_UPDATED', payload: { logoUrl: customBarLogoUrl } });
        onLogoUpdated({ logoUrl: customBarLogoUrl });
      };
      reader.readAsDataURL(file);
    }
  });

  btnRemoveLogo?.addEventListener('click', () => {
    customBarLogoUrl = null;
    safeStorage.removeItem('bar_trivia_logo_url');
    updateHostLogoPreview(null);
    channel.postMessage({ type: 'LOGO_UPDATED', payload: { logoUrl: null } });
    onLogoUpdated({ logoUrl: null });
  });

  // GAME PLAY MODE (AUTO vs MANUAL)
  const modeChips = document.querySelectorAll('.mode-chip');
  function updateGameModeUI(mode) {
    hostGamePlayMode = mode;
    modeChips.forEach(chip => {
      const isSelected = chip.dataset.mode === mode;
      chip.classList.toggle('active', isSelected);
      if (isSelected) {
        chip.style.borderColor = 'var(--neon-cyan)';
        chip.style.color = '#fff';
      } else {
        chip.style.borderColor = 'rgba(255, 255, 255, 0.2)';
        chip.style.color = 'var(--text-muted)';
      }
    });
    updateHostManualDock();
    try {
      supabase.from('game_sessions').upsert({
        room_code: currentRoomCode,
        game_play_mode: mode,
        updated_at: new Date().toISOString()
      }, { onConflict: 'room_code' }).catch(() => {});
    } catch (_) {}
  }

  modeChips.forEach(chip => {
    chip.addEventListener('click', (e) => {
      e.preventDefault();
      updateGameModeUI(chip.dataset.mode || 'Auto');
    });
  });

  // DIFFICULTY LEVEL SELECTION (KIDS, BEGINNER, STANDARD, ADVANCED)
  diffChips.forEach(chip => {
    chip.addEventListener('click', (e) => {
      e.preventDefault();
      if (isAutomatedEngineRunning) return;

      diffChips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');

      selectedDifficulty = chip.dataset.diff || 'Standard';
      const statDifficulty = document.getElementById('stat-difficulty');
      if (statDifficulty) statDifficulty.textContent = selectedDifficulty;
    });
  });

  // QUESTION TIMER DURATION SELECTOR
  timerChips.forEach(chip => {
    const dur = parseInt(chip.getAttribute('data-timer'), 10);
    chip.classList.toggle('active', dur === selectedQuestionDuration);

    chip.addEventListener('click', (e) => {
      e.preventDefault();
      if (isAutomatedEngineRunning) return;

      timerChips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');

      const parsedSecs = parseInt(chip.getAttribute('data-timer'), 10);
      if (!isNaN(parsedSecs)) {
        selectedQuestionDuration = parsedSecs;
        totalTimerDuration = parsedSecs;
        safeStorage.setItem('bar_trivia_question_duration', String(parsedSecs));
      }

      const statActiveTimer = document.getElementById('stat-active-timer');
      if (statActiveTimer) {
        if (selectedQuestionDuration >= 60) {
          const mins = Math.floor(selectedQuestionDuration / 60);
          const secs = selectedQuestionDuration % 60;
          statActiveTimer.textContent = secs > 0 ? `${mins}m ${secs}s` : `${mins} Min`;
        } else {
          statActiveTimer.textContent = `${selectedQuestionDuration}s`;
        }
      }
    });
  });

  // IN-BETWEEN ROUND DURATION SELECTOR (30s, 1 Min, 2 Min, 3 Min, 4 Min, 5 Min, 10 Min)
  const interRoundChips = document.querySelectorAll('.inter-round-chip');
  interRoundChips.forEach(chip => {
    const dur = parseInt(chip.getAttribute('data-round-dur'), 10);
    chip.classList.toggle('active', dur === selectedInterRoundDuration);
    chip.addEventListener('click', (e) => {
      e.preventDefault();
      if (isAutomatedEngineRunning) return;

      interRoundChips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');

      if (!isNaN(dur)) {
        selectedInterRoundDuration = dur;
        safeStorage.setItem('bar_trivia_inter_round_duration', String(dur));
      }
    });
  });

  // MULTI-GENRE QUEUE SELECTION (UP TO 10 GENRES IN ORDER)
  genreChips.forEach(chip => {
    chip.addEventListener('click', (e) => {
      e.preventDefault();
      if (isAutomatedEngineRunning) return;

      const genre = chip.dataset.genre;
      const idx = selectedGenreQueue.indexOf(genre);

      if (idx > -1) {
        selectedGenreQueue.splice(idx, 1);
      } else {
        if (selectedGenreQueue.length < 10) {
          selectedGenreQueue.push(genre);
        }
      }

      updateGenreQueueUI();
    });
  });

  btnClearQueue?.addEventListener('click', () => {
    if (isAutomatedEngineRunning) return;
    selectedGenreQueue = [];
    updateGenreQueueUI();
  });

  function pauseGameEngine() {
    if (!isAutomatedEngineRunning && currentGameState !== 'IN PROGRESS' && currentGameState !== 'QUESTION_ACTIVE' && currentGameState !== 'QUESTION_REVIEW' && currentGameState !== 'ROUND_SUMMARY' && currentGameState !== 'PRE_GAME') return;

    pausedHostEngineState = hostEngineState || 'QUESTION_ACTIVE';
    pausedQuestionData = currentQuestionData;
    pausedQuestionIndex = currentQuestionIndex;
    pausedRound = currentRound;

    if (hostEngineState === 'QUESTION_ACTIVE' || currentGameState === 'QUESTION_ACTIVE') {
      pausedRemainingQuestionSeconds = timerEndsAtGlobalMs > Date.now()
        ? Math.max(1, Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000))
        : (remainingTimerSeconds > 0 ? remainingTimerSeconds : (selectedQuestionDuration || 20));
    } else if (hostTargetEpochMs > Date.now()) {
      pausedRemainingQuestionSeconds = Math.max(1, Math.ceil((hostTargetEpochMs - Date.now()) / 1000));
    } else {
      pausedRemainingQuestionSeconds = selectedQuestionDuration || 20;
    }

    timerEndsAtGlobalMs = 0;
    hostTargetEpochMs = 0;

    isAutomatedEngineRunning = false;
    stopHostHeartbeatLoop();
    clearTimeout(autoEngineTimeout);
    clearInterval(countdownInterval);
    clearInterval(modalCountdownInterval);
    clearInterval(tvNextQCountdownInterval);
    clearInterval(winnerCountdownInterval);
    clearInterval(playerInterQuestionInterval);
    clearMockPlayerTimeouts();
    currentGameState = 'PAUSED';
    updateHostEngineUI('PAUSED');
    onGamePaused({
      remaining_question_seconds: pausedRemainingQuestionSeconds,
      round_number: pausedRound,
      question_index: pausedQuestionIndex
    });

    channel.postMessage({
      type: 'GAME_PAUSED',
      payload: {
        roomCode: currentRoomCode,
        remaining_question_seconds: pausedRemainingQuestionSeconds,
        roundNumber: pausedRound,
        questionIndex: pausedQuestionIndex
      }
    });
    broadcastRealtimeEvent('game_paused', {
      room_code: currentRoomCode,
      remaining_question_seconds: pausedRemainingQuestionSeconds,
      round_number: pausedRound,
      roundNumber: pausedRound,
      question_index: pausedQuestionIndex,
      questionIndex: pausedQuestionIndex
    });
    syncTvSignageDisplay();

    try {
      supabase.from('game_sessions').upsert({
        room_code: currentRoomCode,
        status: 'paused',
        current_round: pausedRound,
        current_question_index: pausedQuestionIndex,
        remaining_question_seconds: pausedRemainingQuestionSeconds,
        updated_at: new Date().toISOString()
      }, { onConflict: 'room_code' }).catch(() => {});
    } catch (_) {}
  }

  function resumeGameEngine() {
    if (isAutomatedEngineRunning) return;
    isAutomatedEngineRunning = true;
    currentGameState = 'IN PROGRESS';
    updateHostEngineUI('IN PROGRESS');

    const resumeSecs = 10;
    const startsAtMs = Date.now() + (resumeSecs * 1000);
    const remainingSecs = pausedRemainingQuestionSeconds || selectedQuestionDuration || 20;

    currentRound = pausedRound || currentRound || 1;
    currentQuestionIndex = pausedQuestionIndex !== undefined ? pausedQuestionIndex : currentQuestionIndex;

    onGameResuming({
      starts_at_epoch_ms: startsAtMs,
      remaining_question_seconds: remainingSecs,
      round_number: currentRound,
      question_index: currentQuestionIndex
    });

    channel.postMessage({
      type: 'GAME_RESUMING',
      payload: {
        roomCode: currentRoomCode,
        starts_at_epoch_ms: startsAtMs,
        remaining_question_seconds: remainingSecs,
        roundNumber: currentRound,
        questionIndex: currentQuestionIndex
      }
    });
    broadcastRealtimeEvent('game_resuming', {
      room_code: currentRoomCode,
      starts_at_epoch_ms: startsAtMs,
      remaining_question_seconds: remainingSecs,
      round_number: currentRound,
      roundNumber: currentRound,
      question_index: currentQuestionIndex,
      questionIndex: currentQuestionIndex
    });
    syncTvSignageDisplay();

    try {
      supabase.from('game_sessions').upsert({
        room_code: currentRoomCode,
        status: 'resuming',
        starts_at: startsAtMs,
        current_round: currentRound,
        current_question_index: currentQuestionIndex,
        remaining_question_seconds: remainingSecs,
        updated_at: new Date().toISOString()
      }, { onConflict: 'room_code' }).catch(() => {});
    } catch (_) {}

    clearTimeout(autoEngineTimeout);
    autoEngineTimeout = setTimeout(() => {
      if (!isAutomatedEngineRunning) return;

      if (pausedHostEngineState === 'QUESTION_ACTIVE' || (!pausedHostEngineState && (pausedQuestionData || currentQuestionData))) {
        const question = pausedQuestionData || currentQuestionData;
        const questionInRound = (currentQuestionIndex % 10) + 1;
        const qDuration = Math.max(1, remainingSecs);

        timerEndsAtGlobalMs = Date.now() + (qDuration * 1000);
        hostTargetEpochMs = timerEndsAtGlobalMs;
        hostEngineState = 'QUESTION_ACTIVE';
        startHostHeartbeatLoop();

        const activeGenre = question?.category || activeRoundGenre || 'General Trivia';
        const payload = {
          questionIndex: currentQuestionIndex,
          roundNumber: currentRound,
          questionNumberInRound: questionInRound,
          questionData: question,
          difficulty: selectedDifficulty,
          durationSeconds: qDuration,
          timerEndsAtMs: timerEndsAtGlobalMs,
          question_index: questionInRound,
          cumulative_question_index: currentQuestionIndex + 1,
          question_number_in_round: questionInRound,
          total_questions: 10,
          total_questions_in_round: 10,
          round_number: currentRound,
          id: question.id,
          question_id: question.id,
          duration_seconds: qDuration,
          timer_ends_at_epoch_ms: timerEndsAtGlobalMs,
          category: activeGenre,
          genre: activeGenre,
          question_text: question.text,
          option_a: question.options?.A || '',
          option_b: question.options?.B || '',
          option_c: question.options?.C || '',
          option_d: question.options?.D || '',
          options: question.options,
          correct_option: question.correct,
          is_resumed: true,
        };

        currentGameState = 'QUESTION_ACTIVE';
        broadcastRealtimeEvent('question_start', payload);
        onQuestionStart(payload);

        try {
          supabase.from('game_sessions').upsert({
            room_code: currentRoomCode,
            status: 'question_active',
            current_question_index: currentQuestionIndex + 1,
            current_round: currentRound,
            round_number: currentRound,
            duration_seconds: qDuration,
            timer_ends_at: timerEndsAtGlobalMs ? new Date(timerEndsAtGlobalMs).toISOString() : null,
            genre: activeGenre,
            question_data: {
              id: question.id,
              question_id: question.id,
              category: activeGenre,
              genre: activeGenre,
              difficulty: selectedDifficulty,
              text: question.text,
              question_text: question.text,
              options: question.options,
              correct: question.correct,
              correct_option: question.correct,
              round_number: currentRound,
              roundNumber: currentRound,
              question_number_in_round: questionInRound,
            },
            updated_at: new Date().toISOString(),
          }, { onConflict: 'room_code' }).catch(() => {});
        } catch (_) {}

        clearTimeout(autoEngineTimeout);
        autoEngineTimeout = setTimeout(() => {
          checkHostEngineTick();
        }, qDuration * 1000);
      } else if (pausedHostEngineState === 'QUESTION_REVIEW') {
        hostEngineState = 'QUESTION_REVIEW';
        hostTargetEpochMs = Date.now() + (remainingSecs * 1000);
        startHostHeartbeatLoop();
        autoEngineTimeout = setTimeout(() => {
          checkHostEngineTick();
        }, remainingSecs * 1000);
      } else if (pausedHostEngineState === 'ROUND_SUMMARY') {
        hostEngineState = 'ROUND_SUMMARY';
        hostTargetEpochMs = Date.now() + (remainingSecs * 1000);
        startHostHeartbeatLoop();
        autoEngineTimeout = setTimeout(() => {
          checkHostEngineTick();
        }, remainingSecs * 1000);
      } else {
        hostEngineState = 'QUESTION_ACTIVE';
        hostTargetEpochMs = 0;
        runNextAutomatedStep();
      }
    }, resumeSecs * 1000);
  }

  btnStartAuto?.addEventListener('click', async () => {
    requestScreenWakeLock();
    if (isAutomatedEngineRunning || currentGameState === 'PAUSED') {
      // Start Game button is disabled and not functional when paused to prevent accidentally starting a new round
      return;
    }
    isAutomatedEngineRunning = true;
    currentRoundQuestions = [];
    currentQuestionIndex = 0;
    currentRound = 1;
    currentQuestionData = null;
    playerChoiceSubmitted = null;
    isCurrentQuestionScored = false;
    updateHostEngineUI('IN PROGRESS');

    // 1. Determine active genre and broadcast pre-game countdown (10s) immediately to TV and players
    let initialGenre = 'General Trivia';
    if (selectedGenreQueue.length > 0) {
      const qIndex = (currentRound - 1) % selectedGenreQueue.length;
      initialGenre = selectedGenreQueue[qIndex];
    } else if (shuffledAutoGenres && shuffledAutoGenres.length > 0) {
      initialGenre = shuffledAutoGenres[(currentRound - 1) % shuffledAutoGenres.length];
    }

    const countdownSecs = 10;
    const startsAtMs = Date.now() + (countdownSecs * 1000);
    hostTargetEpochMs = startsAtMs;
    hostEngineState = 'PRE_GAME';
    startHostHeartbeatLoop();

    broadcastRealtimeEvent('pre_game_countdown', {
      countdown_seconds: countdownSecs,
      starts_at_epoch_ms: startsAtMs,
      room_code: currentRoomCode,
      genre: initialGenre,
      current_genre: initialGenre,
      category: initialGenre,
      round_number: currentRound,
      roundNumber: currentRound,
    });

    handleIncomingPreGameCountdown({
      countdown_seconds: countdownSecs,
      starts_at_epoch_ms: startsAtMs,
      room_code: currentRoomCode,
      genre: initialGenre,
      current_genre: initialGenre,
      category: initialGenre,
      round_number: currentRound,
      roundNumber: currentRound,
    });

    broadcastRealtimeEvent('leaderboard_updated', {
      players: playersLeaderboard,
      leaderboard: playersLeaderboard,
      room_code: currentRoomCode
    });

    try {
      supabase.from('game_sessions').upsert({
        room_code: currentRoomCode,
        status: 'pre_game_countdown',
        starts_at: startsAtMs,
        current_question_index: 0,
        current_round: 1,
        round_number: 1,
        question_data: null,
        current_question_data: null,
        genre: initialGenre,
        updated_at: new Date().toISOString()
      }, { onConflict: 'room_code' }).catch(() => {});
    } catch (_) {}

    // 2. Fetch questions during the countdown
    await initOpenTdbToken();

    // 3. Start Question 1 automatically after countdown finishes
    clearTimeout(autoEngineTimeout);
    autoEngineTimeout = setTimeout(() => {
      checkHostEngineTick();
    }, countdownSecs * 1000);
  });

  btnPauseAuto?.addEventListener('click', () => {
    if (currentGameState === 'PAUSED') {
      resumeGameEngine();
    } else {
      pauseGameEngine();
    }
  });

  const btnRefreshPlayers = document.getElementById('btn-refresh-players');
  btnRefreshPlayers?.addEventListener('click', (e) => {
    e.preventDefault();
    refreshHostPlayers();
  });

  btnResetGame?.addEventListener('click', () => {
    isAutomatedEngineRunning = false;
    pausedHostEngineState = 'IDLE';
    pausedRemainingQuestionSeconds = 0;
    pausedQuestionData = null;
    pausedQuestionIndex = 0;
    pausedRound = 1;
    stopHostHeartbeatLoop();
    clearTimeout(autoEngineTimeout);
    clearInterval(countdownInterval);
    clearInterval(modalCountdownInterval);
    clearInterval(tvNextQCountdownInterval);
    clearInterval(winnerCountdownInterval);
    clearMockPlayerTimeouts();
    resetQuestionHistory();
    currentQuestionIndex = 0;
    currentRound = 1;
    currentGameState = 'LOBBY';
    updateHostEngineUI('NOT STARTED');

    channel.postMessage({ type: 'GAME_RESET', payload: { roomCode: currentRoomCode, reset_mode: 'clear_all' } });
    broadcastRealtimeEvent('game_reset', { room_code: currentRoomCode, reset_mode: 'clear_all' });

    try {
      supabase.from('game_sessions').upsert({
        room_code: currentRoomCode,
        status: 'lobby',
        current_round: 1,
        current_question_index: 0,
        question_data: null,
        current_question_data: null,
        updated_at: new Date().toISOString()
      }, { onConflict: 'room_code' }).catch(() => {});
    } catch (_) {}

    onGameReset({ roomCode: currentRoomCode });
    syncTvSignageDisplay();
  });

  // Initial UI Render & Active Session Sync
  updateGenreQueueUI();
  updateHostEngineUI('NOT STARTED');
  renderHostPlayersRoster();

  async function checkHostActiveGameSession() {
    try {
      const code = (currentRoomCode || 'TRIV').trim().toUpperCase();
      let { data } = await supabase.from('game_sessions')
        .select('*')
        .eq('room_code', code)
        .order('updated_at', { ascending: false })
        .limit(1);

      if ((!data || data.length === 0) && code !== 'TRIV') {
        const fallback = await supabase.from('game_sessions')
          .select('*')
          .eq('room_code', 'TRIV')
          .order('updated_at', { ascending: false })
          .limit(1);
        data = fallback.data;
      }

      const session = (data && data.length > 0) ? data[0] : null;
      if (session) {
        if (session.is_sound_effects_enabled !== undefined) {
          setSoundEffectsEnabled(Boolean(session.is_sound_effects_enabled), false);
        } else if (session.is_sound_enabled !== undefined) {
          setSoundEffectsEnabled(Boolean(session.is_sound_enabled), false);
        }
        const now = Date.now();
        if (session.status === 'pre_game_countdown') {
          let startsAt = session.starts_at;
          if (typeof startsAt === 'string') {
            const parsed = Date.parse(startsAt);
            startsAt = !isNaN(parsed) ? parsed : Number(startsAt);
          } else if (startsAt) {
            startsAt = Number(startsAt);
          }
          startsAt = startsAt || now;
          if (startsAt > now - 45000) {
            isAutomatedEngineRunning = true;
            currentGameState = 'PRE_GAME';
            currentRound = session.current_round || session.round_number || currentRound || 1;
            updateHostEngineUI('IN PROGRESS');
          }
        } else if (session.status === 'question_active') {
          if (currentGameState === 'ROUND_SUMMARY' || hostEngineState === 'ROUND_SUMMARY') {
            return;
          }
          let endsAt = session.timer_ends_at;
          if (typeof endsAt === 'string') {
            const parsed = Date.parse(endsAt);
            endsAt = !isNaN(parsed) ? parsed : Number(endsAt);
          } else if (endsAt) {
            endsAt = Number(endsAt);
          }
          if (!endsAt || isNaN(endsAt)) {
            endsAt = now + (Number(session.duration_seconds) || 20) * 1000;
          }
          if ((endsAt - now) > -35000) {
            isAutomatedEngineRunning = true;
            currentGameState = 'QUESTION_ACTIVE';
            currentRound = session.current_round || session.round_number || currentRound || 1;
            currentQuestionIndex = session.current_question_index || currentQuestionIndex || 1;
            if (session.question_data) {
              currentQuestionData = session.question_data;
              const qInRound = ((currentQuestionIndex - 1) % 10) + 1;
              updateHostLiveStagePreviewCard(session.question_data, currentRound, qInRound);
            }
            updateHostEngineUI('IN PROGRESS');
          }
        } else if (session.status === 'round_summary' || session.status === 'inter_round') {
          currentGameState = 'ROUND_SUMMARY';
          isAutomatedEngineRunning = true;
          updateHostEngineUI('IN PROGRESS');
          const tvWinnerOverlay = document.getElementById('tv-winner-modal-overlay');
          if (tvWinnerOverlay && tvWinnerOverlay.classList.contains('hidden')) {
            let endsAt = session.timer_ends_at || session.starts_at;
            let targetEpoch = null;
            if (typeof endsAt === 'string') {
              const parsed = Date.parse(endsAt);
              targetEpoch = !isNaN(parsed) ? parsed : Number(endsAt);
            } else if (endsAt) {
              targetEpoch = Number(endsAt);
            }
            const rem = targetEpoch ? Math.max(0, Math.ceil((targetEpoch - Date.now()) / 1000)) : (Number(session.duration_seconds) || 120);
            onRoundWinner({
              top_scorers: playersLeaderboard.slice(0, 3),
              delaySeconds: rem,
              starts_at_epoch_ms: targetEpoch
            });
          }
        } else if (session.status === 'paused') {
          isAutomatedEngineRunning = false;
          currentGameState = 'PAUSED';
          if (session.current_round) currentRound = session.current_round;
          if (session.current_question_index !== undefined) currentQuestionIndex = session.current_question_index;
          if (session.remaining_question_seconds) pausedRemainingQuestionSeconds = Number(session.remaining_question_seconds);
          if (session.question_data) currentQuestionData = session.question_data;
          updateHostEngineUI('PAUSED');
        }

        if (session.is_ad_mode_active !== undefined) {
          const remoteAdActive = Boolean(session.is_ad_mode_active);
          if (isAdModeActive !== remoteAdActive) {
            isAdModeActive = remoteAdActive;
            safeStorage.setItem('bar_trivia_ad_mode_active', String(isAdModeActive));
            const toggle = document.getElementById('host-toggle-ad-mode');
            if (toggle) toggle.checked = isAdModeActive;
            syncTvSignageDisplay();
          }
        }
      }
    } catch (err) {
      console.warn('[Host Sync] Error checking active session:', err);
    }
  }

  triggerHostActiveSessionSync = checkHostActiveGameSession;
  checkHostActiveGameSession();
  setInterval(checkHostActiveGameSession, 2500);
}

function updateGenreQueueUI() {
  const genreChips = document.querySelectorAll('.genre-chip');
  const queueDisplay = document.getElementById('host-queue-list-display');

  genreChips.forEach(chip => {
    const genre = chip.dataset.genre;
    const qIndex = selectedGenreQueue.indexOf(genre);

    if (qIndex > -1) {
      chip.className = 'genre-chip in-queue';
      chip.innerHTML = `<span class="q-num-badge">#${qIndex + 1}</span> ${genre}`;
    } else {
      chip.className = 'genre-chip';
      chip.innerHTML = genre;
    }
  });

  if (!queueDisplay) return;

  if (selectedGenreQueue.length === 0) {
    queueDisplay.innerHTML = `<span class="queue-empty-msg">No genres queued yet (Will default to Auto Select)</span>`;
  } else {
    queueDisplay.innerHTML = selectedGenreQueue.map((g, i) => `
      <span class="queue-tag">#${i + 1} ${escapeHtml(g)}</span>
    `).join('');
  }

  const stageQueuePreview = document.getElementById('host-stage-queue-preview');
  if (stageQueuePreview) {
    if (selectedGenreQueue.length === 0) {
      stageQueuePreview.innerHTML = `<span class="queue-empty-msg">All 30 Specific Genres in Auto-Select Rotation</span>`;
    } else {
      stageQueuePreview.innerHTML = selectedGenreQueue.map((g, i) => `
        <span class="queue-tag">#${i + 1} ${escapeHtml(g)}</span>
      `).join('');
    }
  }
}

function onVenueNameUpdated({ venueName }) {
  const promoBarName = document.getElementById('promo-bar-name');
  if (promoBarName) promoBarName.textContent = (venueName || currentVenueName || "OUR PUB").toUpperCase();
}

function updateHostLogoPreview(logoUrl) {
  const hostLogoPreview = document.getElementById('host-logo-preview');
  const previewWrapper = document.getElementById('host-logo-preview-wrapper');

  if (logoUrl) {
    if (hostLogoPreview) hostLogoPreview.src = logoUrl;
    if (previewWrapper) previewWrapper.classList.remove('hidden');
  } else {
    if (previewWrapper) previewWrapper.classList.add('hidden');
  }
}

function onLogoUpdated({ logoUrl }) {
  const tvLogoImg = document.getElementById('tv-custom-logo-img');
  const tvLogoContainer = document.getElementById('tv-custom-logo-container');
  const tvBrandIcon = document.getElementById('tv-brand-icon');
  const promoLogoPlaceholder = document.getElementById('promo-logo-placeholder');

  const activeLogo = logoUrl || customBarLogoUrl;

  if (activeLogo) {
    if (tvLogoImg) tvLogoImg.src = activeLogo;
    if (tvLogoContainer) tvLogoContainer.classList.remove('hidden');
    if (tvBrandIcon) tvBrandIcon.classList.add('hidden');
    if (promoLogoPlaceholder) {
      promoLogoPlaceholder.innerHTML = `<img src="${activeLogo}" style="max-height: 70px; max-width: 140px; object-fit: contain;">`;
    }
  } else {
    if (tvLogoContainer) tvLogoContainer.classList.add('hidden');
    if (tvBrandIcon) tvBrandIcon.classList.remove('hidden');
    if (promoLogoPlaceholder) {
      promoLogoPlaceholder.innerHTML = `<span class="big-icon">🍺</span>`;
    }
  }
}

// CONTINUOUS ROTATING ADVERTISEMENT CAROUSEL (10 SECONDS PER SLIDE - 4 TOTAL SLIDES)
function startPromoCarouselRotation() {
  clearInterval(promoCarouselInterval);
  promoCarouselInterval = setInterval(() => {
    if (currentGameState !== 'LOBBY') return;

    currentPromoSlideIndex = (currentPromoSlideIndex % 4) + 1;
    updateCarouselSlide(currentPromoSlideIndex);
  }, 10000);
}

function initIndicatorClicks() {
  const indicators = document.querySelectorAll('.indicator');
  indicators.forEach(ind => {
    ind.addEventListener('click', () => {
      const target = parseInt(ind.getAttribute('data-slide-target'), 10) || 1;
      currentPromoSlideIndex = target;
      updateCarouselSlide(target);
    });
  });
}

function updateCarouselSlide(slideNumber) {
  const slides = document.querySelectorAll('.promo-slide');
  const indicators = document.querySelectorAll('.indicator');

  slides.forEach(s => {
    const isTarget = s.getAttribute('data-slide') === String(slideNumber);
    s.classList.toggle('active', isTarget);
  });

  indicators.forEach(i => {
    const isTarget = i.getAttribute('data-slide-target') === String(slideNumber);
    i.classList.toggle('active', isTarget);
  });
}

// ============================================================================
// AD DISPLAY SIGNAGE MODE ENGINE (INDEXEDDB CACHE, PDF.JS RENDERER & TV CAROUSEL)
// ============================================================================

// 1. Lightweight Native IndexedDB Helper to Store Multi-Megabyte High-Res Slides
const idbAdStorage = {
  dbPromise: null,
  getDB() {
    if (!this.dbPromise) {
      this.dbPromise = new Promise((resolve) => {
        if (typeof window === 'undefined' || !window.indexedDB) {
          resolve(null);
          return;
        }
        try {
          const request = window.indexedDB.open('BarRoomTriviaDB', 1);
          request.onupgradeneeded = (e) => {
            const db = e.target.result;
            if (!db.objectStoreNames.contains('ad_slides')) {
              db.createObjectStore('ad_slides', { keyPath: 'key' });
            }
          };
          request.onsuccess = () => resolve(request.result);
          request.onerror = () => resolve(null);
        } catch (e) {
          resolve(null);
        }
      });
    }
    return this.dbPromise;
  },
  async saveSlides(slides) {
    try {
      const db = await this.getDB();
      if (!db) {
        try {
          safeStorage.setItem('bar_trivia_ad_slides_fallback', JSON.stringify(slides.slice(0, 3)));
        } catch (_) {}
        return true;
      }
      return new Promise((resolve) => {
        try {
          const tx = db.transaction('ad_slides', 'readwrite');
          const store = tx.objectStore('ad_slides');
          store.put({ key: 'venue_ads', slides });
          tx.oncomplete = () => resolve(true);
          tx.onerror = () => resolve(false);
        } catch (err) {
          console.warn('[idbAdStorage] Save transaction error:', err);
          resolve(false);
        }
      });
    } catch (e) {
      console.warn('[idbAdStorage] Save error:', e);
      return false;
    }
  },
  async loadSlides() {
    try {
      const db = await this.getDB();
      if (!db) {
        const raw = safeStorage.getItem('bar_trivia_ad_slides_fallback');
        return raw ? JSON.parse(raw) : [];
      }
      return new Promise((resolve) => {
        try {
          const tx = db.transaction('ad_slides', 'readonly');
          const store = tx.objectStore('ad_slides');
          const req = store.get('venue_ads');
          req.onsuccess = () => {
            resolve(req.result?.slides || []);
          };
          req.onerror = () => resolve([]);
        } catch (err) {
          console.warn('[idbAdStorage] Load transaction error:', err);
          resolve([]);
        }
      });
    } catch (e) {
      console.warn('[idbAdStorage] Load error:', e);
      return [];
    }
  },
  async clearSlides() {
    try {
      const db = await this.getDB();
      if (!db) {
        safeStorage.removeItem('bar_trivia_ad_slides_fallback');
        return true;
      }
      return new Promise((resolve) => {
        try {
          const tx = db.transaction('ad_slides', 'readwrite');
          const store = tx.objectStore('ad_slides');
          store.delete('venue_ads');
          tx.oncomplete = () => resolve(true);
          tx.onerror = () => resolve(false);
        } catch (_) {
          resolve(false);
        }
      });
    } catch (e) {
      console.warn('[idbAdStorage] Clear error:', e);
      return false;
    }
  }
};

// 2. Ensure PDF.js is loaded from CDN or local environment
async function ensurePdfJsLoaded() {
  if (typeof window !== 'undefined' && window.pdfjsLib) {
    if (!window.pdfjsLib.GlobalWorkerOptions?.workerSrc) {
      window.pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
    }
    return window.pdfjsLib;
  }
  return new Promise((resolve, reject) => {
    if (typeof document === 'undefined') {
      reject(new Error('Document not available'));
      return;
    }
    const script = document.createElement('script');
    script.src = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js';
    script.onload = () => {
      if (window.pdfjsLib) {
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
        resolve(window.pdfjsLib);
      } else {
        reject(new Error('PDF.js failed to initialize'));
      }
    };
    script.onerror = () => reject(new Error('Failed to load PDF.js from CDN'));
    document.head.appendChild(script);
  });
}

// 3. Render multi-page PDF files into individual HD canvas slides
async function renderPdfFileToSlides(file) {
  const pdfjs = await ensurePdfJsLoaded();
  const arrayBuffer = await file.arrayBuffer();
  const loadingTask = pdfjs.getDocument({ data: arrayBuffer });
  const pdf = await loadingTask.promise;
  const slides = [];

  for (let pageNum = 1; pageNum <= pdf.numPages; pageNum++) {
    const page = await pdf.getPage(pageNum);
    // Render at 2.0 scale for crisp 1080p display
    const viewport = page.getViewport({ scale: 2.0 });
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    canvas.width = viewport.width;
    canvas.height = viewport.height;

    await page.render({ canvasContext: ctx, viewport }).promise;
    // Export as high-quality JPEG (0.90) for crisp text with lightweight storage
    const dataUrl = canvas.toDataURL('image/jpeg', 0.90);
    slides.push({
      id: `slide_${Date.now()}_${pageNum}_${Math.random().toString(36).substring(2, 6)}`,
      name: file.name,
      dataUrl,
      type: 'pdf',
      page: pageNum,
      totalPages: pdf.numPages,
      timestamp: Date.now()
    });
  }
  return slides;
}

// 4. Render direct image files (.png, .jpg, .webp) to slide
async function renderImageFileToSlide(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      const rawDataUrl = e.target.result;
      const img = new Image();
      img.onload = () => {
        try {
          const canvas = document.createElement('canvas');
          let width = img.naturalWidth || img.width;
          let height = img.naturalHeight || img.height;
          const maxDim = 1920;
          if (width > maxDim || height > maxDim) {
            if (width > height) {
              height = Math.round((height * maxDim) / width);
              width = maxDim;
            } else {
              width = Math.round((width * maxDim) / height);
              height = maxDim;
            }
          }
          canvas.width = Math.max(1, width);
          canvas.height = Math.max(1, height);
          const ctx = canvas.getContext('2d');
          ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
          const dataUrl = canvas.toDataURL('image/jpeg', 0.86);
          resolve([{
            id: `slide_${Date.now()}_1_${Math.random().toString(36).substring(2, 6)}`,
            name: file.name,
            dataUrl,
            type: 'image',
            page: 1,
            totalPages: 1,
            timestamp: Date.now()
          }]);
        } catch (_) {
          resolve([{
            id: `slide_${Date.now()}_1_${Math.random().toString(36).substring(2, 6)}`,
            name: file.name,
            dataUrl: rawDataUrl,
            type: 'image',
            page: 1,
            totalPages: 1,
            timestamp: Date.now()
          }]);
        }
      };
      img.onerror = () => {
        resolve([{
          id: `slide_${Date.now()}_1_${Math.random().toString(36).substring(2, 6)}`,
          name: file.name,
          dataUrl: rawDataUrl,
          type: 'image',
          page: 1,
          totalPages: 1,
          timestamp: Date.now()
        }]);
      };
      img.src = rawDataUrl;
    };
    reader.onerror = () => reject(new Error('Failed to read image file'));
    reader.readAsDataURL(file);
  });
}

// 5. Official Bar Rooms Trivia Permanent System Ad Generator
const OFFICIAL_SYSTEM_AD_ID = 'system_bar_rooms_trivia_official_ad';
let cachedOfficialAdSlide = null;

function generateOfficialBarRoomsTriviaAdDataUrl() {
  const canvas = document.createElement('canvas');
  canvas.width = 1920;
  canvas.height = 1080;
  const ctx = canvas.getContext('2d');
  if (!ctx) return '';

  // 1. Deep Sleek Dark Theme Gradient Background
  const bgGrad = ctx.createLinearGradient(0, 0, 1920, 1080);
  bgGrad.addColorStop(0, '#0a0a14');
  bgGrad.addColorStop(0.35, '#121026');
  bgGrad.addColorStop(0.7, '#161330');
  bgGrad.addColorStop(1, '#0b0918');
  ctx.fillStyle = bgGrad;
  ctx.fillRect(0, 0, 1920, 1080);

  // 2. Ambient Lighting Glow Orbs
  function drawGlow(x, y, r, color) {
    const g = ctx.createRadialGradient(x, y, 0, x, y, r);
    g.addColorStop(0, color);
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }
  drawGlow(960, 120, 600, 'rgba(0, 229, 255, 0.16)');
  drawGlow(200, 850, 500, 'rgba(255, 214, 0, 0.14)');
  drawGlow(1700, 850, 550, 'rgba(124, 77, 255, 0.20)');
  drawGlow(1600, 200, 400, 'rgba(255, 0, 122, 0.10)');

  // Helper: Rounded Rectangle
  function roundRect(x, y, w, h, r, fill, stroke, strokeWidth) {
    ctx.save();
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + w - r, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + r);
    ctx.lineTo(x + w, y + h - r);
    ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    ctx.lineTo(x + r, y + h);
    ctx.quadraticCurveTo(x, y + h, x, y + h - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
    if (fill) {
      ctx.fillStyle = fill;
      ctx.fill();
    }
    if (stroke) {
      ctx.strokeStyle = stroke;
      ctx.lineWidth = strokeWidth || 1;
      ctx.stroke();
    }
    ctx.restore();
  }

  // Text wrap helper
  function wrapText(text, x, y, maxWidth, lineHeight, fill, font) {
    ctx.save();
    if (font) ctx.font = font;
    if (fill) ctx.fillStyle = fill;
    const words = text.split(' ');
    let line = '';
    let currentY = y;
    for (let n = 0; n < words.length; n++) {
      const testLine = line + words[n] + ' ';
      const metrics = ctx.measureText(testLine);
      if (metrics.width > maxWidth && n > 0) {
        ctx.fillText(line, x, currentY);
        line = words[n] + ' ';
        currentY += lineHeight;
      } else {
        line = testLine;
      }
    }
    ctx.fillText(line, x, currentY);
    ctx.restore();
  }

  // 3. Outer Neon Accent Border
  roundRect(24, 24, 1872, 1032, 28, null, 'rgba(0, 229, 255, 0.35)', 2);

  // 4. Header Section
  // Pill Badge at top
  roundRect(710, 48, 500, 36, 18, 'rgba(0, 229, 255, 0.15)', 'rgba(0, 229, 255, 0.6)', 1.5);
  ctx.font = "900 14px 'Outfit', 'Inter', sans-serif";
  ctx.fillStyle = '#00e5ff';
  ctx.textAlign = 'center';
  ctx.fillText('⚡ OFFICIAL BAR & HOME TRIVIA APP ⚡', 960, 72);

  // App Title
  ctx.font = "900 60px 'Outfit', 'Inter', sans-serif";
  ctx.fillStyle = '#ffffff';
  ctx.shadowColor = 'rgba(0, 229, 255, 0.7)';
  ctx.shadowBlur = 24;
  ctx.fillText('BAR ROOMS TRIVIA', 960, 142);
  ctx.shadowBlur = 0;

  // Catchy Hook
  ctx.font = "800 26px 'Outfit', 'Inter', sans-serif";
  ctx.fillStyle = '#ffd600';
  ctx.fillText('HOST YOUR OWN PUB TRIVIA NIGHT AT HOME & VENUES!', 960, 184);

  // Subhead
  ctx.font = "500 16px 'Inter', sans-serif";
  ctx.fillStyle = '#94a3b8';
  ctx.fillText('Turn any TV and mobile phones into an interactive game show for parties, game nights & events.', 960, 214);

  // 5. 6 Key Feature Cards Grid (3 cols x 2 rows)
  const features = [
    {
      icon: '📱',
      title: 'PLAY ON ANY PHONE',
      color: '#00e5ff',
      desc: 'No app download needed for players! Guests scan the TV QR code with their mobile cameras to join and buzz in instantly.'
    },
    {
      icon: '⚡',
      title: 'REAL-TIME MULTIPLAYER',
      color: '#00e5ff',
      desc: 'Instant 20s countdown timers, live buzzer answers, and synchronized scoring on both TV and phones with zero lag.'
    },
    {
      icon: '🏆',
      title: 'LIVE TV LEADERBOARD',
      color: '#ffd600',
      desc: 'Standings update in real-time on the big screen! Watch players climb the ranks with speed bonuses and round bonuses.'
    },
    {
      icon: '🎯',
      title: '30+ TRIVIA GENRES',
      color: '#00e676',
      desc: 'Pop Culture, 80s/90s Nostalgia, Sports, History, Science, Literature, Riddles & thousands of fresh curated questions!'
    },
    {
      icon: '🤖',
      title: 'AUTOMATED GAME HOST',
      color: '#ff007a',
      desc: 'Sit back and enjoy your party! Built-in automated host mode runs rounds, reads questions, and tallies winners hands-free.'
    },
    {
      icon: '🏠',
      title: 'PERFECT FOR TRIVIA PARTIES',
      color: '#ffd600',
      desc: 'Great for family game nights, house parties, brewery taprooms, birthday bashes, office socials, and holiday events!'
    }
  ];

  ctx.textAlign = 'left';
  features.forEach((feat, idx) => {
    const col = idx % 3;
    const row = Math.floor(idx / 3);
    const cardX = 80 + col * 600;
    const cardY = 246 + row * 194;
    const cardW = 560;
    const cardH = 176;

    // Card background & border
    roundRect(cardX, cardY, cardW, cardH, 16, 'rgba(22, 22, 34, 0.88)', 'rgba(255, 255, 255, 0.12)', 1.5);

    // Feature Icon circle
    roundRect(cardX + 20, cardY + 24, 48, 48, 12, 'rgba(255, 255, 255, 0.06)', 'rgba(255, 255, 255, 0.15)', 1);
    ctx.font = '26px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(feat.icon, cardX + 44, cardY + 58);

    // Feature Title
    ctx.font = "800 20px 'Outfit', 'Inter', sans-serif";
    ctx.fillStyle = feat.color;
    ctx.textAlign = 'left';
    ctx.fillText(feat.title, cardX + 82, cardY + 54);

    // Feature Description
    wrapText(feat.desc, cardX + 22, cardY + 104, cardW - 44, 23, '#cbd5e1', "400 14px 'Inter', sans-serif");
  });

  // 6. Bottom Section: Home Party Highlight (Left) & Google Play Store Badge (Right)
  const botY = 650;
  const botH = 370;

  // Left Card: Home Party Highlight
  const leftW = 1170;
  roundRect(80, botY, leftW, botH, 20, 'rgba(18, 18, 30, 0.92)', 'rgba(0, 229, 255, 0.35)', 2);

  // Badge pill
  roundRect(110, botY + 28, 360, 32, 16, 'rgba(0, 230, 118, 0.15)', 'rgba(0, 230, 118, 0.5)', 1);
  ctx.font = "800 13px 'Outfit', 'Inter', sans-serif";
  ctx.fillStyle = '#00e676';
  ctx.textAlign = 'center';
  ctx.fillText('🏡 USE AT HOME FOR TRIVIA NIGHT PARTIES', 290, botY + 49);

  // Big Headline
  ctx.font = "900 32px 'Outfit', 'Inter', sans-serif";
  ctx.fillStyle = '#ffffff';
  ctx.textAlign = 'left';
  ctx.fillText('BRING THE EXCITEMENT OF PUB TRIVIA HOME!', 110, botY + 115);

  // Explanatory Paragraph
  const homeDesc = 'No pens, no paper answer sheets, and no manual score calculation! Hook up your laptop, tablet, or smart TV, gather your friends and family, and start playing in under 60 seconds.';
  wrapText(homeDesc, 110, botY + 165, leftW - 80, 32, '#94a3b8', "500 20px 'Inter', sans-serif");

  // Home party chips: Family Game Nights, Friends & House Parties, Office & Team Socials, Holiday & Birthday Parties
  const homePartyChips = ['Family Game Nights', 'Friends & House Parties', 'Office & Team Socials', 'Holiday & Birthday Parties'];
  let chipX = 110;
  homePartyChips.forEach(chip => {
    ctx.font = "600 14px 'Inter', sans-serif";
    const chipW = ctx.measureText(chip).width + 24;
    roundRect(chipX, botY + 235, chipW, 28, 14, 'rgba(0, 229, 255, 0.1)', 'rgba(0, 229, 255, 0.35)', 1);
    ctx.fillStyle = '#00e5ff';
    ctx.textAlign = 'left';
    ctx.fillText(chip, chipX + 12, botY + 254);
    chipX += chipW + 12;
  });

  // Footer Tagline on Left Card
  ctx.font = "600 16px 'Inter', sans-serif";
  ctx.fillStyle = 'rgba(255, 255, 255, 0.75)';
  ctx.fillText('★ Compatible with any Smart TV, Projector, Laptop, Tablet, Android Phone & iPhone ★', 110, botY + 285);

  // Right Corner Card: Google Play Store Callout
  const rightX = 1270;
  const rightW = 570;
  roundRect(rightX, botY, rightW, botH, 20, 'rgba(16, 16, 26, 0.96)', 'rgba(0, 229, 255, 0.5)', 2);

  // Header inside right card
  roundRect(rightX + 30, botY + 28, 260, 32, 16, 'rgba(0, 229, 255, 0.18)', 'rgba(0, 229, 255, 0.6)', 1.5);
  ctx.font = "800 13px 'Outfit', 'Inter', sans-serif";
  ctx.fillStyle = '#00e5ff';
  ctx.textAlign = 'center';
  ctx.fillText('📱 GET THE HOST APP', rightX + 160, botY + 49);

  // Action text
  ctx.font = "800 24px 'Outfit', 'Inter', sans-serif";
  ctx.fillStyle = '#ffffff';
  ctx.textAlign = 'left';
  ctx.fillText('DOWNLOAD FROM GOOGLE PLAY', rightX + 30, botY + 98);

  ctx.font = "400 14px 'Inter', sans-serif";
  ctx.fillStyle = '#94a3b8';
  ctx.fillText('Install the official app on your Android Phone, Tablet or Google TV:', rightX + 30, botY + 128);

  // Official-looking Google Play Store Badge Button
  const badgeX = rightX + 30;
  const badgeY = botY + 152;
  const badgeW = 510;
  const badgeH = 96;
  roundRect(badgeX, badgeY, badgeW, badgeH, 16, '#000000', 'rgba(255, 255, 255, 0.35)', 2);

  // Draw Google Play Multi-Color Triangle Icon
  const iconCenterX = badgeX + 46;
  const iconCenterY = badgeY + 48;

  // Blue segment
  ctx.fillStyle = '#00e5ff';
  ctx.beginPath();
  ctx.moveTo(iconCenterX - 20, iconCenterY - 26);
  ctx.lineTo(iconCenterX + 16, iconCenterY);
  ctx.lineTo(iconCenterX - 4, iconCenterY);
  ctx.closePath();
  ctx.fill();

  // Green segment
  ctx.fillStyle = '#00e676';
  ctx.beginPath();
  ctx.moveTo(iconCenterX + 16, iconCenterY);
  ctx.lineTo(iconCenterX + 28, iconCenterY + 10);
  ctx.lineTo(iconCenterX - 20, iconCenterY + 26);
  ctx.closePath();
  ctx.fill();

  // Yellow segment
  ctx.fillStyle = '#ffd600';
  ctx.beginPath();
  ctx.moveTo(iconCenterX + 16, iconCenterY);
  ctx.lineTo(iconCenterX + 28, iconCenterY - 10);
  ctx.lineTo(iconCenterX - 20, iconCenterY - 26);
  ctx.closePath();
  ctx.fill();

  // Red/Pink segment
  ctx.fillStyle = '#ff007a';
  ctx.beginPath();
  ctx.moveTo(iconCenterX + 16, iconCenterY);
  ctx.lineTo(iconCenterX + 28, iconCenterY - 10);
  ctx.lineTo(iconCenterX + 28, iconCenterY + 10);
  ctx.closePath();
  ctx.fill();

  // Badge Text
  ctx.fillStyle = '#e2e8f0';
  ctx.font = "600 14px 'Inter', sans-serif";
  ctx.fillText('GET IT ON', badgeX + 90, badgeY + 36);

  ctx.fillStyle = '#ffffff';
  ctx.font = "800 32px 'Outfit', 'Inter', sans-serif";
  ctx.fillText('Google Play', badgeX + 90, badgeY + 74);

  // Sub-badge callout
  ctx.font = "700 13px 'Outfit', 'Inter', sans-serif";
  ctx.fillStyle = '#00e5ff';
  ctx.fillText('✓ Search "Bar Rooms Trivia" on Google Play Store', rightX + 30, botY + 280);

  // Web play link
  roundRect(rightX + 30, botY + 300, 510, 48, 10, 'rgba(255, 255, 255, 0.05)', 'rgba(255, 214, 0, 0.3)', 1);
  ctx.font = "700 14px 'Inter', sans-serif";
  ctx.fillStyle = '#ffd600';
  ctx.fillText('🌐 Or Play Instantly Online: todd4529.github.io/BarRoomTrivia', rightX + 46, botY + 330);

  return canvas.toDataURL('image/jpeg', 0.92);
}

function getOfficialBarRoomsTriviaAdSlide() {
  if (cachedOfficialAdSlide) return cachedOfficialAdSlide;
  try {
    const dataUrl = generateOfficialBarRoomsTriviaAdDataUrl();
    cachedOfficialAdSlide = {
      id: OFFICIAL_SYSTEM_AD_ID,
      name: 'Bar Rooms Trivia (Official App Ad)',
      dataUrl: dataUrl,
      type: 'system',
      page: 1,
      totalPages: 1,
      isSystemPermanent: true,
      timestamp: 0
    };
  } catch (err) {
    console.error('Error generating official Bar Rooms Trivia ad:', err);
  }
  return cachedOfficialAdSlide;
}

function getAllActiveAdSlides() {
  const officialAd = getOfficialBarRoomsTriviaAdSlide();
  return [officialAd, ...customAdSlides];
}

// 6. TV Ad Signage Synchronization & Carousel Rotation
function syncTvSignageDisplay() {
  const tvAdScreen = document.getElementById('tv-ad-signage-screen');
  const tvPromoScreen = document.getElementById('tv-promo-screen');
  const tvLiveGrid = document.getElementById('tv-live-grid');
  const btnPromo = document.getElementById('btn-tv-toggle-promo');
  const btnLive = document.getElementById('btn-tv-toggle-live');

  // Active game play ALWAYS overrides ad mode
  if (currentGameState === 'QUESTION_ACTIVE' || currentGameState === 'PRE_GAME') {
    if (tvAdScreen) tvAdScreen.classList.add('hidden');
    stopTvAdSignageRotation();
    const tvAdBanner = document.getElementById('tv-ad-intermission-banner');
    if (tvAdBanner) tvAdBanner.classList.add('hidden');
    return;
  }

  const allSlides = getAllActiveAdSlides();
  const isIntermission = currentGameState === 'ROUND_SUMMARY' || hostEngineState === 'ROUND_SUMMARY';

  // Intermission between rounds or active ad mode: ALWAYS display ads!
  if ((isAdModeActive || isIntermission) && allSlides && allSlides.length > 0) {
    if (tvPromoScreen) tvPromoScreen.classList.add('hidden');
    if (tvLiveGrid) tvLiveGrid.classList.add('hidden');
    if (tvAdScreen) tvAdScreen.classList.remove('hidden');
    if (btnPromo) btnPromo.classList.add('active');
    if (btnLive) btnLive.classList.remove('active');
    if (!adRotationTimeout) {
      startTvAdSignageRotation();
    }

    const tvAdBanner = document.getElementById('tv-ad-intermission-banner');
    if (tvAdBanner) {
      if (isIntermission) {
        tvAdBanner.classList.remove('hidden');
      } else {
        tvAdBanner.classList.add('hidden');
      }
    }
  } else {
    if (tvAdScreen) tvAdScreen.classList.add('hidden');
    stopTvAdSignageRotation();
    const isLiveActive = btnLive?.classList.contains('active');
    if (currentGameState === 'PAUSED' || currentGameState === 'QUESTION_ACTIVE' || currentGameState === 'PRE_GAME' || isLiveActive) {
      if (tvLiveGrid) tvLiveGrid.classList.remove('hidden');
      if (tvPromoScreen) tvPromoScreen.classList.add('hidden');
      if (btnLive) btnLive.classList.add('active');
      if (btnPromo) btnPromo.classList.remove('active');
    } else {
      if (tvLiveGrid) tvLiveGrid.classList.add('hidden');
      if (tvPromoScreen) tvPromoScreen.classList.remove('hidden');
      if (btnPromo) btnPromo.classList.add('active');
      startPromoCarouselRotation();
    }
  }
}

function startTvAdSignageRotation() {
  stopTvAdSignageRotation();
  const allSlides = getAllActiveAdSlides();
  if (!allSlides || allSlides.length === 0) return;

  if (currentAdSlideIndex >= allSlides.length) {
    currentAdSlideIndex = 0;
  }

  displayAdSlide(currentAdSlideIndex);

  const progressFill = document.getElementById('tv-ad-progress-fill');
  if (progressFill) {
    progressFill.style.width = '0%';
    progressFill.style.transition = 'none';
    requestAnimationFrame(() => {
      progressFill.style.transition = `width ${adSlideDurationSeconds || 10}s linear`;
      progressFill.style.width = '100%';
    });
  }

  const totalMs = (adSlideDurationSeconds || 10) * 1000;

  if (adProgressBarInterval) clearInterval(adProgressBarInterval);
  const startMs = Date.now();
  adProgressBarInterval = setInterval(() => {
    const elapsed = Date.now() - startMs;
    const pct = Math.min(100, (elapsed / totalMs) * 100);
    if (progressFill) progressFill.style.width = `${pct}%`;
    if (elapsed >= totalMs) clearInterval(adProgressBarInterval);
  }, 100);

  adRotationTimeout = setTimeout(() => {
    const slides = getAllActiveAdSlides();
    currentAdSlideIndex = (currentAdSlideIndex + 1) % slides.length;
    startTvAdSignageRotation();
  }, totalMs);
}

function stopTvAdSignageRotation() {
  if (adRotationTimeout) {
    clearTimeout(adRotationTimeout);
    adRotationTimeout = null;
  }
  if (adProgressBarInterval) {
    clearInterval(adProgressBarInterval);
    adProgressBarInterval = null;
  }
}

function displayAdSlide(index) {
  const allSlides = getAllActiveAdSlides();
  if (!allSlides || allSlides.length === 0) return;
  const safeIndex = index % allSlides.length;
  const slide = allSlides[safeIndex];
  if (!slide) return;

  const img = document.getElementById('tv-ad-slide-img');
  const counterText = document.getElementById('tv-ad-slide-counter-text');
  slide.dataUrl = slide.dataUrl || slide.data_url || slide.url || slide.image_url || '';

  if (img && slide.dataUrl) {
    if (!img.src || img.src === window.location.href || img.src.endsWith('/') || img.classList.contains('fading')) {
      img.src = slide.dataUrl;
      img.classList.remove('fading');
    } else {
      img.classList.add('fading');
      setTimeout(() => {
        img.src = slide.dataUrl;
        img.classList.remove('fading');
      }, 200);
    }
  }

  if (counterText) {
    const prefix = currentGameState === 'PAUSED' ? 'GAME PAUSED • ' : '';
    counterText.textContent = `${prefix}AD ${safeIndex + 1} OF ${allSlides.length}`.toUpperCase();
  }
}

// 7. Host Gallery Thumbnail Management
function renderHostAdGallery() {
  const gallery = document.getElementById('host-ad-gallery');
  const countEl = document.getElementById('host-ad-count');
  const allSlides = getAllActiveAdSlides();
  if (countEl) countEl.textContent = allSlides.length;

  if (!gallery) return;

  gallery.innerHTML = '';
  allSlides.forEach((slide, index) => {
    const card = document.createElement('div');
    card.className = slide.isSystemPermanent ? 'ad-thumb-card system-card' : 'ad-thumb-card';
    card.setAttribute('data-slide-id', slide.id);

    const displayName = (slide.totalPages > 1) 
      ? `${slide.name} (P.${slide.page}/${slide.totalPages})`
      : slide.name;

    if (slide.isSystemPermanent) {
      card.innerHTML = `
        <img src="${slide.dataUrl}" alt="${displayName}" class="ad-thumb-img">
        <div class="ad-thumb-system-tag">⭐ OFFICIAL APP AD</div>
        <div class="ad-thumb-lock-badge" title="Permanent System Ad - Displays in all rotations">🔒</div>
        <div class="ad-thumb-badge" title="${displayName}">${displayName}</div>
      `;
    } else {
      const customIndex = index - 1; // 0-based index in customAdSlides
      card.innerHTML = `
        <img src="${slide.dataUrl}" alt="${displayName}" class="ad-thumb-img">
        <div class="ad-thumb-badge" title="${displayName}">${displayName}</div>
        <button type="button" class="btn-remove-ad-slide" title="Delete Custom Slide" data-custom-index="${customIndex}">✕</button>
      `;

      const removeBtn = card.querySelector('.btn-remove-ad-slide');
      removeBtn?.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        removeCustomAdSlide(customIndex);
      });
    }

    gallery.appendChild(card);
  });
}

async function removeCustomAdSlide(customIndex) {
  if (customIndex < 0 || customIndex >= customAdSlides.length) return;
  customAdSlides.splice(customIndex, 1);
  const allSlides = getAllActiveAdSlides();
  if (currentAdSlideIndex >= allSlides.length) {
    currentAdSlideIndex = 0;
  }
  await idbAdStorage.saveSlides(customAdSlides);
  renderHostAdGallery();
  broadcastAdSlidesUpdated();
  syncTvSignageDisplay();
}

async function clearAllAdSlides() {
  customAdSlides = [];
  currentAdSlideIndex = 0;
  await idbAdStorage.clearSlides();
  renderHostAdGallery();
  broadcastAdSlidesUpdated();
  syncTvSignageDisplay();
}

// 8. Cross-Device Realtime & Channel Broadcasting
function broadcastAdModeChange() {
  const allSlides = getAllActiveAdSlides();
  const payload = {
    isAdModeActive,
    adSlideDurationSeconds,
    slidesCount: allSlides.length,
    customSlidesCount: customAdSlides.length
  };
  try {
    channel.postMessage({ type: 'AD_MODE_TOGGLED', payload });
    broadcastRealtimeEvent('ad_mode_toggled', payload);
  } catch (e) {
    console.warn('Ad mode broadcast error:', e);
  }

  try {
    supabase.from('game_sessions').upsert({
      room_code: (currentRoomCode || 'TRIV').toUpperCase(),
      is_ad_mode_active: isAdModeActive,
      updated_at: new Date().toISOString()
    }, { onConflict: 'room_code' }).catch(() => {});
  } catch (_) {}
}

function broadcastAdSlidesUpdated() {
  broadcastAdModeChange();
  const allSlides = getAllActiveAdSlides();
  try {
    channel.postMessage({
      type: 'AD_SLIDES_UPDATED',
      payload: {
        slides: customAdSlides,
        isAdModeActive,
        adSlideDurationSeconds,
        slidesCount: allSlides.length
      }
    });
    broadcastRealtimeEvent('ad_slides_updated', {
      slides: customAdSlides,
      slidesCount: allSlides.length,
      isAdModeActive,
      adSlideDurationSeconds
    });
  } catch (e) {
    console.warn('Ad slides broadcast error:', e);
  }

  try {
    if (typeof supabase !== 'undefined' && supabase) {
      supabase.from('game_sessions').upsert({
        room_code: (currentRoomCode || 'TRIV').toUpperCase(),
        is_ad_mode_active: isAdModeActive,
        ad_slides: customAdSlides,
        updated_at: new Date().toISOString()
      }, { onConflict: 'room_code' }).then(() => {}).catch(() => {});
    }
  } catch (_) {}
}

function onAdModeToggled(payload) {
  if (!payload) return;
  if (payload.isAdModeActive !== undefined) {
    isAdModeActive = Boolean(payload.isAdModeActive);
    safeStorage.setItem('bar_trivia_ad_mode_active', String(isAdModeActive));
    const toggle = document.getElementById('host-toggle-ad-mode');
    if (toggle) toggle.checked = isAdModeActive;
  }
  if (payload.adSlideDurationSeconds !== undefined) {
    adSlideDurationSeconds = parseInt(payload.adSlideDurationSeconds, 10);
    safeStorage.setItem('bar_trivia_ad_duration', String(adSlideDurationSeconds));
    const durChips = document.querySelectorAll('.ad-dur-chip');
    durChips.forEach(chip => {
      chip.classList.toggle('active', parseInt(chip.dataset.dur, 10) === adSlideDurationSeconds);
    });
  }
  syncTvSignageDisplay();
}

async function onAdSlidesUpdated(payload) {
  onAdModeToggled(payload);
  if (payload && Array.isArray(payload.slides) && payload.slides.length > 0) {
    customAdSlides = payload.slides;
    await idbAdStorage.saveSlides(customAdSlides);
    try {
      safeStorage.setItem('bar_trivia_custom_ad_slides', JSON.stringify(customAdSlides.slice(0, 5)));
    } catch (_) {}
  } else {
    customAdSlides = await idbAdStorage.loadSlides();
    if (!customAdSlides || customAdSlides.length === 0) {
      try {
        const fallback = safeStorage.getItem('bar_trivia_custom_ad_slides');
        if (fallback) customAdSlides = JSON.parse(fallback);
      } catch (_) {}
    }
  }
  renderHostAdGallery();
  stopTvAdSignageRotation();
  startTvAdSignageRotation();
  syncTvSignageDisplay();
}

// 9. Host Settings UI Listeners Initialization
function initHostAdSettings() {
  const toggleAdMode = document.getElementById('host-toggle-ad-mode');
  const fileInput = document.getElementById('host-ad-files-input');
  const dropzone = document.getElementById('host-ad-dropzone');
  const uploadStatus = document.getElementById('host-ad-upload-status');
  const durChips = document.querySelectorAll('.ad-dur-chip');
  const btnClearAll = document.getElementById('btn-clear-all-ads');

  // Master switch - default is toggled OFF when loading host controls screen
  isAdModeActive = false;
  safeStorage.setItem('bar_trivia_ad_mode_active', 'false');
  if (toggleAdMode) {
    toggleAdMode.checked = false;
    toggleAdMode.addEventListener('change', () => {
      isAdModeActive = toggleAdMode.checked;
      safeStorage.setItem('bar_trivia_ad_mode_active', String(isAdModeActive));
      broadcastAdModeChange();
      syncTvSignageDisplay();
    });
  }

  // Sound Effects permanently removed per user request

  // Duration Chips
  durChips.forEach(chip => {
    const dur = parseInt(chip.dataset.dur, 10);
    chip.classList.toggle('active', dur === adSlideDurationSeconds);
    chip.addEventListener('click', (e) => {
      e.preventDefault();
      durChips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      adSlideDurationSeconds = dur;
      safeStorage.setItem('bar_trivia_ad_duration', String(adSlideDurationSeconds));
      broadcastAdModeChange();
      const allSlides = getAllActiveAdSlides();
      if (isAdModeActive && allSlides.length > 0) {
        startTvAdSignageRotation();
      }
    });
  });

  // Clear Custom Ads Button
  btnClearAll?.addEventListener('click', (e) => {
    e.preventDefault();
    clearAllAdSlides();
  });

  // File Upload Processing
  async function handleFilesUpload(files) {
    if (!files || files.length === 0) return;
    if (uploadStatus) {
      uploadStatus.classList.remove('hidden');
      uploadStatus.textContent = `⏳ Processing ${files.length} file(s)...`;
    }

    const newSlides = [];
    try {
      for (const file of Array.from(files)) {
        const isPdf = file.type === 'application/pdf' || file.name.toLowerCase().endsWith('.pdf');
        if (isPdf) {
          if (uploadStatus) uploadStatus.textContent = `📄 Rendering PDF: ${file.name}...`;
          const pdfSlides = await renderPdfFileToSlides(file);
          newSlides.push(...pdfSlides);
        } else if (file.type.startsWith('image/') || /\.(png|jpe?g|webp)$/i.test(file.name)) {
          if (uploadStatus) uploadStatus.textContent = `🖼️ Processing image: ${file.name}...`;
          const imgSlides = await renderImageFileToSlide(file);
          newSlides.push(...imgSlides);
        }
      }

      if (newSlides.length > 0) {
        customAdSlides.push(...newSlides);
        await idbAdStorage.saveSlides(customAdSlides);
        try {
          safeStorage.setItem('bar_trivia_custom_ad_slides', JSON.stringify(customAdSlides.slice(0, 5)));
        } catch (_) {}
        renderHostAdGallery();
        broadcastAdSlidesUpdated();

        // Automatically toggle Ad Mode ON if it was OFF
        if (!isAdModeActive) {
          isAdModeActive = true;
          safeStorage.setItem('bar_trivia_ad_mode_active', 'true');
          if (toggleAdMode) toggleAdMode.checked = true;
          broadcastAdModeChange();
        }

        // Jump directly to the newly uploaded custom ad so it displays immediately!
        const allSlides = getAllActiveAdSlides();
        currentAdSlideIndex = allSlides.length > 1 ? 1 : 0;
        stopTvAdSignageRotation();
        displayAdSlide(currentAdSlideIndex);
        startTvAdSignageRotation();
        syncTvSignageDisplay();

        if (uploadStatus) {
          uploadStatus.textContent = `✅ Successfully added ${newSlides.length} custom slide(s)!`;
          setTimeout(() => uploadStatus.classList.add('hidden'), 3500);
        }
      } else {
        if (uploadStatus) {
          uploadStatus.textContent = `⚠️ No valid PDF or image files found.`;
          setTimeout(() => uploadStatus.classList.add('hidden'), 3500);
        }
      }
    } catch (err) {
      console.error('Error uploading ad files:', err);
      if (uploadStatus) {
        uploadStatus.textContent = `❌ Error: ${err.message || 'Failed to process files'}`;
        setTimeout(() => uploadStatus.classList.add('hidden'), 5000);
      }
    }

    if (fileInput) fileInput.value = '';
  }

  fileInput?.addEventListener('change', (e) => {
    handleFilesUpload(e.target.files);
  });

  // Drag and Drop on dropzone
  if (dropzone) {
    ['dragenter', 'dragover'].forEach(eventName => {
      dropzone.addEventListener(eventName, (e) => {
        e.preventDefault();
        e.stopPropagation();
        dropzone.classList.add('dragover');
      });
    });

    ['dragleave', 'drop'].forEach(eventName => {
      dropzone.addEventListener(eventName, (e) => {
        e.preventDefault();
        e.stopPropagation();
        dropzone.classList.remove('dragover');
      });
    });

    dropzone.addEventListener('drop', (e) => {
      const dt = e.dataTransfer;
      if (dt && dt.files && dt.files.length > 0) {
        handleFilesUpload(dt.files);
      }
    });
  }
}

// 10. Initial Load from IndexedDB
async function loadAdSlidesAndInit() {
  try {
    customAdSlides = await idbAdStorage.loadSlides();
    if (!customAdSlides || customAdSlides.length === 0) {
      try {
        const fallback = safeStorage.getItem('bar_trivia_custom_ad_slides');
        if (fallback) customAdSlides = JSON.parse(fallback);
      } catch (_) {}
    }
  } catch (e) {
    console.warn('Could not load ad slides:', e);
    try {
      const fallback = safeStorage.getItem('bar_trivia_custom_ad_slides');
      if (fallback) customAdSlides = JSON.parse(fallback);
      else customAdSlides = [];
    } catch (_) {
      customAdSlides = [];
    }
  }
  renderHostAdGallery();
  syncTvSignageDisplay();
}

// Expose Ad mode helpers globally for testing and console inspection
window.idbAdStorage = idbAdStorage;
window.customAdSlides = customAdSlides;
window.isAdModeActive = () => isAdModeActive;
window.getOfficialBarRoomsTriviaAdSlide = getOfficialBarRoomsTriviaAdSlide;
window.getAllActiveAdSlides = getAllActiveAdSlides;
window.syncTvSignageDisplay = syncTvSignageDisplay;
window.startTvAdSignageRotation = startTvAdSignageRotation;
window.stopTvAdSignageRotation = stopTvAdSignageRotation;
window.clearAllAdSlides = clearAllAdSlides;
window.removeCustomAdSlide = removeCustomAdSlide;
window.renderHostAdGallery = renderHostAdGallery;
window.playSound = playSound;
window.setSoundEffectsEnabled = setSoundEffectsEnabled;
window.isSoundEffectsEnabled = () => isSoundEffectsEnabled;
window.unlockAudioContext = unlockAudioContext;
window.updateTvAudioUI = updateTvAudioUI;
window.showNetworkStatus = showNetworkStatus;

function renderHostPlayersRoster() {
  const rosterList = document.getElementById('host-connected-players-list');
  const countBadge = document.getElementById('host-live-player-badge');
  const tabBadge = document.getElementById('host-tab-player-count');
  const statPlayers = document.getElementById('stat-players-count');

  const validPlayers = playersLeaderboard.filter(p => p && p.nickname && !isFictitiousPlayer(p.nickname));
  const count = validPlayers.length;

  if (countBadge) countBadge.textContent = `${count} Active`;
  if (tabBadge) tabBadge.textContent = count;
  if (statPlayers) statPlayers.textContent = count;

  if (!rosterList) return;

  if (count === 0) {
    rosterList.innerHTML = `
      <div class="host-empty-roster">
        <span class="empty-icon">📱</span>
        <p class="empty-headline">No players joined yet</p>
        <small>Players can scan the TV QR code or join with room code <strong>${escapeHtml(currentRoomCode)}</strong>.</small>
      </div>
    `;
    return;
  }

  // Sorted by cumulative score descending
  const sorted = [...validPlayers].sort((a, b) => {
    const sA = Number(a.score ?? a.cumulative_score ?? 0);
    const sB = Number(b.score ?? b.cumulative_score ?? 0);
    if (sB !== sA) return sB - sA;
    return (a.nickname || '').localeCompare(b.nickname || '');
  });

  rosterList.innerHTML = sorted.map((p, idx) => {
    const score = Number(p.score ?? p.cumulative_score ?? 0);
    const rankClass = idx === 0 ? 'rank-1' : (idx === 1 ? 'rank-2' : (idx === 2 ? 'rank-3' : ''));
    const medal = idx === 0 ? '🥇' : (idx === 1 ? '🥈' : (idx === 2 ? '🥉' : `#${idx + 1}`));
    const streakHtml = (p.streak && p.streak > 1) ? `<span class="player-streak-tag">🔥 ${p.streak} streak</span>` : '';
    
    return `
      <div class="host-player-item ${rankClass}">
        <div class="player-item-left">
          <span class="player-rank-badge ${rankClass}">${medal}</span>
          <div class="player-info-col">
            <span class="player-name">${escapeHtml(p.nickname)}</span>
            ${streakHtml}
          </div>
        </div>
        <div class="player-item-right">
          <span class="player-score-tag">${score} pts</span>
        </div>
      </div>
    `;
  }).join('');
}

function updateHostEngineUI(statusText) {
  if (!statusText) {
    statusText = isAutomatedEngineRunning ? 'IN PROGRESS' : (currentGameState === 'PAUSED' ? 'PAUSED' : 'NOT STARTED');
  } else if (statusText === 'NOT STARTED' && currentGameState === 'PAUSED') {
    statusText = 'PAUSED';
  }

  const btnStartAuto = document.getElementById('btn-start-auto');
  const btnPauseAuto = document.getElementById('btn-pause-auto');
  const btnSkip = document.getElementById('btn-skip-question');
  const engineStatus = document.getElementById('host-engine-status');
  const statPlayers = document.getElementById('stat-players-count');
  const statRound = document.getElementById('stat-round');
  const statDiff = document.getElementById('stat-difficulty');
  const statTimer = document.getElementById('stat-active-timer');
  const hostRoomDisplay = document.getElementById('host-room-code-display');
  const hostPlayersRoom = document.getElementById('host-players-room-code');

  const isRunning = (statusText === 'IN PROGRESS');
  const isPaused = (statusText === 'PAUSED');

  if (btnStartAuto) {
    const shouldDisableStart = isRunning || isPaused;
    btnStartAuto.disabled = shouldDisableStart;
    if (shouldDisableStart) {
      btnStartAuto.classList.add('disabled', 'btn-greyed-out');
      btnStartAuto.setAttribute('aria-disabled', 'true');
    } else {
      btnStartAuto.classList.remove('disabled', 'btn-greyed-out');
      btnStartAuto.removeAttribute('aria-disabled');
    }
  }
  if (btnPauseAuto) {
    const btnPauseText = document.getElementById('btn-pause-auto-text');
    btnPauseAuto.disabled = (!isRunning && !isPaused);
    if (isPaused) {
      if (btnPauseText) btnPauseText.textContent = 'Resume';
      btnPauseAuto.classList.add('btn-success');
      btnPauseAuto.classList.remove('btn-warning');
      btnPauseAuto.setAttribute('title', 'Resume Game');
    } else {
      if (btnPauseText) btnPauseText.textContent = 'Pause';
      btnPauseAuto.classList.add('btn-warning');
      btnPauseAuto.classList.remove('btn-success');
      btnPauseAuto.setAttribute('title', 'Pause Game');
    }
  }

  if (statRound) statRound.textContent = currentRound;
  if (statDiff) statDiff.textContent = selectedDifficulty;
  if (statTimer) {
    if (selectedQuestionDuration >= 60) {
      const mins = Math.floor(selectedQuestionDuration / 60);
      const secs = selectedQuestionDuration % 60;
      statTimer.textContent = secs > 0 ? `${mins}m ${secs}s` : `${mins} Min`;
    } else {
      statTimer.textContent = `${selectedQuestionDuration}s`;
    }
  }

  if (hostRoomDisplay) hostRoomDisplay.textContent = currentRoomCode;
  if (hostPlayersRoom) hostPlayersRoom.textContent = currentRoomCode;

  if (engineStatus) {
    if (statusText === 'IN PROGRESS') {
      engineStatus.className = 'engine-badge badge-running';
      engineStatus.textContent = `Game Status: IN PROGRESS (${selectedDifficulty} • ${selectedQuestionDuration}s TIMER)`;
    } else if (statusText === 'PAUSED') {
      engineStatus.className = 'engine-badge badge-idle';
      engineStatus.textContent = `Game Status: PAUSED`;
    } else {
      engineStatus.className = 'engine-badge badge-idle';
      engineStatus.textContent = `Game Status: NOT STARTED`;
    }
  }

  renderHostPlayersRoster();
}

// AUTOMATED GAME LOOP LOGIC
async function runNextAutomatedStep() {
  if (!isAutomatedEngineRunning) return;

  try {
    currentRound = Math.floor(currentQuestionIndex / 10) + 1;
    const questionInRound = (currentQuestionIndex % 10) + 1;

    let activeRoundGenre = 'Auto Select';

    // QUEUE OR AUTO SELECT ROTATION LOGIC
    if (selectedGenreQueue.length > 0) {
      const qIndex = (currentRound - 1) % selectedGenreQueue.length;
      activeRoundGenre = selectedGenreQueue[qIndex];
    } else {
      const autoGenre = shuffledAutoGenres[(currentRound - 1) % shuffledAutoGenres.length];
      activeRoundGenre = autoGenre;
    }

    // CACHE 10 QUESTIONS PER ROUND (Avoids OpenTDB rate limiting & network failures per question)
    if (questionInRound === 1 || !currentRoundQuestions || currentRoundQuestions.length < 10) {
      try {
        currentRoundQuestions = await fetchRealtimeTriviaQuestions(activeRoundGenre, selectedDifficulty, 10);
      } catch (err) {
        console.warn('[Realtime] Failed to fetch round questions, using local:', err);
      }
      if (!currentRoundQuestions || currentRoundQuestions.length === 0) {
        currentRoundQuestions = getLocalQuestions(activeRoundGenre, selectedDifficulty, 10);
      }
    }

    // Safe Question Selection with Guaranteed Fallback
    let question = currentRoundQuestions?.[questionInRound - 1];
    if (!question || !question.options) {
      const fallback = getLocalQuestions(activeRoundGenre, selectedDifficulty, 1);
      question = fallback?.[0];
    }
    if (!question || !question.options) {
      question = {
        id: `q_safe_${Date.now()}_${questionInRound}`,
        category: activeRoundGenre,
        difficulty: selectedDifficulty,
        text: `In the rich history and culture of ${activeRoundGenre}, what quality defines its greatest achievements?`,
        options: {
          A: 'Creative originality and timeless cultural storytelling',
          B: 'A short-lived passing fad forgotten within days',
          C: 'An unverified rumor with no historical foundation',
          D: 'A generic copy lacking any artistic distinction'
        },
        correct: 'A'
      };
    }

    const durationSeconds = selectedQuestionDuration || 20;
    const isManual = hostGamePlayMode === 'Manual';

    if (isManual) {
      timerEndsAtGlobalMs = 0;
      hostTargetEpochMs = 0;
      hostEngineState = 'QUESTION_READING';
    } else {
      timerEndsAtGlobalMs = Date.now() + (durationSeconds * 1000);
      hostTargetEpochMs = timerEndsAtGlobalMs;
      hostEngineState = 'QUESTION_ACTIVE';
      startHostHeartbeatLoop();
    }

    const payload = {
      questionIndex: currentQuestionIndex,
      roundNumber: currentRound,
      questionNumberInRound: questionInRound,
      questionData: question,
      difficulty: selectedDifficulty,
      durationSeconds,
      timerEndsAtMs: timerEndsAtGlobalMs,
      // Flat properties for TV and standard receivers:
      question_index: questionInRound,
      cumulative_question_index: currentQuestionIndex + 1,
      question_number_in_round: questionInRound,
      total_questions: 10,
      total_questions_in_round: 10,
      round_number: currentRound,
      id: question.id,
      question_id: question.id,
      duration_seconds: durationSeconds,
      time_limit_seconds: durationSeconds,
      total_duration: durationSeconds,
      totalTimerDuration: durationSeconds,
      timer_ends_at_epoch_ms: timerEndsAtGlobalMs,
      timerEndsAtMs: timerEndsAtGlobalMs,
      category: question.category || activeRoundGenre,
      genre: question.category || activeRoundGenre,
      question_text: question.text,
      option_a: question.options.A,
      option_b: question.options.B,
      option_c: question.options.C,
      option_d: question.options.D,
      options: question.options,
      correct_option: question.correct,
      game_play_mode: hostGamePlayMode,
      question_phase: isManual ? 'reading' : 'countdown',
      timer_state: isManual ? 'idle' : 'running',
      timestamp: Date.now(),
      sent_at_epoch_ms: Date.now(),
    };

    currentGameState = isManual ? 'QUESTION_READING' : 'QUESTION_ACTIVE';
    broadcastRealtimeEvent('question_start', payload);
    onQuestionStart(payload);
    updateHostManualDock();

    try {
      supabase.from('game_sessions').upsert({
        room_code: currentRoomCode,
        status: isManual ? 'active_reading' : 'question_active',
        current_question_index: currentQuestionIndex + 1,
        current_round: currentRound,
        round_number: currentRound,
        duration_seconds: durationSeconds,
        timer_ends_at: timerEndsAtGlobalMs ? new Date(timerEndsAtGlobalMs).toISOString() : null,
        game_play_mode: hostGamePlayMode,
        genre: activeRoundGenre,
        question_data: {
          id: question.id,
          question_id: question.id,
          category: question.category || activeRoundGenre,
          genre: question.category || activeRoundGenre,
          difficulty: selectedDifficulty,
          text: question.text,
          question_text: question.text,
          options: question.options,
          correct: question.correct,
          correct_option: question.correct,
          round_number: currentRound,
          roundNumber: currentRound,
          question_number_in_round: questionInRound,
        },
        updated_at: new Date().toISOString(),
      }, { onConflict: 'room_code' }).catch(() => {});
    } catch (_) {}

    clearTimeout(autoEngineTimeout);
    if (!isManual) {
      autoEngineTimeout = setTimeout(() => {
        checkHostEngineTick();
      }, durationSeconds * 1000);
    }
  } catch (loopErr) {
    console.error('[Automated Engine] Recovering from step error:', loopErr);
    clearTimeout(autoEngineTimeout);
    const fallbackDuration = Number(selectedQuestionDuration) || 20;
    autoEngineTimeout = setTimeout(() => {
      if (isAutomatedEngineRunning) {
        checkHostEngineTick();
      }
    }, fallbackDuration * 1000);
  }
}

function handleHostQuestionTimeout(question, currentRound, questionInRound) {
  if (!isAutomatedEngineRunning || hostEngineState !== 'QUESTION_ACTIVE') return;

  const reviewDurationMs = 15000; // Synchronized 15-second review: result reveal + dedicated countdown
  const hostReviewDurationMs = (questionInRound === 10) ? 20000 : reviewDurationMs; // 20 seconds for question 10
  hostTargetEpochMs = Date.now() + hostReviewDurationMs;

  const correctOpt = (question.correct || '').toUpperCase().trim();

  // Host reliably grades all answers submitted for this question so leaderboard always updates
  let anyScoreChanged = false;
  Object.values(currentQuestionAnswers).forEach(ans => {
    if (ans && ans.choice === correctOpt && ans.nickname && !ans.graded) {
      ans.graded = true;
      const pIdx = playersLeaderboard.findIndex(p => p.nickname.toLowerCase() === ans.nickname.toLowerCase());
      if (pIdx >= 0) {
        const currentScore = Number(playersLeaderboard[pIdx].score || 0);
        if (currentScore <= (ans.scoreAtSubmission || 0)) {
          playersLeaderboard[pIdx].score = (ans.scoreAtSubmission || 0) + 10;
          playersLeaderboard[pIdx].cumulative_score = playersLeaderboard[pIdx].score;
          anyScoreChanged = true;
        }
      } else {
        playersLeaderboard.push({
          id: ans.nickname,
          player_uid: ans.nickname,
          room_code: currentRoomCode,
          nickname: ans.nickname,
          score: 10,
          cumulative_score: 10,
          is_connected: true
        });
        anyScoreChanged = true;
      }
    }
  });

  if (anyScoreChanged) {
    playersLeaderboard.sort((a, b) => (b.cumulative_score || b.score || 0) - (a.cumulative_score || a.score || 0));
    renderLeaderboard();
  }

  const expiredPayload = {
    correctOption: question.correct,
    correctText: `${question.correct}) ${question.options[question.correct]}`,
    next_question_starts_at_epoch_ms: hostTargetEpochMs,
    nextQuestionStartsAtEpochMs: hostTargetEpochMs,
    questionIndex: currentQuestionIndex,
    roundNumber: currentRound,
    questionNumberInRound: questionInRound,
    question_id: question.id,
    id: question.id,
    timestamp: Date.now(),
    game_play_mode: hostGamePlayMode,
    is_last_question_of_round: (questionInRound === 10),
  };

  currentGameState = 'QUESTION_REVIEW';
  hostEngineState = 'QUESTION_REVIEW';

  broadcastRealtimeEvent('timer_expired', expiredPayload);
  onTimerExpired(expiredPayload);
  updateHostManualDock();

  if (anyScoreChanged) {
    broadcastRealtimeEvent('leaderboard_updated', {
      players: playersLeaderboard,
      leaderboard: playersLeaderboard,
      room_code: currentRoomCode
    });
    // Persist scores to Supabase DB in background
    playersLeaderboard.forEach(p => {
      try {
        supabase.from('players').upsert({
          room_code: currentRoomCode.toUpperCase(),
          nickname: p.nickname,
          player_uid: p.player_uid || p.nickname,
          cumulative_score: Number(p.cumulative_score ?? p.score ?? 0),
          is_connected: true
        }, { onConflict: 'room_code, nickname' });
      } catch (_) {}
    });
  }

  clearTimeout(autoEngineTimeout);
  if (hostGamePlayMode === 'Auto') {
    autoEngineTimeout = setTimeout(() => {
      checkHostEngineTick();
    }, hostReviewDurationMs);
  }
}

function handleHostAdvanceAfterReview(questionInRound, currentRound) {
  if (!isAutomatedEngineRunning || hostEngineState !== 'QUESTION_REVIEW') return;
  hostEngineState = 'TRANSITIONING';
  hostTargetEpochMs = 0;
  clearTimeout(autoEngineTimeout);
  currentQuestionIndex++;

  if (questionInRound === 10) {
    currentGameState = 'ROUND_SUMMARY';
    hostEngineState = 'ROUND_SUMMARY';
    const interRoundSecs = Math.max(5, selectedInterRoundDuration || 120);
    hostTargetEpochMs = Date.now() + (interRoundSecs * 1000);
    
    playersLeaderboard.sort((a, b) => (Number(b.score ?? b.cumulative_score ?? 0)) - (Number(a.score ?? a.cumulative_score ?? 0)));
    const validPlayers = playersLeaderboard.filter(p => p && p.nickname && !isFictitiousPlayer(p.nickname));

    let top3 = [];
    let winnerPayload = {
      roundNumber: currentRound,
      winnerName: '',
      winnerScore: 0,
      top3Winners: [],
      delaySeconds: interRoundSecs
    };

    if (validPlayers.length > 0) {
      const roundWinner = validPlayers[0];
      const currentWinnerScore = Number(roundWinner.score ?? roundWinner.cumulative_score ?? 0);
      if (currentWinnerScore > 0) {
        roundWinner.score = currentWinnerScore + 20;
        roundWinner.cumulative_score = roundWinner.score;
        renderLeaderboard();
        broadcastRealtimeEvent('leaderboard_updated', {
          players: playersLeaderboard,
        });
        broadcastRealtimeEvent('player_score_updated', {
          room_code: currentRoomCode,
          nickname: roundWinner.nickname,
          score: roundWinner.score,
          cumulative_score: roundWinner.score,
          points_earned: 20,
        });

        if (currentPlayer && currentPlayer.nickname && currentPlayer.nickname.toLowerCase() === roundWinner.nickname.toLowerCase()) {
          currentPlayer.score = roundWinner.score;
          const scoreVal = document.getElementById('player-score-val');
          if (scoreVal) scoreVal.textContent = currentPlayer.score;
        }
      }

      top3 = validPlayers.slice(0, 3);
      winnerPayload = {
        roundNumber: currentRound,
        winnerName: roundWinner.nickname,
        winnerScore: Number(roundWinner.score ?? roundWinner.cumulative_score ?? 0),
        top3Winners: top3,
        delaySeconds: interRoundSecs,
        starts_at_epoch_ms: hostTargetEpochMs,
        next_round_starts_at_epoch_ms: hostTargetEpochMs,
      };
    } else {
      winnerPayload.starts_at_epoch_ms = hostTargetEpochMs;
      winnerPayload.next_round_starts_at_epoch_ms = hostTargetEpochMs;
    }

    const nextRound = currentRound + 1;
    broadcastRealtimeEvent('round_completed', {
      round_number: currentRound,
      roundNumber: currentRound,
      completed_round: currentRound,
      next_round: nextRound,
      nextRound: nextRound,
      top3_winners: top3,
      top_3_winners: top3,
      top3Winners: top3,
      delaySeconds: interRoundSecs,
      delay_seconds: interRoundSecs,
      duration_seconds: interRoundSecs,
      starts_at_epoch_ms: hostTargetEpochMs,
      next_round_starts_at_epoch_ms: hostTargetEpochMs,
    });
    onRoundWinner(winnerPayload);
    updateHostManualDock();

    try {
      const summaryPayload = {
        room_code: currentRoomCode,
        status: 'round_summary',
        current_round: currentRound,
        round_number: currentRound,
        current_question_index: currentQuestionIndex,
        question_data: null,
        current_question_data: null,
        duration_seconds: interRoundSecs,
        timer_ends_at: new Date(hostTargetEpochMs).toISOString(),
        starts_at: new Date(hostTargetEpochMs).toISOString(),
        updated_at: new Date().toISOString(),
      };
      supabase.from('game_sessions').upsert(summaryPayload, { onConflict: 'room_code' }).catch(() => {});
      if (currentRoomCode.toUpperCase() !== 'TRIV') {
        supabase.from('game_sessions').upsert({ ...summaryPayload, room_code: 'TRIV' }, { onConflict: 'room_code' }).catch(() => {});
      }
    } catch (_) {}

    if (hostGamePlayMode === 'Auto') {
      autoEngineTimeout = setTimeout(() => {
        checkHostEngineTick();
      }, interRoundSecs * 1000);
    }
  } else {
    runNextAutomatedStep();
  }
}

function updateHostManualDock() {
  const manualBanner = document.getElementById('host-manual-dock-banner');
  const btnManual = document.getElementById('btn-manual-primary');
  if (!manualBanner || !btnManual) return;

  if (hostGamePlayMode !== 'Manual' || !isAutomatedEngineRunning || currentGameState === 'PAUSED') {
    manualBanner.classList.add('hidden');
    return;
  }

  manualBanner.classList.remove('hidden');

  if (hostEngineState === 'QUESTION_READING') {
    btnManual.style.background = 'var(--neon-green)';
    btnManual.style.color = '#000';
    btnManual.innerHTML = '⏱️ START QUESTION TIMER';
    btnManual.onclick = () => {
      startManualQuestionCountdown();
    };
  } else if (hostEngineState === 'QUESTION_ACTIVE') {
    btnManual.style.background = '#ffd600';
    btnManual.style.color = '#000';
    btnManual.innerHTML = '⏭️ END TIMER EARLY (REVEAL ANSWER)';
    btnManual.onclick = () => {
      expireManualQuestionEarly();
    };
  } else if (hostEngineState === 'QUESTION_REVIEW') {
    btnManual.style.background = 'var(--neon-cyan)';
    btnManual.style.color = '#000';
    btnManual.innerHTML = '⏭️ NEXT QUESTION';
    btnManual.onclick = () => {
      advanceManualNextQuestion();
    };
  } else if (hostEngineState === 'ROUND_SUMMARY') {
    btnManual.style.background = 'var(--neon-purple)';
    btnManual.style.color = '#fff';
    btnManual.innerHTML = `🚀 START ROUND ${Math.floor(currentQuestionIndex / 10) + 1}`;
    btnManual.onclick = () => {
      handleHostAdvanceAfterRoundSummary();
    };
  } else {
    manualBanner.classList.add('hidden');
  }
}

function startManualQuestionCountdown() {
  if (!isAutomatedEngineRunning || hostEngineState !== 'QUESTION_READING') return;
  const durationSeconds = selectedQuestionDuration || 20;
  timerEndsAtGlobalMs = Date.now() + (durationSeconds * 1000);
  hostTargetEpochMs = timerEndsAtGlobalMs;
  hostEngineState = 'QUESTION_ACTIVE';
  currentGameState = 'QUESTION_ACTIVE';

  broadcastRealtimeEvent('manual_timer_started', {
    room_code: currentRoomCode,
    timer_ends_at_epoch_ms: timerEndsAtGlobalMs,
    timerEndsAtMs: timerEndsAtGlobalMs,
    duration_seconds: durationSeconds,
    time_limit_seconds: durationSeconds,
    total_duration: durationSeconds,
    totalTimerDuration: durationSeconds,
    question_index: (currentQuestionIndex % 10) + 1,
    round_number: currentRound,
    timestamp: Date.now(),
    sent_at_epoch_ms: Date.now(),
  });

  startCountdown(durationSeconds);
  startHostHeartbeatLoop();
  updateHostManualDock();

  try {
    supabase.from('game_sessions').upsert({
      room_code: currentRoomCode,
      status: 'question_active',
      timer_ends_at: new Date(timerEndsAtGlobalMs).toISOString(),
      duration_seconds: durationSeconds,
      updated_at: new Date().toISOString(),
    }, { onConflict: 'room_code' }).catch(() => {});
  } catch (_) {}

  clearTimeout(autoEngineTimeout);
  autoEngineTimeout = setTimeout(() => {
    checkHostEngineTick();
  }, durationSeconds * 1000);
}

function expireManualQuestionEarly() {
  if (!isAutomatedEngineRunning || hostEngineState !== 'QUESTION_ACTIVE') return;
  clearInterval(countdownInterval);
  clearTimeout(autoEngineTimeout);
  const questionInRound = (currentQuestionIndex % 10) + 1;
  let question = currentRoundQuestions?.[questionInRound - 1] || currentQuestionData;
  if (!question || !question.options) {
    question = currentQuestionData || { correct: 'A', options: { A: '' } };
  }
  handleHostQuestionTimeout(question, currentRound, questionInRound);
}

function advanceManualNextQuestion() {
  if (!isAutomatedEngineRunning || hostEngineState !== 'QUESTION_REVIEW') return;
  clearTimeout(autoEngineTimeout);
  const questionInRound = (currentQuestionIndex % 10) + 1;
  handleHostAdvanceAfterReview(questionInRound, currentRound);
}

function handleHostAdvanceAfterRoundSummary() {
  if (!isAutomatedEngineRunning || hostEngineState !== 'ROUND_SUMMARY') return;
  currentRoundQuestions = [];
  currentQuestionData = null;
  playerChoiceSubmitted = null;
  isCurrentQuestionScored = false;

  const nextRound = Math.floor(currentQuestionIndex / 10) + 1;
  currentRound = nextRound;
  let nextGenre = 'General Trivia';
  if (selectedGenreQueue.length > 0) {
    const qIndex = (nextRound - 1) % selectedGenreQueue.length;
    nextGenre = selectedGenreQueue[qIndex];
  } else if (shuffledAutoGenres && shuffledAutoGenres.length > 0) {
    nextGenre = shuffledAutoGenres[(nextRound - 1) % shuffledAutoGenres.length];
  }

  // Pre-game countdown for the new round and genre
  hostEngineState = 'PRE_GAME';
  const preGameSecs = 10;
  hostTargetEpochMs = Date.now() + (preGameSecs * 1000);

  broadcastRealtimeEvent('pre_game_countdown', {
    countdown_seconds: preGameSecs,
    genre: nextGenre,
    current_genre: nextGenre,
    category: nextGenre,
    round_number: nextRound,
    starts_at_epoch_ms: hostTargetEpochMs,
  });

  handleIncomingPreGameCountdown({
    countdown_seconds: preGameSecs,
    genre: nextGenre,
    round_number: nextRound,
    starts_at_epoch_ms: hostTargetEpochMs,
  });

  try {
    supabase.from('game_sessions').upsert({
      room_code: currentRoomCode,
      status: 'pre_game_countdown',
      current_question_index: currentQuestionIndex + 1,
      current_round: nextRound,
      starts_at: hostTargetEpochMs,
      updated_at: new Date().toISOString(),
    }, { onConflict: 'room_code' }).catch(() => {});
  } catch (_) {}

  clearTimeout(autoEngineTimeout);
  autoEngineTimeout = setTimeout(() => {
    checkHostEngineTick();
  }, preGameSecs * 1000);
}

function checkHostEngineTick() {
  if (!isAutomatedEngineRunning || hostTargetEpochMs <= 0) return;
  const now = Date.now();
  if (now >= hostTargetEpochMs) {
    if (hostEngineState === 'PRE_GAME') {
      hostTargetEpochMs = 0;
      hostEngineState = 'QUESTION_ACTIVE';
      runNextAutomatedStep();
    } else if (hostEngineState === 'QUESTION_ACTIVE') {
      currentRound = Math.max(currentRound, Math.floor(currentQuestionIndex / 10) + 1);
      const questionInRound = (currentQuestionIndex % 10) + 1;
      let question = currentRoundQuestions?.[questionInRound - 1];
      if (!question || !question.options) {
        question = currentQuestionData || { correct: 'A', options: { A: '' } };
      }
      handleHostQuestionTimeout(question, currentRound, questionInRound);
    } else if (hostEngineState === 'QUESTION_REVIEW') {
      currentRound = Math.max(currentRound, Math.floor(currentQuestionIndex / 10) + 1);
      const questionInRound = (currentQuestionIndex % 10) + 1;
      handleHostAdvanceAfterReview(questionInRound, currentRound);
    } else if (hostEngineState === 'ROUND_SUMMARY') {
      handleHostAdvanceAfterRoundSummary();
    }
  }
}

// SIMULATE BACKGROUND PLAYERS (DISABLED - Only real connected players submit answers)
function triggerMockPlayersSimulation(questionData, durationSeconds) {
  clearMockPlayerTimeouts();
}

function clearMockPlayerTimeouts() {
  mockPlayerTimeouts.forEach(t => clearTimeout(t));
  mockPlayerTimeouts = [];
}

// 5. QUESTION START HANDLER (STARTS TV & PLAYER COUNTDOWN TIMERS IMMEDIATELY)
function onQuestionStart(payload) {
  if (!payload) return;
  questionStartTimeLocal = Date.now();
  const qObj = payload.questionData || payload.question_data || payload;
  const opts = qObj.options || payload.options || {};
  const optA = payload.option_a || payload.optionA || qObj.option_a || qObj.optionA || opts.A || opts.a || (Array.isArray(opts) ? opts[0] : 'Option A');
  const optB = payload.option_b || payload.optionB || qObj.option_b || qObj.option_b || opts.B || opts.b || (Array.isArray(opts) ? opts[1] : 'Option B');
  const optC = payload.option_c || payload.optionC || qObj.option_c || qObj.option_c || opts.C || opts.c || (Array.isArray(opts) ? opts[2] : 'Option C');
  const optD = payload.option_d || payload.optionD || qObj.option_d || qObj.option_d || opts.D || opts.d || (Array.isArray(opts) ? opts[3] : 'Option D');
  const correct = (qObj.correct || qObj.correct_option || payload.correct_option || payload.correct || 'A').toUpperCase().trim();

  const questionData = {
    id: qObj.id || payload.question_id || payload.id || String(Date.now()),
    category: qObj.category || qObj.genre || payload.category || payload.genre || 'General Knowledge',
    difficulty: payload.difficulty || qObj.difficulty || selectedDifficulty || 'Standard',
    text: decodeHtmlEntities(qObj.text || qObj.question_text || payload.question_text || payload.text || payload.question || ''),
    options: {
      A: decodeHtmlEntities(optA),
      B: decodeHtmlEntities(optB),
      C: decodeHtmlEntities(optC),
      D: decodeHtmlEntities(optD),
    },
    correct: correct,
  };

  const totalDur = payload.totalTimerDuration || payload.total_duration || payload.time_limit_seconds || selectedQuestionDuration || 20;
  totalTimerDuration = Math.max(5, Number(totalDur) || 20);
  const rawDur = payload.durationSeconds || payload.duration_seconds || totalTimerDuration;
  let durationSeconds = Math.max(1, Number(rawDur) || totalTimerDuration);
  if (durationSeconds <= 4 && totalTimerDuration > 4) {
    durationSeconds = totalTimerDuration;
  }
  const roundNumber = Number(payload.roundNumber || payload.round_number || payload.current_round || currentRound || 1);
  const questionNumberInRound = Number(payload.questionNumberInRound || payload.question_number_in_round || ((currentQuestionIndex % 10) + 1));
  const activeDifficulty = payload.difficulty || questionData.difficulty || selectedDifficulty || 'Standard';

  currentQuestionData = questionData;
  playerChoiceSubmitted = null;
  isCurrentQuestionScored = false;
  lastScoredQuestionKey = null;
  currentQuestionAnswers = {};
  if (payload.questionIndex !== undefined || payload.question_index !== undefined) {
    currentQuestionIndex = Number(payload.questionIndex ?? payload.question_index);
  }

  hideResultModal();
  hideWinnerModals();
  hideInterQuestionCountdown();
  clearInterval(preGameCountdownInterval);
  clearInterval(modalCountdownInterval);
  clearInterval(playerReviewInterval);
  clearInterval(winnerCountdownInterval);
  const promoFluctuating = document.getElementById('promo-fluctuating-text') || document.querySelector('.promo-cta-box-centered .fluctuating-text');
  if (promoFluctuating) {
    promoFluctuating.textContent = 'WAITING FOR HOST TO START GAME';
    promoFluctuating.style.color = '';
  }
  const tvAdBanner = document.getElementById('tv-ad-intermission-banner');
  if (tvAdBanner) tvAdBanner.classList.add('hidden');

  const btnTvBack = document.getElementById('btn-tv-back');
  if (btnTvBack) btnTvBack.classList.add('question-hidden');

  const btnPromo = document.getElementById('btn-tv-toggle-promo');
  const btnLive = document.getElementById('btn-tv-toggle-live');
  if (btnLive) btnLive.classList.add('active');
  if (btnPromo) btnPromo.classList.remove('active');

  const tvPromoScreen = document.getElementById('tv-promo-screen');
  const tvAdScreen = document.getElementById('tv-ad-signage-screen');
  const tvLiveGrid = document.getElementById('tv-live-grid');
  if (tvPromoScreen) tvPromoScreen.classList.add('hidden');
  if (tvAdScreen) tvAdScreen.classList.add('hidden');
  stopTvAdSignageRotation();
  if (tvLiveGrid) tvLiveGrid.classList.remove('hidden');

  triggerMockPlayersSimulation(questionData, totalTimerDuration);

  const tvNextQBanner = document.getElementById('tv-next-q-banner');
  if (tvNextQBanner) tvNextQBanner.classList.add('hidden');
  clearInterval(tvNextQCountdownInterval);
  clearInterval(playerReviewInterval);
  const timerLabel = document.querySelector('.timer-text-container .timer-label');
  if (timerLabel) timerLabel.textContent = 'SEC';
  const tvTimerSublabel = document.getElementById('tv-timer-sublabel');
  if (tvTimerSublabel) tvTimerSublabel.classList.add('hidden');

  // Update Host Stats
  const statRound = document.getElementById('stat-round');
  const statQNum = document.getElementById('stat-q-num');
  const statDifficulty = document.getElementById('stat-difficulty');
  const statActiveTimer = document.getElementById('stat-active-timer');
  if (statRound) statRound.textContent = roundNumber || 1;
  if (statQNum) statQNum.textContent = `${questionNumberInRound || 1} / 10`;
  if (statDifficulty) statDifficulty.textContent = activeDifficulty;
  if (statActiveTimer) {
    if (totalTimerDuration >= 60) {
      const mins = Math.floor(totalTimerDuration / 60);
      const secs = totalTimerDuration % 60;
      statActiveTimer.textContent = secs > 0 ? `${mins}m ${secs}s` : `${mins} Min`;
    } else {
      statActiveTimer.textContent = `${totalTimerDuration}s`;
    }
  }

  // Update TV Display Live Stage & Difficulty Badge
  const tvRoundTracker = document.getElementById('tv-round-tracker');
  const tvCategory = document.getElementById('tv-category');
  const tvDiffBadge = document.getElementById('tv-difficulty-badge');
  const tvQuestionText = document.getElementById('tv-question-text');
  const tvOptionsGrid = document.getElementById('tv-options-grid');
  const tvTimerContainer = document.getElementById('tv-timer-container');
  const tvGenreIcon = document.getElementById('tv-genre-icon');

  const categoryName = questionData.category || 'General Knowledge';
  const categoryIcon = genreIconMap[categoryName] || '💡';

  const diffEmojiMap = { Kids: '🧒', Beginner: '🌱', Standard: '🎯', Advanced: '🧠' };
  const diffClassMap = { Kids: 'diff-kids', Beginner: 'diff-beginner', Standard: 'diff-standard', Advanced: 'diff-advanced' };

  if (tvDiffBadge) {
    tvDiffBadge.className = `difficulty-pill ${diffClassMap[activeDifficulty] || 'diff-standard'}`;
    tvDiffBadge.textContent = `${diffEmojiMap[activeDifficulty] || '🎯'} ${activeDifficulty.toUpperCase()}`;
  }

  if (tvGenreIcon) tvGenreIcon.textContent = categoryIcon;
  if (tvRoundTracker) tvRoundTracker.textContent = `ROUND ${roundNumber || 1} • QUESTION ${questionNumberInRound || 1}/10`;
  if (tvCategory) tvCategory.textContent = `${categoryIcon} ${categoryName.toUpperCase()}`;
  const cleanQText = decodeHtmlEntities(questionData.text || '')
      .replace(/\s*\((?:Focus Point|Batch|Formula|Protocol\s*)?#\d+\)/gi, '')
      .replace(/\s*\(#INDEX\)/gi, '')
      .replace(/\s*#\d+\b/g, '')
      .trim();

  if (tvQuestionText) tvQuestionText.textContent = cleanQText;

  // Update Host Mobile Stage Card & Live Answer Key Grid
  const hostStageBadge = document.getElementById('host-stage-badge');
  const hostStageQCounter = document.getElementById('host-stage-q-counter');
  const hostLiveGenrePill = document.getElementById('host-live-genre-pill');
  const hostLiveQText = document.getElementById('host-live-q-text');
  const btnSkip = document.getElementById('btn-skip-question');

  if (hostStageBadge) {
    hostStageBadge.className = 'stage-status-indicator stage-live';
    hostStageBadge.textContent = '🟢 QUESTION LIVE';
  }
  if (hostStageQCounter) {
    hostStageQCounter.textContent = `Question ${questionNumberInRound || 1} of 10 (Round ${roundNumber || 1})`;
  }
  if (hostLiveGenrePill) {
    hostLiveGenrePill.textContent = `${categoryIcon} ${categoryName.toUpperCase()}`;
  }
  if (hostLiveQText) {
    hostLiveQText.textContent = cleanQText;
  }
  isAutomatedEngineRunning = true;
  updateHostEngineUI('IN PROGRESS');

  // Populate Host Answer Key Grid & Highlight Correct Option
  const hostAnswerGrid = document.getElementById('host-live-answer-grid');
  if (hostAnswerGrid) hostAnswerGrid.classList.remove('hidden');

  const correctOptLetter = (questionData.correct || 'A').toUpperCase().trim();
  ['A', 'B', 'C', 'D'].forEach(letter => {
    const card = document.getElementById(`host-ans-${letter}`);
    const txt = document.getElementById(`host-ans-text-${letter}`);
    if (txt) txt.textContent = questionData.options?.[letter] || `Option ${letter}`;
    if (card) {
      card.classList.toggle('correct-key', letter === correctOptLetter);
    }
  });

  if (tvOptionsGrid) {
    tvOptionsGrid.classList.remove('hidden');
    document.querySelectorAll('.option-tile').forEach(t => {
      t.classList.remove('reveal-correct');
      t.querySelectorAll('.correct-badge-icon').forEach(b => b.remove());
    });
    document.getElementById('opt-a-text').textContent = questionData.options.A;
    document.getElementById('opt-b-text').textContent = questionData.options.B;
    document.getElementById('opt-c-text').textContent = questionData.options.C;
    document.getElementById('opt-d-text').textContent = questionData.options.D;
  }

  // UNHIDE & START TV COUNTDOWN TIMER (If running; in Manual Mode hold at READY)
  const isIdle = payload.timer_state === 'idle' || payload.question_phase === 'reading';
  if (tvTimerContainer) tvTimerContainer.classList.remove('hidden');

  if (isIdle) {
    clearInterval(countdownInterval);
    remainingTimerSeconds = totalTimerDuration;
    const tvTimerVal = document.getElementById('tv-timer-val');
    const timerProgress = document.getElementById('timer-progress');
    const playerTimerVal = document.getElementById('player-timer-val');
    if (tvTimerVal) tvTimerVal.textContent = 'READY';
    if (playerTimerVal) playerTimerVal.textContent = totalTimerDuration;
    if (timerProgress) {
      timerProgress.style.strokeDashoffset = '0';
      timerProgress.style.stroke = 'var(--neon-green)';
    }
    const hostStageBadge = document.getElementById('host-stage-badge');
    if (hostStageBadge) {
      hostStageBadge.className = 'stage-status-indicator stage-live';
      hostStageBadge.textContent = '🎤 HOST READING QUESTION';
    }
  } else {
    startCountdown(durationSeconds);
  }
  // Silent countdown: do not play sound until last 5 seconds (playSound('question_start') omitted during countdown)

  // Reset player answer choice state and dismiss previous result modal for new question
  playerChoiceSubmitted = null;
  isCurrentQuestionScored = false;
  hideResultModal();
  hideWinnerModals();
  hideInterQuestionCountdown();

  // Update Player Phone Display & Difficulty Pill
  try {
    const playerDispRoom = document.getElementById('player-disp-room');
    const playerCategoryPill = document.getElementById('player-category-pill');
    const playerDiffPill = document.getElementById('player-difficulty-pill');
    const playerQuestionText = document.getElementById('player-question-text');
    const playerStatusBadge = document.getElementById('player-status-badge');
    const answerBtns = document.querySelectorAll('.btn-answer');

    updatePlayerHeaderCard(roundNumber || currentRound || 1, questionNumberInRound || 1);
    if (playerCategoryPill) playerCategoryPill.textContent = `${categoryIcon} ${categoryName.toUpperCase()}`;
    if (playerDiffPill) {
      playerDiffPill.className = `difficulty-pill-sm ${diffClassMap[activeDifficulty] || 'diff-standard'}`;
      playerDiffPill.textContent = `${diffEmojiMap[activeDifficulty] || '🎯'} ${activeDifficulty.toUpperCase()}`;
    }
    if (playerQuestionText) playerQuestionText.textContent = cleanQText;

    const pOptA = document.getElementById('p-opt-a');
    if (pOptA) pOptA.textContent = decodeHtmlEntities(questionData.options.A);
    const pOptB = document.getElementById('p-opt-b');
    if (pOptB) pOptB.textContent = decodeHtmlEntities(questionData.options.B);
    const pOptC = document.getElementById('p-opt-c');
    if (pOptC) pOptC.textContent = decodeHtmlEntities(questionData.options.C);
    const pOptD = document.getElementById('p-opt-d');
    if (pOptD) pOptD.textContent = decodeHtmlEntities(questionData.options.D);

    if (playerStatusBadge) {
      if (isIdle) {
        playerStatusBadge.className = 'status-badge status-active';
        playerStatusBadge.innerHTML = `<span id="status-icon">🎤</span> HOST READING QUESTION`;
      } else {
        playerStatusBadge.className = 'status-badge status-active';
        playerStatusBadge.innerHTML = `<span id="status-icon">⏱️</span> UNLOCKED`;
      }
    }

    answerBtns.forEach(btn => {
      btn.disabled = false;
      btn.classList.remove('selected', 'unselected', 'review-correct', 'review-wrong');
      const existingBadge = btn.querySelector('.player-correct-badge');
      if (existingBadge) existingBadge.remove();
    });
  } catch (playerErr) {
    console.warn('[onQuestionStart] Player display update non-fatal error:', playerErr);
  }
}

function startCountdown(seconds) {
  clearInterval(countdownInterval);
  const validSeconds = Math.max(1, Number(seconds) || Number(totalTimerDuration) || Number(selectedQuestionDuration) || 20);
  totalTimerDuration = validSeconds;
  const now = Date.now();
  if (!timerEndsAtGlobalMs || timerEndsAtGlobalMs <= now || ((timerEndsAtGlobalMs - now) <= 4000 && validSeconds > 4)) {
    timerEndsAtGlobalMs = now + (validSeconds * 1000);
  }
  remainingTimerSeconds = Math.max(0, Math.ceil((timerEndsAtGlobalMs - now) / 1000));
  updateTimerUI();

  let lastTickedSecond = -1;
  countdownInterval = setInterval(() => {
    if (timerEndsAtGlobalMs > 0) {
      remainingTimerSeconds = Math.max(0, Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000));
    } else {
      remainingTimerSeconds--;
    }
    updateTimerUI();

    if (remainingTimerSeconds <= 5 && remainingTimerSeconds > 0 && remainingTimerSeconds !== lastTickedSecond) {
      lastTickedSecond = remainingTimerSeconds;
      playSound('tick', remainingTimerSeconds); // playSound('tick')
    }

    if (remainingTimerSeconds <= 0) {
      clearInterval(countdownInterval);
      playSound('buzz');
      // Autonomous fallback: if timer expired and still in QUESTION_ACTIVE,
      // reveal answer locally and prepare to sync if host was delayed!
      if (currentGameState === 'QUESTION_ACTIVE') {
        currentGameState = 'QUESTION_REVIEW';
        const targetEpoch = Date.now() + 15000;
        onTimerExpired({
          correctOption: currentQuestionData?.correct,
          next_question_starts_at_epoch_ms: targetEpoch,
          nextQuestionStartsAtEpochMs: targetEpoch,
          game_play_mode: 'Auto',
        });
        setTimeout(() => {
          if (currentGameState === 'QUESTION_REVIEW') {
            broadcastRealtimeEvent('request_state_sync', { room_code: currentRoomCode });
          }
        }, 15000);
      }
    }
  }, 500);
}

function updateTimerUI() {
  const currentSecs = Math.max(0, remainingTimerSeconds);

  const tvTimerVal = document.getElementById('tv-timer-val');
  const timerProgress = document.getElementById('timer-progress');
  if (tvTimerVal) tvTimerVal.textContent = currentSecs;

  const playerTimerVal = document.getElementById('player-timer-val');
  if (playerTimerVal) playerTimerVal.textContent = currentSecs;

  // Update Host Live Stage Progress Bar & Timer Number
  const hostTimerFill = document.getElementById('host-timer-progress-fill');
  const hostTimerSecs = document.getElementById('host-live-timer-secs');
  if (hostTimerSecs) hostTimerSecs.textContent = `${currentSecs}s`;
  if (hostTimerFill) {
    const maxDur = totalTimerDuration > 0 ? totalTimerDuration : 20;
    const pct = Math.max(0, Math.min(100, (currentSecs / maxDur) * 100));
    hostTimerFill.style.width = `${pct}%`;
    if (currentSecs <= 5) {
      hostTimerFill.style.background = '#ff007a';
    } else if (currentSecs <= 10) {
      hostTimerFill.style.background = '#ffd600';
    } else {
      hostTimerFill.style.background = 'linear-gradient(90deg, #00e5ff, #00ff87)';
    }
  }

  if (timerProgress) {
    const ratio = currentSecs / totalTimerDuration;
    const offset = 264 - (ratio * 264);
    timerProgress.style.strokeDashoffset = offset;
    
    if (currentSecs <= 5) {
      timerProgress.style.stroke = '#ff007a';
    } else if (currentSecs <= 10) {
      timerProgress.style.stroke = '#ffd600';
    } else {
      timerProgress.style.stroke = '#00e5ff';
    }
  }
}

let playerReviewInterval = null;

function startPlayerReviewCountdown(seconds, targetEpochMs, isLastQ = false) {
  clearInterval(playerReviewInterval);
  const targetEpoch = targetEpochMs || (Date.now() + (seconds * 1000));

  const updateBadge = () => {
    const rem = Math.max(0, Math.ceil((targetEpoch - Date.now()) / 1000));
    const playerStatusBadge = document.getElementById('player-status-badge');
    if (playerStatusBadge) {
      if (rem > 0) {
        playerStatusBadge.className = 'status-badge status-active';
        playerStatusBadge.innerHTML = isLastQ
          ? `<span id="status-icon">⏱️</span> <span id="status-text">ROUND RESULTS IN ${rem}s...</span>`
          : `<span id="status-icon">⏳</span> <span id="status-text">NEXT QUESTION IN ${rem}s...</span>`;
      } else {
        playerStatusBadge.innerHTML = isLastQ
          ? `<span id="status-icon">🏆</span> <span id="status-text">CALCULATING WINNERS...</span>`
          : `<span id="status-icon">🚀</span> <span id="status-text">PREPARING NEXT QUESTION...</span>`;
      }
    }
    return rem;
  };

  const initialRem = updateBadge();
  if (initialRem > 0) {
    playerReviewInterval = setInterval(() => {
      const rem = updateBadge();
      if (rem <= 0) {
        clearInterval(playerReviewInterval);
        hideResultModal();
        if (typeof triggerActiveSessionSync === 'function') {
          triggerActiveSessionSync();
        }
        broadcastRealtimeEvent('request_state_sync', { room_code: currentRoomCode });
      }
    }, 500);
  }
}

// 6. TIMER EXPIRED -> HIGHLIGHT CORRECT OPTION TILE ON TV & START NEXT QUESTION COUNTDOWN TIMER ON TV
function onTimerExpired(payload) {
  const rawCorrect = payload?.correct_option || payload?.correctOption || payload?.correct || currentQuestionData?.correct || '';
  const correctOpt = rawCorrect.toUpperCase().trim();
  const correctTextStr = payload?.correctText || `${correctOpt}) ${currentQuestionData?.options?.[correctOpt] || ''}`;

  const btnTvBack = document.getElementById('btn-tv-back');
  if (btnTvBack) btnTvBack.classList.remove('question-hidden');

  clearMockPlayerTimeouts();

  const playerStatusBadge = document.getElementById('player-status-badge');
  const answerBtns = document.querySelectorAll('.btn-answer');

  const curQ = payload?.questionNumberInRound || payload?.question_number_in_round || ((currentQuestionIndex % 10) + 1);
  const curRound = payload?.roundNumber || payload?.round_number || currentRound;
  updatePlayerHeaderCard(curRound, curQ, 'Review');

  const isLastQ = (curQ === 10);
  const defaultReviewMs = isLastQ ? 20000 : 15000;

  // Calculate review seconds remaining for next question / round results countdown (20s for Q10, 15s for Q1-9)
  let nextEpoch = payload?.next_question_starts_at_epoch_ms || 
                  payload?.nextQuestionStartsAtEpochMs;
  if (typeof nextEpoch === 'string') {
    const p = Date.parse(nextEpoch);
    nextEpoch = !isNaN(p) ? p : Number(nextEpoch);
  } else if (nextEpoch) {
    nextEpoch = Number(nextEpoch);
  }
  const now = Date.now();
  if (!nextEpoch || isNaN(nextEpoch) || nextEpoch <= now) {
    nextEpoch = now + 15000;
    if (isLastQ) nextEpoch = now + 20000;
  }
  const reviewSeconds = Math.max(0, Math.ceil((nextEpoch - now) / 1000));

  // Update Host Mobile Stage Card for Review Phase
  const hostStageBadge = document.getElementById('host-stage-badge');
  const hostStageQCounter = document.getElementById('host-stage-q-counter');
  const hostTimerSecs = document.getElementById('host-live-timer-secs');
  const btnSkip = document.getElementById('btn-skip-question');

  if (hostStageBadge) {
    hostStageBadge.className = 'stage-status-indicator stage-review';
    hostStageBadge.textContent = '🔵 QUESTION REVIEW';
  }
  if (hostStageQCounter) {
    hostStageQCounter.textContent = isLastQ
      ? `Revealing Correct Answer (Round Results in ${reviewSeconds}s)`
      : `Reviewing Answer (Next Question in ${reviewSeconds}s)`;
  }
  if (hostTimerSecs) {
    hostTimerSecs.textContent = `${reviewSeconds}s`;
  }

  startPlayerReviewCountdown(reviewSeconds, nextEpoch, isLastQ);

  answerBtns.forEach(btn => {
    btn.disabled = true;
    const choice = (btn.dataset.choice || '').toUpperCase();
    const existingBadge = btn.querySelector('.player-correct-badge');
    if (existingBadge) existingBadge.remove();

    if (choice === correctOpt) {
      btn.classList.add('review-correct');
      btn.classList.remove('unselected');
      const badge = document.createElement('span');
      badge.className = 'player-correct-badge';
      badge.innerHTML = '✅ CORRECT';
      btn.appendChild(badge);
    } else if (btn.classList.contains('selected')) {
      btn.classList.add('review-wrong');
    } else {
      btn.classList.add('unselected');
    }
  });

  if (correctOpt) {
    const correctTile = document.getElementById(`tile-${correctOpt.toLowerCase()}`);
    if (correctTile) {
      correctTile.classList.add('reveal-correct');
      if (!correctTile.querySelector('.correct-badge-icon')) {
        const badgeSpan = document.createElement('span');
        badgeSpan.className = 'correct-badge-icon';
        badgeSpan.innerHTML = '✅ CORRECT';
        correctTile.appendChild(badgeSpan);
      }
    }
  }

  const tvNextQBanner = document.getElementById('tv-next-q-banner');
  const tvNextQVal = document.getElementById('tv-next-q-timer-val');
  const tvTimerVal = document.getElementById('tv-timer-val');
  const tvTimerContainer = document.getElementById('tv-timer-container');
  const timerLabel = document.querySelector('.timer-text-container .timer-label');
  const timerProgress = document.getElementById('timer-progress');
  const tvTimerSublabel = document.getElementById('tv-timer-sublabel');

  if (tvTimerContainer) {
    tvTimerContainer.classList.remove('hidden');
    if (timerLabel) timerLabel.textContent = '';
    if (tvTimerSublabel) {
      tvTimerSublabel.textContent = isLastQ ? 'Round Results' : 'Next question';
      tvTimerSublabel.classList.remove('hidden');
    }
  }

  const totalReviewDuration = isLastQ ? 20.0 : 15.0;

  if (tvNextQBanner) {
    tvNextQBanner.innerHTML = isLastQ
      ? `⏱️ ROUND RESULTS IN <strong id="tv-next-q-timer-val">${reviewSeconds}</strong> SECONDS`
      : `⏳ NEXT QUESTION IN <strong id="tv-next-q-timer-val">${reviewSeconds}</strong> SECONDS`;
    tvNextQBanner.classList.remove('hidden');
  }

  const updateTvCountdown = () => {
    const remNextQSecs = Math.max(0, Math.ceil((nextEpoch - Date.now()) / 1000));
    const activeTvVal = document.getElementById('tv-next-q-timer-val');
    if (activeTvVal) activeTvVal.textContent = remNextQSecs;
    if (tvTimerVal) tvTimerVal.textContent = remNextQSecs;
    if (timerProgress) {
      const ratio = remNextQSecs / totalReviewDuration;
      const offset = 264 - (ratio * 264);
      timerProgress.style.strokeDashoffset = offset;
      timerProgress.style.stroke = '#00e5ff';
    }
    if (remNextQSecs <= 0) {
      clearInterval(tvNextQCountdownInterval);
      if (tvNextQBanner) tvNextQBanner.classList.add('hidden');
    }
    return remNextQSecs;
  };

  updateTvCountdown();
  clearInterval(tvNextQCountdownInterval);
  tvNextQCountdownInterval = setInterval(updateTvCountdown, 500);

  // ACCURATE SCORING: Evaluate answer ONLY once when timer expires
  const qIdentifier = (currentQuestionData?.id || currentQuestionData?.text || `r${currentRound}_q${currentQuestionIndex}`);
  
  if (lastScoredQuestionKey === qIdentifier && isCurrentQuestionScored) {
    // Already evaluated and scored for this exact question; do not flip result or overwrite modal
    return;
  }

  const isCorrect = Boolean(playerChoiceSubmitted && correctOpt && playerChoiceSubmitted.toUpperCase() === correctOpt);

  if (!isCurrentQuestionScored) {
    isCurrentQuestionScored = true;
    lastScoredQuestionKey = qIdentifier;

    const activeView = document.body.getAttribute('data-view') || 'tv';
    if (activeView === 'tv') {
      // TV Display reveals the correct answer to the room with celebratory chime
      playSound('correct');
    } else {
      if (isCorrect) {
        playSound('correct');
      } else if (playerChoiceSubmitted) {
        playSound('wrong');
      } else {
        playSound('buzz');
      }
    }

    if (isCorrect && currentPlayer) {
      currentPlayer.streak = (currentPlayer.streak || 0) + 1;
      const pointsEarned = 10;
      const targetPlayer = playersLeaderboard.find(p => p.nickname.toLowerCase() === currentPlayer.nickname.toLowerCase());
      if (targetPlayer) {
        const lbScore = Number(targetPlayer.cumulative_score ?? targetPlayer.score ?? 0);
        if (lbScore > Number(currentPlayer.score || 0)) {
          currentPlayer.score = lbScore;
        }
      }
      currentPlayer.score += pointsEarned;
      const scoreVal = document.getElementById('player-score-val');
      if (scoreVal) scoreVal.textContent = currentPlayer.score;

      if (targetPlayer) {
        targetPlayer.score = currentPlayer.score;
        targetPlayer.cumulative_score = currentPlayer.score;
        targetPlayer.streak = currentPlayer.streak;
      } else {
        playersLeaderboard.push({
          nickname: currentPlayer.nickname,
          score: currentPlayer.score,
          cumulative_score: currentPlayer.score,
          streak: currentPlayer.streak
        });
      }
      renderLeaderboard();
      broadcastRealtimeEvent('leaderboard_updated', {
        players: playersLeaderboard,
        leaderboard: playersLeaderboard,
        room_code: currentRoomCode,
      });
      broadcastRealtimeEvent('player_score_updated', {
        nickname: currentPlayer.nickname,
        score: currentPlayer.score,
        cumulative_score: currentPlayer.score,
        points_earned: pointsEarned,
        room_code: currentRoomCode,
      });

      // Also persist directly to Supabase DB so score is preserved
      try {
        supabase.from('players').upsert({
          room_code: currentRoomCode.toUpperCase(),
          nickname: currentPlayer.nickname,
          player_uid: currentPlayer.nickname,
          cumulative_score: currentPlayer.score,
          is_connected: true
        }, { onConflict: 'room_code, nickname' });
      } catch (_) {}

      const randomQuote = getRandomItem(funnyCorrectQuotes);
      showResultModal(true, `+${pointsEarned} PTS`, correctTextStr, randomQuote, reviewSeconds, nextEpoch, isLastQ);
      confetti({ particleCount: 60, spread: 80, origin: { y: 0.6 } });
    } else {
      if (currentPlayer) {
        currentPlayer.streak = 0;
      }
      const randomQuote = getRandomItem(funnyWrongQuotes);
      showResultModal(false, "0 PTS", correctTextStr, randomQuote, reviewSeconds, nextEpoch, isLastQ);
    }

    // Do NOT set playerChoiceSubmitted = null here! Keep choice locked in during review phase.
    // It will be cleared cleanly when the next question starts.
  }
}

function getRandomItem(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function showResultModal(isCorrect, pointsText, correctTextStr, funnyQuote, countdownSeconds = 15, targetEpochMs = null, isLastQ = false) {
  const overlay = document.getElementById('result-modal-overlay');
  const card = document.getElementById('result-modal-box');
  const icon = document.getElementById('result-modal-icon');
  const title = document.getElementById('result-modal-title');
  const scorePill = document.getElementById('result-modal-score');
  const correctTextEl = document.getElementById('result-correct-text');
  const quote = document.getElementById('result-modal-quote');
  const modalTimerVal = document.getElementById('modal-next-q-timer');

  if (!overlay || !card) return;

  if (isCorrect) {
    card.className = 'result-modal-card is-correct';
    if (icon) icon.textContent = '🎉';
    if (title) title.textContent = 'CORRECT! YOU GOT IT!';
    if (scorePill) scorePill.textContent = pointsText;
    try {
      confetti({
        particleCount: 80,
        spread: 90,
        origin: { y: 0.5 },
        colors: ['#10B981', '#00E5FF', '#FFD700', '#FF007A', '#FFFFFF']
      });
    } catch (_) {}
  } else {
    card.className = 'result-modal-card is-wrong';
    if (icon) icon.textContent = '❌';
    if (title) title.textContent = 'OOPS! YOU MISSED IT!';
    if (scorePill) scorePill.textContent = pointsText;
  }

  if (correctTextEl) correctTextEl.textContent = decodeHtmlEntities(correctTextStr);
  if (quote) quote.textContent = `"${funnyQuote}"`;

  const pill = document.querySelector('.next-q-countdown-pill');
  if (pill) {
    if (isLastQ) {
      pill.innerHTML = `⏱️ Round Results in <strong id="modal-next-q-timer">${countdownSeconds}</strong>s...`;
    } else {
      pill.innerHTML = `⏳ Next Question in <strong id="modal-next-q-timer">${countdownSeconds}</strong>s...`;
    }
  }

  const now = Date.now();
  let targetEpoch = targetEpochMs;
  if (!targetEpoch || (targetEpoch - now) <= 5000) {
    targetEpoch = now + Math.max(10, Math.round(countdownSeconds * 1000));
  }

  const updateModalCountdown = () => {
    const rem = Math.max(0, Math.ceil((targetEpoch - Date.now()) / 1000));
    const activeTimer = document.getElementById('modal-next-q-timer');
    if (activeTimer) activeTimer.textContent = rem;
    if (rem <= (isLastQ ? 0 : 5)) {
      clearInterval(modalCountdownInterval);
      hideResultModal();
      if (!isLastQ) {
        showInterQuestionCountdown(targetEpoch);
      }
    }
  };

  updateModalCountdown();
  clearInterval(modalCountdownInterval);
  modalCountdownInterval = setInterval(updateModalCountdown, 500);

  overlay.classList.remove('hidden');
  // Tap-to-dismiss transitions to dedicated countdown screen (or hides if round ending)
  overlay.onclick = () => {
    clearInterval(modalCountdownInterval);
    hideResultModal();
    if (!isLastQ) {
      showInterQuestionCountdown(targetEpoch);
    }
  };
}

let playerInterQuestionInterval = null;

function showInterQuestionCountdown(targetEpochMs) {
  hideResultModal();
  clearInterval(playerInterQuestionInterval);

  const now = Date.now();
  let targetEpoch = targetEpochMs;
  if (!targetEpoch || (targetEpoch - now) <= 0) {
    targetEpoch = now + 5000;
  }

  const interQScreen = document.getElementById('player-inter-question-screen');
  const timerVal = document.getElementById('player-inter-q-timer');
  const subtextVal = document.getElementById('player-inter-q-subtext');
  const qCard = document.querySelector('.player-question-card');
  const btnGrid = document.querySelector('.button-grid-2x2');

  // Immediately hide previous question and previous choices
  if (qCard) {
    qCard.classList.add('hidden');
    qCard.style.display = 'none';
  }
  if (btnGrid) {
    btnGrid.classList.add('hidden');
    btnGrid.style.display = 'none';
  }
  if (interQScreen) {
    interQScreen.classList.remove('hidden');
    interQScreen.style.display = 'flex';
  }

  const updateCountdown = () => {
    const rem = Math.max(0, Math.ceil((targetEpoch - Date.now()) / 1000));
    if (timerVal) {
      timerVal.textContent = rem > 0 ? `${rem} SECS` : '0 SECS';
    }
    if (subtextVal) {
      const qNumInRound = ((currentQuestionIndex % 10) + 1);
      const nextQNum = qNumInRound < 10 ? qNumInRound + 1 : 1;
      const isLastQ = qNumInRound >= 10;
      subtextVal.textContent = rem > 0 
        ? (isLastQ 
            ? `Round ${currentRound} Final Question Complete • Preparing Results...` 
            : `Round ${currentRound} • Preparing Question ${nextQNum} of 10...`)
        : 'Loading next question...';
    }
    if (rem <= 0) {
      if (typeof triggerActiveSessionSync === 'function') {
        triggerActiveSessionSync();
      }
      broadcastRealtimeEvent('request_state_sync', { room_code: currentRoomCode });
    }
  };

  updateCountdown();
  playerInterQuestionInterval = setInterval(updateCountdown, 500);
}

function hideInterQuestionCountdown() {
  clearInterval(playerInterQuestionInterval);
  const interQScreen = document.getElementById('player-inter-question-screen');
  const qCard = document.querySelector('.player-question-card');
  const btnGrid = document.querySelector('.button-grid-2x2');
  if (interQScreen) {
    interQScreen.classList.add('hidden');
    interQScreen.style.display = 'none';
  }
  if (qCard) {
    qCard.classList.remove('hidden');
    qCard.style.display = '';
  }
  if (btnGrid) {
    btnGrid.classList.remove('hidden');
    btnGrid.style.display = '';
  }
}

function hideResultModal() {
  const overlay = document.getElementById('result-modal-overlay');
  if (overlay) {
    overlay.classList.add('hidden');
    overlay.onclick = null;
  }
  clearInterval(modalCountdownInterval);
}

// 7. MULTI-LAYER ROUND WINNER CELEBRATION MODAL WITH LIVE COUNTDOWN
function onRoundWinner(payload) {
  hideResultModal();
  hideInterQuestionCountdown();

  // Update Host Mobile Stage Card
  const hostStageBadge = document.getElementById('host-stage-badge');
  const hostStageQCounter = document.getElementById('host-stage-q-counter');
  const btnSkip = document.getElementById('btn-skip-question');
  if (hostStageBadge) {
    hostStageBadge.className = 'stage-status-indicator stage-summary';
    hostStageBadge.textContent = '🏆 ROUND COMPLETED';
  }
  if (hostStageQCounter) {
    hostStageQCounter.textContent = `Round ${currentRound} Complete! Next round loading...`;
  }
  const rNum = Number(payload?.roundNumber || payload?.round_number || currentRound);
  if (rNum > 0) currentRound = Math.max(currentRound, rNum);
  updatePlayerHeaderCard(currentRound, null, 'Intermission');

  if (btnSkip) btnSkip.classList.add('hidden');

  let top3 = [];
  if (Array.isArray(payload?.top3Winners) && payload.top3Winners.length > 0) {
    top3 = payload.top3Winners;
  } else if (Array.isArray(payload?.top_3_winners) && payload.top_3_winners.length > 0) {
    top3 = payload.top_3_winners;
  } else if (Array.isArray(payload?.top3_winners) && payload.top3_winners.length > 0) {
    top3 = payload.top3_winners;
  } else {
    top3 = playersLeaderboard.slice(0, 3);
  }

  // Filter out any fictitious players, strictly preserving all real players even with score 0
  top3 = top3.filter(p => p && p.nickname && !isFictitiousPlayer(p.nickname));

  const tvWinnerOverlay = document.getElementById('tv-winner-modal-overlay');
  const playerWinnerOverlay = document.getElementById('player-winner-modal-overlay');

  const tvPodium1 = document.getElementById('tv-podium-1');
  const tvPodium2 = document.getElementById('tv-podium-2');
  const tvPodium3 = document.getElementById('tv-podium-3');

  const playerPodium1 = document.getElementById('player-podium-1');
  const playerPodium2 = document.getElementById('player-podium-2');
  const playerPodium3 = document.getElementById('player-podium-3');

  if (top3.length > 0) {
    const winner1 = top3[0];
    const winner2 = top3[1];
    const winner3 = top3[2];

    const tvW1Name = document.getElementById('tv-w1-name');
    const tvW1Score = document.getElementById('tv-w1-score');
    const tvW2Name = document.getElementById('tv-w2-name');
    const tvW2Score = document.getElementById('tv-w2-score');
    const tvW3Name = document.getElementById('tv-w3-name');
    const tvW3Score = document.getElementById('tv-w3-score');

    if (tvPodium1) tvPodium1.style.display = 'flex';
    if (tvW1Name) tvW1Name.textContent = (winner1.nickname || '').toUpperCase();
    if (tvW1Score) tvW1Score.textContent = `${Number(winner1.score ?? winner1.cumulative_score ?? 0)} PTS`;

    if (tvPodium2) {
      if (winner2) {
        tvPodium2.style.display = 'flex';
        if (tvW2Name) tvW2Name.textContent = (winner2.nickname || '').toUpperCase();
        if (tvW2Score) tvW2Score.textContent = `${Number(winner2.score ?? winner2.cumulative_score ?? 0)} PTS`;
      } else {
        tvPodium2.style.display = 'none';
      }
    }

    if (tvPodium3) {
      if (winner3) {
        tvPodium3.style.display = 'flex';
        if (tvW3Name) tvW3Name.textContent = (winner3.nickname || '').toUpperCase();
        if (tvW3Score) tvW3Score.textContent = `${Number(winner3.score ?? winner3.cumulative_score ?? 0)} PTS`;
      } else {
        tvPodium3.style.display = 'none';
      }
    }

    const pW1Name = document.getElementById('player-w1-name');
    const pW1Score = document.getElementById('player-w1-score');
    const pW2Name = document.getElementById('player-w2-name');
    const pW2Score = document.getElementById('player-w2-score');
    const pW3Name = document.getElementById('player-w3-name');
    const pW3Score = document.getElementById('player-w3-score');

    if (playerPodium1) playerPodium1.style.display = 'flex';
    if (pW1Name) pW1Name.textContent = (winner1.nickname || '').toUpperCase();
    if (pW1Score) pW1Score.textContent = `${Number(winner1.score ?? winner1.cumulative_score ?? 0)} PTS`;

    if (playerPodium2) {
      if (winner2) {
        playerPodium2.style.display = 'flex';
        if (pW2Name) pW2Name.textContent = (winner2.nickname || '').toUpperCase();
        if (pW2Score) pW2Score.textContent = `${Number(winner2.score ?? winner2.cumulative_score ?? 0)} PTS`;
      } else {
        playerPodium2.style.display = 'none';
      }
    }

    if (playerPodium3) {
      if (winner3) {
        playerPodium3.style.display = 'flex';
        if (pW3Name) pW3Name.textContent = (winner3.nickname || '').toUpperCase();
        if (pW3Score) pW3Score.textContent = `${Number(winner3.score ?? winner3.cumulative_score ?? 0)} PTS`;
      } else {
        playerPodium3.style.display = 'none';
      }
    }
  }

  if (top3.length > 0 && currentPlayer && currentPlayer.nickname) {
    const myWinner = top3.find(w => w && w.nickname && w.nickname.toLowerCase() === currentPlayer.nickname.toLowerCase());
    if (myWinner) {
      const topScore = Math.max(Number(currentPlayer.score || 0), Number(myWinner.score ?? myWinner.cumulative_score ?? 0));
      currentPlayer.score = topScore;
      const scoreVal = document.getElementById('player-score-val');
      if (scoreVal) scoreVal.textContent = topScore;
    }
  } else {
    // If no players are registered yet, hide podium rows rather than showing fictitious names
    if (tvPodium1) tvPodium1.style.display = 'none';
    if (tvPodium2) tvPodium2.style.display = 'none';
    if (tvPodium3) tvPodium3.style.display = 'none';
    if (playerPodium1) playerPodium1.style.display = 'none';
    if (playerPodium2) playerPodium2.style.display = 'none';
    if (playerPodium3) playerPodium3.style.display = 'none';
  }

  const tvNextRoundTimer = document.getElementById('tv-winner-next-round-timer');
  const playerWinnerTimer = document.getElementById('player-winner-next-round-timer') || document.getElementById('player-winner-next-timer');

  if (tvWinnerOverlay) tvWinnerOverlay.classList.remove('hidden');
  if (playerWinnerOverlay) playerWinnerOverlay.classList.remove('hidden');

  currentGameState = 'ROUND_SUMMARY';

  let remWinnerSecs = Number(payload?.delaySeconds || payload?.delay_seconds || payload?.duration_seconds || selectedInterRoundDuration || 120);
  let targetEpoch = payload?.starts_at_epoch_ms || payload?.next_round_starts_at_epoch_ms;
  if (!targetEpoch && payload?.starts_at) {
    const parsed = typeof payload.starts_at === 'string' ? Date.parse(payload.starts_at) : Number(payload.starts_at);
    if (!isNaN(parsed)) targetEpoch = parsed;
  }
  if (!targetEpoch && payload?.timer_ends_at) {
    const parsed = typeof payload.timer_ends_at === 'string' ? Date.parse(payload.timer_ends_at) : Number(payload.timer_ends_at);
    if (!isNaN(parsed)) targetEpoch = parsed;
  }
  if (!targetEpoch && remWinnerSecs > 0) {
    targetEpoch = Date.now() + remWinnerSecs * 1000;
  }
  if (targetEpoch) {
    const diff = Math.ceil((targetEpoch - Date.now()) / 1000);
    if (diff > 0) {
      remWinnerSecs = diff;
    }
  }

  // Dismiss Top 3 Winners overlay on TV after 20 seconds so ad signage is displayed uncovered for remainder of intermission
  clearTimeout(tvWinnerOverlayTimeout);
  const winnerDisplayMs = Math.min(20000, remWinnerSecs * 1000);
  tvWinnerOverlayTimeout = setTimeout(() => {
    if (tvWinnerOverlay) {
      tvWinnerOverlay.classList.add('hidden');
    }
    syncTvSignageDisplay();
  }, winnerDisplayMs);

  syncTvSignageDisplay();

  const formatRoundTimer = (s) => {
    const mins = Math.floor(s / 60);
    const secs = s % 60;
    return `${mins}:${String(secs).padStart(2, '0')}`;
  };

  const formatIntermissionBadgeText = (s) => {
    if (s <= 0) return 'STARTING NOW';
    const mins = Math.floor(s / 60);
    const secs = s % 60;
    if (mins >= 1 && secs === 0) {
      return `${mins} MINUTE${mins > 1 ? 'S' : ''}`;
    }
    if (mins >= 1) {
      return `${mins} MIN ${secs} SEC`;
    }
    return `${secs} SECONDS`;
  };

  if (tvNextRoundTimer) tvNextRoundTimer.textContent = formatIntermissionBadgeText(remWinnerSecs);
  if (playerWinnerTimer) playerWinnerTimer.textContent = formatRoundTimer(remWinnerSecs);

  // Also display NEXT ROUND STARTING IN..... directly on the player question card
  const playerQuestionText = document.getElementById('player-question-text');
  const playerCategoryPill = document.getElementById('player-category-pill');
  const statusText = document.getElementById('status-text');
  if (playerQuestionText) {
    playerQuestionText.innerHTML = `
      <div style="text-align:center; padding: 12px 0;">
        <div style="font-size:13px; font-weight:900; color:var(--accent-yellow); letter-spacing:1.5px; text-transform:uppercase; margin-bottom:8px;">NEXT ROUND STARTING IN.....</div>
        <div style="font-size:42px; font-weight:900; color:#fff; letter-spacing:2px;" id="player-card-round-timer">${formatIntermissionBadgeText(remWinnerSecs)}</div>
        <div style="font-size:13px; color:rgba(255,255,255,0.7); margin-top:8px; font-weight:600;">Round ${currentRound} Complete • Ready for Next Round!</div>
      </div>
    `;
  }
  if (playerCategoryPill) {
    playerCategoryPill.textContent = `ROUND ${currentRound} COMPLETE`;
  }
  if (statusText) {
    statusText.textContent = 'INTERMISSION';
  }

  currentQuestionData = null;
  hideResultModal();
  hideInterQuestionCountdown();
  const btnTvBack = document.getElementById('btn-tv-back');
  if (btnTvBack) btnTvBack.classList.remove('question-hidden');

  const answerBtns = document.querySelectorAll('.btn-answer');
  answerBtns.forEach(btn => {
    btn.disabled = true;
    btn.classList.remove('selected', 'unselected', 'review-correct', 'review-wrong');
  });

  clearInterval(winnerCountdownInterval);
  winnerCountdownInterval = setInterval(() => {
    const currentSecs = targetEpoch ? Math.max(0, Math.ceil((targetEpoch - Date.now()) / 1000)) : Math.max(0, --remWinnerSecs);
    const badgeText = formatIntermissionBadgeText(currentSecs);
    const roundTimerText = formatRoundTimer(currentSecs);

    if (tvNextRoundTimer) tvNextRoundTimer.textContent = badgeText;
    if (playerWinnerTimer) playerWinnerTimer.textContent = roundTimerText;
    const cardTimer = document.getElementById('player-card-round-timer');
    if (cardTimer) cardTimer.textContent = badgeText;

    // Actively display the countdown timer on the TV promo bottom banner and ad signage
    const promoFluctuating = document.getElementById('promo-fluctuating-text') || document.querySelector('.promo-cta-box-centered .fluctuating-text');
    if (promoFluctuating) {
      promoFluctuating.textContent = `NEXT ROUND IN ${badgeText}`;
      promoFluctuating.style.color = 'var(--accent-yellow)';
    }

    const tvAdBanner = document.getElementById('tv-ad-intermission-banner');
    const tvAdTimer = document.getElementById('tv-ad-round-timer');
    if (tvAdBanner) tvAdBanner.classList.remove('hidden');
    if (tvAdTimer) tvAdTimer.textContent = badgeText;

    if (currentSecs <= 0) {
      clearInterval(winnerCountdownInterval);
      winnerCountdownInterval = null;
      hideWinnerModals();
      if (currentGameState === 'ROUND_SUMMARY') {
        currentGameState = 'COUNTDOWN';
      }
      if (tvNextRoundTimer) tvNextRoundTimer.textContent = 'STARTING NOW';
      if (playerWinnerTimer) playerWinnerTimer.textContent = '0:00';
      if (cardTimer) cardTimer.textContent = 'STARTING NOW';
      if (promoFluctuating) promoFluctuating.textContent = 'STARTING NEXT ROUND...';
      if (tvAdTimer) tvAdTimer.textContent = 'STARTING NOW';

      // Immediately request state sync from host / TV display
      broadcastRealtimeEvent('request_state_sync', {
        room_code: currentRoomCode,
        client: 'player',
        timestamp: Date.now()
      });
      if (typeof triggerActiveSessionSync === 'function') {
        triggerActiveSessionSync();
      }
    }
  }, 1000);

  const roundNum = Number(payload?.roundNumber || payload?.round_number || currentRound || 1);
  const fanfareKey = `round_${roundNum}`;
  const nowMs = Date.now();
  if (lastFanfareCelebrationKey !== fanfareKey || (nowMs - lastFanfarePlayEpoch) > 15000) {
    lastFanfareCelebrationKey = fanfareKey;
    lastFanfarePlayEpoch = nowMs;
    confetti({ particleCount: 120, spread: 100, origin: { y: 0.5 } });
    playSound('fanfare');
  }
}

function hideWinnerModals() {
  const tvWinnerOverlay = document.getElementById('tv-winner-modal-overlay');
  const playerWinnerOverlay = document.getElementById('player-winner-modal-overlay');

  clearTimeout(tvWinnerOverlayTimeout);
  if (tvWinnerOverlay) tvWinnerOverlay.classList.add('hidden');
  if (playerWinnerOverlay) playerWinnerOverlay.classList.add('hidden');
  if (currentGameState !== 'ROUND_SUMMARY') {
    clearInterval(winnerCountdownInterval);
    const promoFluctuating = document.getElementById('promo-fluctuating-text') || document.querySelector('.promo-cta-box-centered .fluctuating-text');
    if (promoFluctuating) {
      promoFluctuating.textContent = 'WAITING FOR HOST TO START GAME';
      promoFluctuating.style.color = '';
    }
    const tvAdBanner = document.getElementById('tv-ad-intermission-banner');
    if (tvAdBanner) tvAdBanner.classList.add('hidden');
  }
}

function onRoundSummary(payload) {
  hideResultModal();
  hideInterQuestionCountdown();
}

// 8. PLAYER CONTROLLER HANDLER WITH SPEED BONUS & STREAK MULTIPLIER SCORING
function initPlayerControls() {
  const formJoin = document.getElementById('form-player-join');
  const btnJoin = document.getElementById('btn-player-join');
  const playerEntryScreen = document.getElementById('player-entry-screen');
  const playerControllerScreen = document.getElementById('player-controller-screen');
  const playerDispNickname = document.getElementById('player-disp-nickname');
  const playerDispRoom = document.getElementById('player-disp-room');
  const answerBtns = document.querySelectorAll('.btn-answer');
  const nicknameInput = document.getElementById('input-nickname');

  const savedNick = safeStorage.getItem('bar_trivia_player_nickname');
  if (savedNick && nicknameInput && !nicknameInput.value) {
    nicknameInput.value = savedNick;
  }

  function doJoin() {
    const roomInput = document.getElementById('input-room-code');

    const enteredRoom = (roomInput?.value || '').trim();
    if (enteredRoom) {
      currentRoomCode = enteredRoom.toUpperCase().replace(/[^A-Z0-9-]/g, '');
    }

    const rawNick = (nicknameInput?.value || '').trim();
    if (rawNick && isFictitiousPlayer(rawNick)) {
      alert('This name is reserved for the Host. Please choose a different nickname to play!');
      return;
    }
    const nickname = rawNick || `Player_${Math.floor(Math.random() * 900 + 100)}`;

    safeStorage.setItem('bar_trivia_player_nickname', nickname);
    safeStorage.setItem('bar_trivia_current_room', currentRoomCode);

    currentPlayer = { nickname, score: 0, streak: 0 };
    if (playerDispNickname) playerDispNickname.textContent = nickname.toUpperCase();
    updatePlayerHeaderCard(currentRound, null, 'Ready');
    const playerTimerVal = document.getElementById('player-timer-val');
    if (playerTimerVal) {
      playerTimerVal.textContent = selectedQuestionDuration || 20;
    }

    if (playerEntryScreen) {
      playerEntryScreen.classList.add('hidden');
      playerEntryScreen.style.display = 'none';
    }
    if (playerControllerScreen) {
      playerControllerScreen.classList.remove('hidden');
      playerControllerScreen.style.display = 'flex';
    }

    // Re-initialize Realtime connection for this specific room code
    initRealtimeEngine();

    // Acquire screen wake lock so player's phone screen doesn't turn off
    requestScreenWakeLock();

    // Broadcast join immediately and retry with intervals to ensure MQTT delivery
    const sendJoinBroadcast = () => {
      if (!currentPlayer || !currentPlayer.nickname || isFictitiousPlayer(currentPlayer.nickname)) return;
      broadcastRealtimeEvent('player_joined', {
        nickname: currentPlayer.nickname,
        score: Number(currentPlayer.score ?? 0),
        room_code: currentRoomCode,
      });
      // Also write directly to Supabase players table
      try {
        supabase.from('players').upsert({
          room_code: currentRoomCode.toUpperCase(),
          nickname: currentPlayer.nickname,
          player_uid: currentPlayer.nickname,
          cumulative_score: Number(currentPlayer.score ?? 0),
          is_connected: true,
          updated_at: new Date().toISOString()
        }).catch(() => {});
        if (currentRoomCode.toUpperCase() !== 'TRIV') {
          supabase.from('players').upsert({
            room_code: 'TRIV',
            nickname: currentPlayer.nickname,
            player_uid: currentPlayer.nickname,
            cumulative_score: Number(currentPlayer.score ?? 0),
            is_connected: true,
            updated_at: new Date().toISOString()
          }).catch(() => {});
        }
      } catch (_) {}
    };
    sendJoinBroadcast();
    setTimeout(sendJoinBroadcast, 300);
    setTimeout(sendJoinBroadcast, 800);
    setTimeout(sendJoinBroadcast, 1800);
    setTimeout(sendJoinBroadcast, 3000);

    broadcastRealtimeEvent('request_state_sync', { room_code: currentRoomCode });
    onPlayerJoined(currentPlayer);

    if (currentQuestionData) {
      const now = Date.now();
      const remainingMs = timerEndsAtGlobalMs > 0 ? (timerEndsAtGlobalMs - now) : 0;
      const remSecs = remainingMs > 3000
        ? Math.ceil(remainingMs / 1000)
        : (remainingTimerSeconds > 3 ? remainingTimerSeconds : (Number(selectedQuestionDuration) || 20));
      onQuestionStart({
        questionData: currentQuestionData,
        roundNumber: currentRound,
        questionNumberInRound: (currentQuestionIndex % 10) + 1,
        durationSeconds: remSecs,
        difficulty: selectedDifficulty,
      });
    }

    async function syncSessionFromSupabase() {
      // Periodic player heartbeat ensures TV display maintains sync
      if (currentPlayer && currentPlayer.nickname && !isFictitiousPlayer(currentPlayer.nickname)) {
        sendJoinBroadcast();
      }

      try {
        const code = (currentRoomCode || 'TRIV').trim().toUpperCase();
        let { data, error } = await supabase.from('game_sessions')
          .select('*')
          .eq('room_code', code)
          .order('updated_at', { ascending: false })
          .limit(1);

        if ((!data || data.length === 0) && code !== 'TRIV') {
          const fallbackRes = await supabase.from('game_sessions')
            .select('*')
            .eq('room_code', 'TRIV')
            .order('updated_at', { ascending: false })
            .limit(1);
          data = fallbackRes.data;
        }

        const session = (data && data.length > 0) ? data[0] : null;
        if (session) {
          if (session.is_sound_effects_enabled !== undefined) {
            setSoundEffectsEnabled(Boolean(session.is_sound_effects_enabled), false);
          } else if (session.is_sound_enabled !== undefined) {
            setSoundEffectsEnabled(Boolean(session.is_sound_enabled), false);
          }
          if (session.is_ad_mode_active !== undefined) {
            const adActive = Boolean(session.is_ad_mode_active);
            if (isAdModeActive !== adActive) {
              isAdModeActive = adActive;
              safeStorage.setItem('bar_trivia_ad_mode_active', String(isAdModeActive));
              syncTvSignageDisplay();
            }
          }
          if (session.status === 'paused') {
            if (currentGameState !== 'PAUSED') {
              onGamePaused({
                remaining_question_seconds: session.remaining_question_seconds,
                round_number: session.current_round,
                question_index: session.current_question_index,
              });
            }
          } else if (session.status === 'resuming') {
            if (currentGameState === 'PAUSED') {
              onGameResuming({
                starts_at_epoch_ms: session.starts_at,
                remaining_question_seconds: session.remaining_question_seconds,
                round_number: session.current_round,
                question_index: session.current_question_index,
              });
            }
          }
          const rNum = Number(session.current_round || session.round_number || 0);
          if (rNum > 0) {
            if (session.status === 'pre_game_countdown' && rNum === 1) {
              currentRound = 1;
              currentQuestionIndex = 0;
            } else {
              currentRound = Math.max(currentRound, rNum);
            }
          }
          if (session.status === 'pre_game_countdown') {
            let startsAt = session.starts_at;
            if (typeof startsAt === 'string') {
              const parsed = Date.parse(startsAt);
              startsAt = !isNaN(parsed) ? parsed : Number(startsAt);
            } else if (startsAt) {
              startsAt = Number(startsAt);
            }
            startsAt = startsAt || Date.now();
            const rem = Math.max(1, Math.ceil((startsAt - Date.now()) / 1000));
            handleIncomingPreGameCountdown({ countdown_seconds: rem, round_number: rNum || currentRound, genre: session.genre });
          } else if ((session.status === 'question_active' || session.status === 'active_reading') && session.question_data) {
            const isIntermissionActive = currentGameState === 'ROUND_SUMMARY' || hostEngineState === 'ROUND_SUMMARY';
            const sessionRound = Number(session.current_round || session.round_number || session.question_data.round_number || session.question_data.roundNumber || currentRound);
            if (isIntermissionActive) {
              if (sessionRound < currentRound) {
                return;
              }
              currentGameState = 'QUESTION_ACTIVE';
              clearInterval(winnerCountdownInterval);
              winnerCountdownInterval = null;
              hideWinnerModals();
            }
            const qData = session.question_data;
            const now = Date.now();
            let endsAt = session.timer_ends_at;
            if (typeof endsAt === 'string') {
              const parsed = Date.parse(endsAt);
              endsAt = !isNaN(parsed) ? parsed : Number(endsAt);
            } else if (endsAt) {
              endsAt = Number(endsAt);
            }
            const dur = Math.max(5, Number(session.duration_seconds || session.time_limit_seconds || selectedQuestionDuration || 20));
            if (!endsAt || isNaN(endsAt) || (endsAt - now) <= 4000) {
              endsAt = now + (dur * 1000);
            }
            if ((endsAt - now) > -60000) {
              const sessionQIdx = session.current_question_index || 0;
              const curQIdx = (currentQuestionIndex !== null && currentQuestionIndex !== undefined) ? currentQuestionIndex + 1 : 0;
              const qText = qData.text || qData.question || qData.question_text || '';
              const curText = currentQuestionData ? (currentQuestionData.text || currentQuestionData.question || currentQuestionData.question_text || '') : '';
              
              const playerQElem = document.getElementById('player-question-text');
              const isUiWaiting = !playerQElem ||
                playerQElem.textContent.includes('Waiting for next question') ||
                playerQElem.textContent.includes('Get ready') ||
                playerQElem.textContent.includes('STARTING IN') ||
                playerQElem.textContent.includes('NEXT ROUND') ||
                playerQElem.textContent.trim() === '';

              const isDifferentQ = !currentQuestionData ||
                isUiWaiting ||
                (sessionQIdx > 0 && sessionQIdx !== curQIdx) ||
                (sessionRound !== currentRound) ||
                (qData.id && currentQuestionData.id && qData.id !== currentQuestionData.id) ||
                (qText && curText && qText !== curText);

              if (isDifferentQ) {
                hideResultModal();
                hideInterQuestionCountdown();
                handleIncomingQuestionStart({
                  ...qData,
                  question_index: session.current_question_index || 1,
                  cumulative_question_index: session.current_question_index || 1,
                  round_number: sessionRound,
                  roundNumber: sessionRound,
                  duration_seconds: dur,
                  totalTimerDuration: dur,
                  timer_ends_at_epoch_ms: endsAt,
                  timestamp: now,
                  sent_at_epoch_ms: now,
                });
              } else {
                const qNum = ((session.current_question_index - 1) % 10) + 1;
                updatePlayerHeaderCard(currentRound, qNum);
              }
            }
          } else if (session.status === 'round_summary' || session.status === 'inter_round') {
            currentGameState = 'ROUND_SUMMARY';
            updatePlayerHeaderCard(currentRound, null, 'Intermission');
            let endsAt = session.timer_ends_at || session.starts_at;
            let targetEpoch = null;
            if (typeof endsAt === 'string') {
              const parsed = Date.parse(endsAt);
              targetEpoch = !isNaN(parsed) ? parsed : Number(endsAt);
            } else if (endsAt) {
              targetEpoch = Number(endsAt);
            }
            const rem = targetEpoch ? Math.max(0, Math.ceil((targetEpoch - Date.now()) / 1000)) : (Number(session.duration_seconds) || 120);
            const tvWinnerOverlay = document.getElementById('tv-winner-modal-overlay');
            const playerWinnerOverlay = document.getElementById('player-winner-modal-overlay');
            const isWinnerShowing = (tvWinnerOverlay && !tvWinnerOverlay.classList.contains('hidden')) ||
                                    (playerWinnerOverlay && !playerWinnerOverlay.classList.contains('hidden'));
            if (!isWinnerShowing) {
              onRoundWinner({
                top_scorers: playersLeaderboard.slice(0, 3),
                delaySeconds: rem,
                starts_at_epoch_ms: targetEpoch
              });
            } else {
              const formatRoundTimer = (s) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
              const tvNextRoundTimer = document.getElementById('tv-winner-next-round-timer');
              const playerWinnerTimer = document.getElementById('player-winner-next-round-timer') || document.getElementById('player-winner-next-timer');
              const cardTimer = document.getElementById('player-card-round-timer');
              if (tvNextRoundTimer) tvNextRoundTimer.textContent = rem >= 60 ? formatRoundTimer(rem) : rem;
              if (playerWinnerTimer) playerWinnerTimer.textContent = formatRoundTimer(rem);
              if (cardTimer) cardTimer.textContent = formatRoundTimer(rem);
            }
          }

          if (currentPlayer && currentPlayer.nickname) {
            const myRow = playersLeaderboard.find(p => p.nickname.toLowerCase() === currentPlayer.nickname.toLowerCase());
            if (myRow) {
              const myTop = Math.max(Number(currentPlayer.score || 0), Number(myRow.cumulative_score || myRow.score || 0));
              if (myTop > Number(currentPlayer.score || 0)) {
                currentPlayer.score = myTop;
                const scoreVal = document.getElementById('player-score-val');
                if (scoreVal) scoreVal.textContent = myTop;
              }
            }
          }
        }
      } catch (err) {
        console.warn('[Sync] checkActiveGameSession error:', err);
      }
    }

    function checkActiveGameSession() {
      syncSessionFromSupabase();
    }

    triggerActiveSessionSync = checkActiveGameSession;
    checkActiveGameSession();
    setInterval(checkActiveGameSession, 2000);
  }

  formJoin?.addEventListener('submit', (e) => {
    e.preventDefault();
    doJoin();
  });

  btnJoin?.addEventListener('click', (e) => {
    e.preventDefault();
    doJoin();
  });

  answerBtns.forEach(btn => {
    btn.onclick = (e) => {
      e.preventDefault();
      // Guard: Only allow choosing if player is registered and hasn't already submitted
      if (!currentPlayer || playerChoiceSubmitted !== null) return;

      const choice = (btn.dataset.choice || '').toUpperCase();
      playerChoiceSubmitted = choice;

      // Haptic feedback (buzzer vibration on mobile devices)
      if (typeof navigator !== 'undefined' && 'vibrate' in navigator) {
        try { navigator.vibrate(45); } catch (_) {}
      }
      playSound('tap');

      // Lock visually: highlight selected and dim unselected
      answerBtns.forEach(b => {
        const bChoice = (b.dataset.choice || '').toUpperCase();
        if (bChoice === choice) {
          b.classList.add('selected');
          b.classList.remove('unselected');
        } else {
          b.classList.add('unselected');
          b.classList.remove('selected');
        }
        b.disabled = true;
      });

      const playerStatusBadge = document.getElementById('player-status-badge');
      if (playerStatusBadge) {
        playerStatusBadge.className = 'status-badge status-locked';
        playerStatusBadge.innerHTML = `<span id="status-icon">🔒</span> LOCKED IN: Option ${choice}`;
      }

      broadcastRealtimeEvent('answer_submitted', {
        nickname: currentPlayer.nickname,
        selected_option: choice,
        score: Number(currentPlayer.score ?? 0),
      });
    };
  });
}

function onPlayerJoined(player) {
  if (!player || !player.nickname || isFictitiousPlayer(player.nickname)) return;
  const initialScore = Number(player.score ?? player.cumulative_score ?? 0);
  const exists = playersLeaderboard.some(p => p.nickname.toLowerCase() === player.nickname.toLowerCase());
  if (!exists) {
    playersLeaderboard.push({
      id: player.id || player.nickname,
      player_uid: player.player_uid || player.nickname,
      room_code: currentRoomCode,
      nickname: player.nickname,
      score: initialScore,
      cumulative_score: initialScore,
      streak: player.streak || 0,
      is_connected: true
    });
  } else {
    const idx = playersLeaderboard.findIndex(p => p.nickname.toLowerCase() === player.nickname.toLowerCase());
    if (idx >= 0) {
      playersLeaderboard[idx].is_connected = true;
      if (initialScore === 0) {
        playersLeaderboard[idx].score = 0;
        playersLeaderboard[idx].cumulative_score = 0;
      } else if (player.score !== undefined || player.cumulative_score !== undefined) {
        playersLeaderboard[idx].score = Math.max(Number(playersLeaderboard[idx].score || 0), initialScore);
        playersLeaderboard[idx].cumulative_score = Math.max(Number(playersLeaderboard[idx].cumulative_score || 0), initialScore);
      }
    }
  }

  renderLeaderboard();
  channel.postMessage({ type: 'LEADERBOARD_UPDATED', payload: { leaderboard: playersLeaderboard } });
  broadcastRealtimeEvent('leaderboard_updated', {
    players: playersLeaderboard,
    leaderboard: playersLeaderboard,
    room_code: currentRoomCode
  });

  // Persist to Supabase DB players table
  try {
    supabase.from('players').upsert({
      room_code: currentRoomCode.toUpperCase(),
      nickname: player.nickname,
      player_uid: player.player_uid || player.nickname,
      cumulative_score: initialScore,
      is_connected: true,
      updated_at: new Date().toISOString()
    }, { onConflict: 'room_code,nickname' }).catch(() => {});
  } catch (_) {}

  updateHostEngineUI(isAutomatedEngineRunning ? 'IN PROGRESS' : 'NOT STARTED');
}

function onAnswerSubmitted(payload) {
  if (!payload) return;
  const nick = payload.nickname || payload.player?.nickname;
  const choice = (payload.selected_option || payload.choice || '').toUpperCase().trim();
  if (!nick || !choice) return;

  const existingPlayer = playersLeaderboard.find(p => p.nickname.toLowerCase() === nick.toLowerCase());
  const scoreAtSubmission = existingPlayer ? Number(existingPlayer.score || 0) : Number(payload.score || 0);

  currentQuestionAnswers[nick.toLowerCase()] = {
    nickname: nick,
    choice: choice,
    scoreAtSubmission: scoreAtSubmission,
    timestamp: payload.timestamp || Date.now(),
    graded: false,
  };
  console.log(`[Host/TV] Player ${nick} answer recorded: ${choice}`);
}

function onPlayerScoreUpdated(payload) {
  if (!payload) return;
  const nick = payload.nickname || payload.player?.nickname;
  if (!nick || isFictitiousPlayer(nick)) return;
  const incScore = Number(payload.score ?? payload.cumulative_score ?? 0);
  const idx = playersLeaderboard.findIndex(p => p.nickname.toLowerCase() === nick.toLowerCase());
  if (idx >= 0) {
    playersLeaderboard[idx].score = Math.max(Number(playersLeaderboard[idx].score || 0), incScore);
    playersLeaderboard[idx].cumulative_score = Math.max(Number(playersLeaderboard[idx].cumulative_score || 0), incScore);
    if (payload.streak !== undefined) playersLeaderboard[idx].streak = payload.streak;
    playersLeaderboard[idx].is_connected = true;
  } else {
    playersLeaderboard.push({
      id: nick,
      player_uid: nick,
      room_code: currentRoomCode,
      nickname: nick,
      score: incScore,
      cumulative_score: incScore,
      streak: payload.streak || 0,
      is_connected: true,
    });
  }

  if (currentPlayer && currentPlayer.nickname && currentPlayer.nickname.toLowerCase() === nick.toLowerCase()) {
    currentPlayer.score = Math.max(Number(currentPlayer.score || 0), incScore);
    if (payload.streak !== undefined) currentPlayer.streak = payload.streak;
    const scoreVal = document.getElementById('player-score-val');
    if (scoreVal) scoreVal.textContent = currentPlayer.score;
  }

  playersLeaderboard.sort((a, b) => (b.cumulative_score || b.score || 0) - (a.cumulative_score || a.score || 0));
  renderLeaderboard();
}

function mergeIncomingLeaderboard(list) {
  if (!Array.isArray(list)) return;
  const valid = list
    .filter(p => p && p.nickname && !isFictitiousPlayer(p.nickname))
    .map(p => ({
      ...p,
      score: Number(p.score ?? p.cumulative_score ?? 0),
      cumulative_score: Number(p.score ?? p.cumulative_score ?? 0),
    }));

  valid.forEach(incoming => {
    const idx = playersLeaderboard.findIndex(p => p.nickname.toLowerCase() === incoming.nickname.toLowerCase());
    if (idx >= 0) {
      playersLeaderboard[idx] = {
        ...playersLeaderboard[idx],
        ...incoming,
        score: Math.max(Number(playersLeaderboard[idx].score || 0), Number(incoming.score || 0)),
        cumulative_score: Math.max(Number(playersLeaderboard[idx].cumulative_score || 0), Number(incoming.cumulative_score || 0)),
        is_connected: incoming.is_connected !== false,
      };
    } else {
      playersLeaderboard.push(incoming);
    }
  });

  if (currentPlayer && currentPlayer.nickname && !isFictitiousPlayer(currentPlayer.nickname)) {
    const myIdx = playersLeaderboard.findIndex(p => p.nickname.toLowerCase() === currentPlayer.nickname.toLowerCase());
    if (myIdx >= 0) {
      const topScore = Math.max(
        Number(currentPlayer.score || 0),
        Number(playersLeaderboard[myIdx].score || 0),
        Number(playersLeaderboard[myIdx].cumulative_score || 0)
      );
      currentPlayer.score = topScore;
      playersLeaderboard[myIdx].score = topScore;
      playersLeaderboard[myIdx].cumulative_score = topScore;
      const scoreVal = document.getElementById('player-score-val');
      if (scoreVal) scoreVal.textContent = topScore;
    } else {
      playersLeaderboard.push({
        id: currentPlayer.nickname,
        player_uid: currentPlayer.nickname,
        room_code: currentRoomCode,
        nickname: currentPlayer.nickname,
        score: Number(currentPlayer.score ?? 0),
        cumulative_score: Number(currentPlayer.score ?? 0),
        streak: currentPlayer.streak || 0,
        is_connected: true
      });
    }
  }

  playersLeaderboard.sort((a, b) => (b.cumulative_score || b.score || 0) - (a.cumulative_score || a.score || 0));
  renderLeaderboard();
}

function onGamePaused(payload) {
  isAutomatedEngineRunning = false;
  currentGameState = 'PAUSED';
  pausedHostEngineState = hostEngineState || 'QUESTION_ACTIVE';
  pausedQuestionData = currentQuestionData;
  pausedQuestionIndex = currentQuestionIndex;
  pausedRound = currentRound;
  if (payload?.remaining_question_seconds) {
    pausedRemainingQuestionSeconds = Number(payload.remaining_question_seconds);
  } else if (timerEndsAtGlobalMs > Date.now()) {
    pausedRemainingQuestionSeconds = Math.max(1, Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000));
  } else if (remainingTimerSeconds > 0) {
    pausedRemainingQuestionSeconds = remainingTimerSeconds;
  }
  timerEndsAtGlobalMs = 0;
  hostTargetEpochMs = 0;
  clearInterval(countdownInterval);
  clearInterval(modalCountdownInterval);
  clearInterval(tvNextQCountdownInterval);
  clearInterval(winnerCountdownInterval);
  clearInterval(playerInterQuestionInterval);
  updateHostEngineUI('PAUSED');
  syncTvSignageDisplay();

  const tvTimerVal = document.getElementById('tv-timer-val');
  if (tvTimerVal) tvTimerVal.textContent = 'PAUSED';
  const playerTimerVal = document.getElementById('player-timer-val');
  if (playerTimerVal) playerTimerVal.textContent = 'PAUSED';
  const playerStatusBadge = document.getElementById('player-status-badge');
  if (playerStatusBadge) playerStatusBadge.textContent = 'GAME PAUSED';
  updatePlayerHeaderCard(currentRound, null, 'Game Paused');
}

function onGameResuming(payload) {
  currentGameState = 'IN PROGRESS';
  updateHostEngineUI('IN PROGRESS');
  syncTvSignageDisplay();
  if (payload?.round_number || payload?.roundNumber) {
    currentRound = Number(payload.round_number || payload.roundNumber);
  }
  if (payload?.remaining_question_seconds) {
    pausedRemainingQuestionSeconds = Number(payload.remaining_question_seconds);
  }

  const rawStarts = payload?.starts_at_epoch_ms || payload?.starts_at;
  const startsAt = rawStarts ? Number(rawStarts) : (Date.now() + 10000);

  clearInterval(countdownInterval);
  const updateResumeTick = () => {
    const rem = Math.max(0, Math.ceil((startsAt - Date.now()) / 1000));
    const tvTimerVal = document.getElementById('tv-timer-val');
    if (tvTimerVal && currentGameState !== 'QUESTION_ACTIVE') {
      tvTimerVal.textContent = rem > 0 ? `${rem}s` : 'GO!';
    }
    const playerTimerVal = document.getElementById('player-timer-val');
    if (playerTimerVal && currentGameState !== 'QUESTION_ACTIVE') {
      playerTimerVal.textContent = rem > 0 ? `${rem}s` : 'GO!';
    }
    const playerStatusBadge = document.getElementById('player-status-badge');
    if (playerStatusBadge && currentGameState !== 'QUESTION_ACTIVE') {
      playerStatusBadge.textContent = rem > 0 ? `RESUMING IN ${rem}s` : 'RESUMING NOW';
    }
    updatePlayerHeaderCard(currentRound, null, rem > 0 ? `Resuming in ${rem}s` : 'Resuming...');
    if (rem <= 0) {
      clearInterval(countdownInterval);
    }
  };
  updateResumeTick();
  countdownInterval = setInterval(updateResumeTick, 1000);
}

// RESET GAME -> REVERT TO ROTATING PROMO CAROUSEL
function onGameReset() {
  playersLeaderboard = [];
  selectedGenreQueue = [];
  currentRound = 1;
  currentQuestionIndex = 0;
  pausedHostEngineState = 'IDLE';
  pausedRemainingQuestionSeconds = 0;
  pausedQuestionData = null;
  pausedQuestionIndex = 0;
  pausedRound = 1;
  updateGenreQueueUI();
  renderLeaderboard();
  currentGameState = 'LOBBY';
  playerChoiceSubmitted = null;
  isCurrentQuestionScored = false;
  lastScoredQuestionKey = null;
  lastFanfareCelebrationKey = null;
  lastFanfarePlayEpoch = 0;
  hideResultModal();
  hideWinnerModals();
  hideInterQuestionCountdown();
  clearInterval(preGameCountdownInterval);
  const playerTimerVal = document.getElementById('player-timer-val');
  if (playerTimerVal) {
    playerTimerVal.textContent = selectedQuestionDuration || 20;
  }
  const btnTvBack = document.getElementById('btn-tv-back');
  if (btnTvBack) btnTvBack.classList.remove('question-hidden');

  // Reset Host Mobile Stage Card
  const hostStageBadge = document.getElementById('host-stage-badge');
  const hostStageQCounter = document.getElementById('host-stage-q-counter');
  const hostLiveGenrePill = document.getElementById('host-live-genre-pill');
  const hostLiveQText = document.getElementById('host-live-q-text');
  const hostTimerFill = document.getElementById('host-timer-progress-fill');
  const hostTimerSecs = document.getElementById('host-live-timer-secs');
  const btnSkip = document.getElementById('btn-skip-question');

  if (hostStageBadge) {
    hostStageBadge.className = 'stage-status-indicator';
    hostStageBadge.textContent = '🔴 LOBBY STAGE';
  }
  if (hostStageQCounter) {
    hostStageQCounter.textContent = 'Ready to Launch Round 1';
  }
  if (hostLiveGenrePill) {
    hostLiveGenrePill.textContent = '⚡ Auto Select / General Trivia';
  }
  if (hostLiveQText) {
    hostLiveQText.textContent = 'Game is waiting in lobby. Tap "▶️ Start Game" below to launch Round 1 on TV and player phones!';
  }
  if (hostTimerFill) hostTimerFill.style.width = '100%';
  if (hostTimerSecs) hostTimerSecs.textContent = `${selectedQuestionDuration}s`;

  const hostAnswerGrid = document.getElementById('host-live-answer-grid');
  if (hostAnswerGrid) hostAnswerGrid.classList.add('hidden');

  ['A', 'B', 'C', 'D'].forEach(letter => {
    const card = document.getElementById(`host-ans-${letter}`);
    const txt = document.getElementById(`host-ans-text-${letter}`);
    if (txt) txt.textContent = `Option ${letter}`;
    if (card) card.classList.remove('correct-key');
  });

  renderHostPlayersRoster();

  const btnPromo = document.getElementById('btn-tv-toggle-promo');
  const btnLive = document.getElementById('btn-tv-toggle-live');
  if (btnPromo) btnPromo.classList.add('active');
  if (btnLive) btnLive.classList.remove('active');

  const tvNextQBanner = document.getElementById('tv-next-q-banner');
  if (tvNextQBanner) tvNextQBanner.classList.add('hidden');
  clearInterval(tvNextQCountdownInterval);
  const tvTimerSublabel = document.getElementById('tv-timer-sublabel');
  if (tvTimerSublabel) tvTimerSublabel.classList.add('hidden');

  const tvPromoScreen = document.getElementById('tv-promo-screen');
  const tvAdScreen = document.getElementById('tv-ad-signage-screen');
  const tvLiveGrid = document.getElementById('tv-live-grid');

  if (tvLiveGrid) tvLiveGrid.classList.add('hidden');

  const allSlides = getAllActiveAdSlides();
  if (isAdModeActive && allSlides && allSlides.length > 0) {
    if (tvPromoScreen) tvPromoScreen.classList.add('hidden');
    if (tvAdScreen) tvAdScreen.classList.remove('hidden');
    startTvAdSignageRotation();
  } else {
    if (tvAdScreen) tvAdScreen.classList.add('hidden');
    stopTvAdSignageRotation();
    if (tvPromoScreen) tvPromoScreen.classList.remove('hidden');
    startPromoCarouselRotation();
  }
}

// 9. CLEAN LEADERBOARD RENDER WITHOUT CLUTTERED TEXT BADGES
function renderLeaderboard() {
  renderHostPlayersRoster();
  const list = document.getElementById('tv-leaderboard-list');
  if (!list) return;

  // Filter out any fictitious players, ensuring all real players (even with 0 pts) remain visible
  playersLeaderboard = playersLeaderboard.filter(p => p && p.nickname && !isFictitiousPlayer(p.nickname));

  playersLeaderboard.sort((a, b) => {
    const scoreA = Number(a.score ?? a.cumulative_score ?? 0);
    const scoreB = Number(b.score ?? b.cumulative_score ?? 0);
    if (scoreB !== scoreA) return scoreB - scoreA;
    return (a.nickname || '').localeCompare(b.nickname || '');
  });

  if (playersLeaderboard.length === 0) {
    list.innerHTML = `<li class="lb-empty">No players connected yet...</li>`;
    return;
  }

  list.innerHTML = playersLeaderboard.map((p, index) => {
    const topClass = index < 3 ? `top-${index + 1}` : '';
    const displayScore = Number(p.score ?? p.cumulative_score ?? 0);
    return `
      <li class="lb-item ${topClass}">
        <div style="display:flex; align-items:center;">
          <span class="lb-rank">#${index + 1}</span>
          <span>${escapeHtml(p.nickname)}</span>
        </div>
        <span class="lb-score">${displayScore} pts</span>
      </li>
    `;
  }).join('');
}

function startLeaderboardAutoScroll() {
  clearInterval(lbScrollInterval);
  let scrollOffset = 0;

  lbScrollInterval = setInterval(() => {
    const list = document.getElementById('tv-leaderboard-list');
    if (!list) return;

    if (playersLeaderboard.length > 4) {
      const maxScroll = (playersLeaderboard.length - 4) * 52;
      scrollOffset += 1.2;

      if (scrollOffset >= maxScroll + 24) {
        scrollOffset = 0;
      }

      list.style.transform = `translateY(-${scrollOffset}px)`;
    } else {
      list.style.transform = `translateY(0px)`;
    }
  }, 100);
}

function decodeHtmlEntities(text) {
  if (!text) return '';
  let str = String(text);

  const entityMap = {
    '&percnt;': '%',
    '&quot;': '"',
    '&#039;': "'",
    '&#39;': "'",
    '&apos;': "'",
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&deg;': '°',
    '&plusmn;': '±',
    '&ndash;': '–',
    '&mdash;': '—',
    '&lsquo;': '‘',
    '&rsquo;': '’',
    '&ldquo;': '“',
    '&rdquo;': '”',
    '&hellip;': '…',
    '&sup2;': '²',
    '&sup3;': '³',
    '&frac12;': '½',
    '&frac14;': '¼',
    '&frac34;': '¾',
    '&eacute;': 'é',
    '&Eacute;': 'É',
    '&aacute;': 'á',
    '&iacute;': 'í',
    '&oacute;': 'ó',
    '&uacute;': 'ú',
    '&ntilde;': 'ñ',
    '&uuml;': 'ü',
    '&ouml;': 'ö',
    '&auml;': 'ä',
    '&copy;': '©',
    '&reg;': '®',
    '&trade;': '™',
    '&euro;': '€',
    '&pound;': '£',
    '&yen;': '¥',
    '&cent;': '¢'
  };

  for (const [entity, replacement] of Object.entries(entityMap)) {
    str = str.split(entity).join(replacement);
  }

  // Decimal entities: &#37; -> %, &#176; -> °, etc.
  str = str.replace(/&#(\d+);/g, (match, dec) => {
    const code = parseInt(dec, 10);
    return code && code > 0 && code <= 0x10FFFF ? String.fromCharCode(code) : match;
  });

  // Hex entities: &#x25; -> %, etc.
  str = str.replace(/&#x([0-9a-fA-F]+);/gi, (match, hex) => {
    const code = parseInt(hex, 16);
    return code && code > 0 && code <= 0x10FFFF ? String.fromCharCode(code) : match;
  });

  return str;
}

function escapeHtml(text) {
  return text.replace(/[&<>"']/g, function(m) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[m];
  });
}

// Execute app initializer after full script and DOM are ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initApp);
} else {
  initApp();
}
