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
let selectedQuestionDuration = 20; // Default 20 seconds
let selectedInterRoundDuration = parseInt(safeStorage.getItem('bar_trivia_inter_round_duration') || '60', 10); // 30, 60 (Default), 120, 180, 240, 300, 600
let selectedDifficulty = 'Standard'; // Kids, Beginner, Standard, Advanced
let selectedGenreQueue = []; // Up to 10 genres in order
let currentVenueName = safeStorage.getItem('bar_trivia_venue_name') || "OUR PUB";
let customBarLogoUrl = safeStorage.getItem('bar_trivia_logo_url') || null;
let isAutomatedEngineRunning = false;
let autoEngineTimeout = null;
let countdownInterval = null;
let modalCountdownInterval = null;
let tvNextQCountdownInterval = null;
let winnerCountdownInterval = null;
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

// Ad Display Signage Mode State
let isAdModeActive = safeStorage.getItem('bar_trivia_ad_mode_active') === 'true';
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
let isSoundEffectsEnabled = safeStorage.getItem('bar_trivia_sound_enabled') !== 'false';

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
  const ctx = audioCtx;

  if (!isSoundEffectsEnabled) {
    if (btnTvSound) {
      btnTvSound.className = 'tv-toggle-btn tv-sound-toggle-btn sound-off';
      btnTvSound.textContent = '🔇 Sound OFF';
      btnTvSound.setAttribute('title', 'Sound effects are muted. Click to enable.');
    }
    if (banner) banner.classList.add('hidden');
    return;
  }

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

function playSound(type) {
  const param = arguments[1];
  if (!isSoundEffectsEnabled) return;
  const ctx = getAudioContext();
  if (!ctx) return;

  const executePlay = () => {
    try {
      const now = Math.max(ctx.currentTime, 0.005);

      if (type === 'tick' || type === 'tick_tock') { // if (type === 'tick')
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
      } else if (type === 'tap') {
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
      } else if (type === 'question_start' || type === 'start') {
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
      } else if (type === 'correct' || type === 'clapping_fanfare') { // if (type === 'correct')
        // CLAPPING FANFARE: Layered Crowd Applause + Celebratory Brass Fanfare Chords
        // Layer 1: Crowd Applause (18 staggered acoustic handclaps)
        const clapDelays = [
          0, 0.04, 0.09, 0.14, 0.19, 0.25, 0.31, 0.38, 
          0.45, 0.53, 0.61, 0.70, 0.80, 0.90, 1.01, 1.12, 1.23, 1.34
        ];
        clapDelays.forEach((delay, idx) => {
          const clapTime = now + delay + (Math.sin(idx * 7) * 0.015);
          const clapLen = Math.floor(ctx.sampleRate * 0.022);
          const clapBuf = ctx.createBuffer(1, clapLen, ctx.sampleRate);
          const cData = clapBuf.getChannelData(0);
          for (let j = 0; j < clapLen; j++) {
            cData[j] = (Math.random() * 2 - 1) * Math.exp(-j / (ctx.sampleRate * 0.005));
          }
          const cSrc = ctx.createBufferSource();
          cSrc.buffer = clapBuf;
          const cFilter = ctx.createBiquadFilter();
          cFilter.type = 'bandpass';
          cFilter.frequency.setValueAtTime(1100 + ((idx % 5) * 220), clapTime);
          cFilter.Q.setValueAtTime(3.5, clapTime);
          const cGain = ctx.createGain();
          const vol = 0.24 + ((idx % 3) * 0.06);
          cGain.gain.setValueAtTime(vol, clapTime);
          cGain.gain.linearRampToValueAtTime(0.0001, clapTime + 0.022);
          cSrc.connect(cFilter);
          cFilter.connect(cGain);
          cGain.connect(ctx.destination);
          cSrc.start(clapTime);
        });

        // Layer 2: Celebratory Brass Fanfare Progression
        // G4 (392Hz) -> C5 (523Hz) -> E5 (659Hz) -> G5 (784Hz) -> High C Major Chord Finale
        const fanfareNotes = [
          { f: 392.00, t: 0.00, d: 0.12, g: 0.35 },
          { f: 523.25, t: 0.11, d: 0.12, g: 0.38 },
          { f: 659.25, t: 0.23, d: 0.14, g: 0.40 },
          { f: 783.99, t: 0.36, d: 0.16, g: 0.42 },
          // Finale Grand Chord (sustained through applause)
          { f: 523.25, t: 0.52, d: 0.85, g: 0.36 },
          { f: 659.25, t: 0.52, d: 0.85, g: 0.36 },
          { f: 783.99, t: 0.52, d: 0.85, g: 0.38 },
          { f: 1046.50, t: 0.52, d: 0.85, g: 0.40 },
        ];

        fanfareNotes.forEach(n => {
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
      } else if (type === 'wrong') {
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
      } else if (type === 'buzz') {
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
      } else if (type === 'fanfare') { // if (type === 'fanfare')
        // Celebratory clapping fanfare for round victories
        const clapDelays = [0, 0.05, 0.11, 0.18, 0.26, 0.35, 0.45, 0.56, 0.68, 0.81, 0.95, 1.10, 1.25];
        clapDelays.forEach((delay, idx) => {
          const clapTime = now + delay;
          const clapLen = Math.floor(ctx.sampleRate * 0.022);
          const clapBuf = ctx.createBuffer(1, clapLen, ctx.sampleRate);
          const cData = clapBuf.getChannelData(0);
          for (let j = 0; j < clapLen; j++) {
            cData[j] = (Math.random() * 2 - 1) * Math.exp(-j / (ctx.sampleRate * 0.005));
          }
          const cSrc = ctx.createBufferSource();
          cSrc.buffer = clapBuf;
          const cFilter = ctx.createBiquadFilter();
          cFilter.type = 'bandpass';
          cFilter.frequency.setValueAtTime(1200 + ((idx % 4) * 200), clapTime);
          cFilter.Q.setValueAtTime(3.5, clapTime);
          const cGain = ctx.createGain();
          cGain.gain.setValueAtTime(0.24, clapTime);
          cGain.gain.linearRampToValueAtTime(0.0001, clapTime + 0.022);
          cSrc.connect(cFilter);
          cFilter.connect(cGain);
          cGain.connect(ctx.destination);
          cSrc.start(clapTime);
        });

        [ { f: 523.25, t: 0, d: 0.16 }, { f: 659.25, t: 0.12, d: 0.18 }, { f: 783.99, t: 0.24, d: 0.22 }, { f: 1046.50, t: 0.36, d: 0.70 } ].forEach(n => {
          const osc = ctx.createOscillator();
          const gain = ctx.createGain();
          osc.type = 'triangle';
          osc.frequency.setValueAtTime(n.f, now + n.t);
          gain.gain.setValueAtTime(0.0001, now + n.t);
          gain.gain.linearRampToValueAtTime(0.36, now + n.t + 0.02);
          gain.gain.linearRampToValueAtTime(0.0001, now + n.t + n.d);
          osc.connect(gain);
          gain.connect(ctx.destination);
          osc.start(now + n.t);
          osc.stop(now + n.t + n.d);
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
  isSoundEffectsEnabled = Boolean(enabled);
  safeStorage.setItem('bar_trivia_sound_enabled', String(isSoundEffectsEnabled));
  const toggleSound = document.getElementById('host-toggle-sound');
  if (toggleSound) toggleSound.checked = isSoundEffectsEnabled;
  updateTvAudioUI();

  if (shouldBroadcast) {
    const payload = { isSoundEffectsEnabled };
    try {
      channel.postMessage({ type: 'SOUND_TOGGLED', payload });
      broadcastRealtimeEvent('sound_toggled', payload);
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
let hostEngineState = 'IDLE'; // 'PRE_GAME', 'QUESTION_ACTIVE', 'QUESTION_REVIEW', 'ROUND_SUMMARY'
let hostHeartbeatInterval = null;

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

function loadInitialPlayers() {
  const normRoom = (currentRoomCode || 'TRIV').toUpperCase();

  // Purge any fictitious / host users from memory
  playersLeaderboard = playersLeaderboard.filter(p => p && p.nickname && !isFictitiousPlayer(p.nickname));

  try {
    supabase.from('players')
      .select('*')
      .or(`room_code.eq.${normRoom},room_code.eq.TRIV`)
      .order('cumulative_score', { ascending: false })
      .then(({ data, error }) => {
        if (!error && data) {
          const realPlayers = data.filter(p => !isFictitiousPlayer(p.nickname));
          playersLeaderboard = realPlayers.map(p => ({
            id: p.id || p.nickname,
            player_uid: p.player_uid || p.nickname,
            room_code: normRoom,
            nickname: p.nickname,
            score: Number(p.cumulative_score ?? p.score ?? 0),
            cumulative_score: Number(p.cumulative_score ?? p.score ?? 0),
            streak: p.streak || 0,
            is_connected: p.is_connected !== false
          }));
          renderLeaderboard();
          updateHostEngineUI(isAutomatedEngineRunning ? 'IN PROGRESS' : 'NOT STARTED');
        }
      }).catch((err) => {
        console.warn('[Leaderboard] Load players error:', err);
      });
  } catch (_) {}
}
window.loadInitialPlayers = loadInitialPlayers;

// MAIN APP INITIALIZER
function initApp() {
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
      const remainingSecs = timerEndsAtGlobalMs 
        ? Math.max(0, Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000))
        : remainingTimerSeconds;

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

      const remainingSecs = timerEndsAtGlobalMs 
        ? Math.max(0, Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000))
        : remainingTimerSeconds;

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
  'starts_at_epoch_ms',
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
  const sent = Number(payload.timestamp || payload.sent_at_epoch_ms || 0);
  if (!sent) return payload;
  const skew = Date.now() - sent;
  if (Math.abs(skew) < 1500) return payload;
  const out = { ...payload };
  SENDER_EPOCH_KEYS.forEach(key => {
    const v = Number(out[key]);
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
    currentRound = Math.max(currentRound, rNum);
  }
  updatePlayerHeaderCard(currentRound, null, `Starting in ${countdownSecs}s`);

  hideResultModal();
  hideWinnerModals();
  hideInterQuestionCountdown();

  // If in TV view, automatically transition from rotating promo/ads to live stage
  const tvPromoScreen = document.getElementById('tv-promo-screen');
  const tvAdScreen = document.getElementById('tv-ad-signage-screen');
  const tvLiveGrid = document.getElementById('tv-live-grid');
  const btnPromo = document.getElementById('btn-tv-toggle-promo');
  const btnLive = document.getElementById('btn-tv-toggle-live');
  if (tvPromoScreen) tvPromoScreen.classList.add('hidden');
  if (tvAdScreen) tvAdScreen.classList.add('hidden');
  stopTvAdSignageRotation();
  if (tvLiveGrid) tvLiveGrid.classList.remove('hidden');
  if (btnPromo) btnPromo.classList.remove('active');
  if (btnLive) btnLive.classList.add('active');

  const tvCategory = document.getElementById('tv-category');
  const tvQuestionText = document.getElementById('tv-question-text');
  if (tvCategory) tvCategory.textContent = '🚀 GAME STARTING';
  if (tvQuestionText) tvQuestionText.textContent = `Get ready! Round ${currentRound} starts in ${countdownSecs} seconds...`;

  const playerQuestionText = document.getElementById('player-question-text');
  if (playerQuestionText) {
    playerQuestionText.textContent = `🎮 ROUND ${currentRound} STARTING IN ${countdownSecs} SECONDS! Get ready...`;
  }
  const playerStatusBadge = document.getElementById('player-status-badge');
  if (playerStatusBadge) {
    playerStatusBadge.className = 'status-badge status-active';
    playerStatusBadge.innerHTML = `<span id="status-icon">🚀</span> ROUND ${currentRound} IN ${countdownSecs}s`;
  }
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
    text: qObj.text || qObj.question_text || payload.question_text || payload.text || payload.question || '',
    options: {
      A: optA,
      B: optB,
      C: optC,
      D: optD,
    },
    correct: correct,
  };

  const isSameQuestion = currentQuestionData && (
    (currentQuestionData.id && questionData.id && currentQuestionData.id === questionData.id) ||
    (currentQuestionData.text && questionData.text && currentQuestionData.text === questionData.text)
  );

  const durationSeconds = Number(payload.duration_seconds || payload.time_limit_seconds || payload.durationSeconds) || selectedQuestionDuration || 20;
  const qIndex = Number(payload.question_index || payload.questionIndex) || 1;
  currentQuestionIndex = qIndex;
  const rFromPayload = Number(payload.round_number || payload.roundNumber);
  const roundNum = (rFromPayload && rFromPayload > 0)
    ? rFromPayload
    : (payload.cumulative_question_index ? Math.floor((payload.cumulative_question_index - 1) / 10) + 1 : (currentRound || 1));
  currentRound = roundNum;
  const qNumInRound = Number(payload.question_number_in_round || payload.questionNumberInRound) || (((qIndex - 1) % 10) + 1);

  const rawTargetEpoch = payload.timer_ends_at_epoch_ms || payload.timerEndsAtMs || payload.timer_ends_at || payload.timerEndsAtEpochMs;
  const now = Date.now();
  if (rawTargetEpoch && Number(rawTargetEpoch) > now) {
    timerEndsAtGlobalMs = Number(rawTargetEpoch);
  } else if (!isSameQuestion || !timerEndsAtGlobalMs) {
    timerEndsAtGlobalMs = now + durationSeconds * 1000;
  }
  const remainingSecs = Math.max(0, Math.ceil((timerEndsAtGlobalMs - now) / 1000));

  if (isSameQuestion && playerChoiceSubmitted !== null) {
    // Current question is already active and player has already submitted an answer.
    // Preserve their answer selection and do not re-enable buttons.
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
    difficulty: questionData.difficulty,
  });
}

function handleIncomingTimerExpired(rawPayload) {
  const payload = rawPayload?.payload || rawPayload || {};
  console.log('[Realtime] Processing timer_expired:', payload);

  const nextEpoch = payload.next_question_starts_at_epoch_ms || 
                    payload.nextQuestionStartsAtEpochMs || 
                    (Date.now() + 10000);
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
  } else if (normEvent === 'timer_expired') {
    handleIncomingTimerExpired(payload);
  } else if (normEvent === 'round_completed' || normEvent === 'round_winner') {
    const nextR = Number(payload?.next_round || payload?.nextRound || ((payload?.round_number || currentRound) + 1));
    currentRound = Math.max(currentRound, nextR);
    const list = payload?.top3Winners || payload?.top_3_winners || payload?.top3_winners || [];
    onRoundWinner({ top3Winners: list, delaySeconds: selectedInterRoundDuration || 60, roundNumber: currentRound });
  } else if (normEvent === 'game_paused') {
    isAutomatedEngineRunning = false;
    currentGameState = 'PAUSED';
    updateHostEngineUI('PAUSED');
  } else if (normEvent === 'game_resuming') {
    currentGameState = 'IN PROGRESS';
    updateHostEngineUI('IN PROGRESS');
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
        const rem = Math.max(1, Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000));
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
          duration_seconds: rem,
          timer_ends_at_epoch_ms: timerEndsAtGlobalMs,
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
  } else if (normEvent === 'sound_toggled') {
    if (payload && payload.isSoundEffectsEnabled !== undefined) {
      setSoundEffectsEnabled(Boolean(payload.isSoundEffectsEnabled), false);
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
      isAutomatedEngineRunning = false;
      currentGameState = 'PAUSED';
      updateHostEngineUI('PAUSED');
    } else if (type === 'GAME_RESUMING') {
      currentGameState = 'IN PROGRESS';
      updateHostEngineUI('IN PROGRESS');
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
    } else if (type === 'SOUND_TOGGLED') {
      if (payload && payload.isSoundEffectsEnabled !== undefined) {
        setSoundEffectsEnabled(Boolean(payload.isSoundEffectsEnabled), false);
      }
    }
  };
}

function onStateSyncResponse(payload) {
  if (!payload) return;

  if (payload.isSoundEffectsEnabled !== undefined) {
    setSoundEffectsEnabled(Boolean(payload.isSoundEffectsEnabled), false);
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
    selectedDifficulty = payload.selectedDifficulty || 'Standard';
    timerEndsAtGlobalMs = payload.timerEndsAtGlobalMs || 0;

    const remainingSecs = payload.timerEndsAtGlobalMs 
      ? Math.max(0, Math.ceil((payload.timerEndsAtGlobalMs - Date.now()) / 1000))
      : payload.totalTimerDuration;

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
    chip.addEventListener('click', (e) => {
      e.preventDefault();
      if (isAutomatedEngineRunning) return;

      timerChips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');

      const parsedSecs = parseInt(chip.getAttribute('data-timer'), 10);
      if (!isNaN(parsedSecs)) {
        selectedQuestionDuration = parsedSecs;
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

  btnStartAuto?.addEventListener('click', async () => {
    requestScreenWakeLock();
    if (isAutomatedEngineRunning) return;
    isAutomatedEngineRunning = true;
    currentRoundQuestions = [];
    if (currentGameState === 'LOBBY' || currentGameState === 'NOT_STARTED' || currentQuestionIndex === 0) {
      currentQuestionIndex = 0;
      currentRound = 1;
    }
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
    if (isAutomatedEngineRunning) {
      // Transition from RUNNING -> PAUSED
      isAutomatedEngineRunning = false;
      stopHostHeartbeatLoop();
      clearTimeout(autoEngineTimeout);
      clearInterval(countdownInterval);
      clearInterval(modalCountdownInterval);
      clearInterval(tvNextQCountdownInterval);
      clearInterval(winnerCountdownInterval);
      clearMockPlayerTimeouts();
      currentGameState = 'PAUSED';
      updateHostEngineUI('PAUSED');

      channel.postMessage({ type: 'GAME_PAUSED', payload: { roomCode: currentRoomCode } });
      broadcastRealtimeEvent('game_paused', { room_code: currentRoomCode });

      try {
        supabase.from('game_sessions').upsert({
          room_code: currentRoomCode,
          status: 'paused',
          current_round: currentRound,
          current_question_index: currentQuestionIndex,
          updated_at: new Date().toISOString()
        }, { onConflict: 'room_code' }).catch(() => {});
      } catch (_) {}
    } else {
      // Transition from PAUSED -> RESUME
      isAutomatedEngineRunning = true;
      currentGameState = 'IN PROGRESS';
      updateHostEngineUI('IN PROGRESS');
      startHostHeartbeatLoop();

      const resumeSecs = 10;
      const startsAtMs = Date.now() + (resumeSecs * 1000);
      channel.postMessage({
        type: 'GAME_RESUMING',
        payload: {
          roomCode: currentRoomCode,
          starts_at_epoch_ms: startsAtMs,
          remaining_question_seconds: selectedQuestionDuration
        }
      });
      broadcastRealtimeEvent('game_resuming', {
        room_code: currentRoomCode,
        starts_at_epoch_ms: startsAtMs,
        remaining_question_seconds: selectedQuestionDuration
      });

      try {
        supabase.from('game_sessions').upsert({
          room_code: currentRoomCode,
          status: 'resuming',
          starts_at: startsAtMs,
          current_round: currentRound,
          current_question_index: currentQuestionIndex,
          updated_at: new Date().toISOString()
        }, { onConflict: 'room_code' }).catch(() => {});
      } catch (_) {}

      clearTimeout(autoEngineTimeout);
      autoEngineTimeout = setTimeout(() => {
        checkHostEngineTick();
      }, resumeSecs * 1000);
    }
  });

  btnResetGame?.addEventListener('click', () => {
    isAutomatedEngineRunning = false;
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
        const now = Date.now();
        if (session.status === 'pre_game_countdown') {
          const startsAt = session.starts_at || now;
          if (startsAt > now - 45000) {
            isAutomatedEngineRunning = true;
            currentGameState = 'PRE_GAME';
            currentRound = session.current_round || session.round_number || currentRound || 1;
            updateHostEngineUI('IN PROGRESS');
          }
        } else if (session.status === 'question_active') {
          const endsAt = session.timer_ends_at || (now + 20000);
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
        } else if (session.status === 'paused') {
          if (currentGameState !== 'QUESTION_ACTIVE' && currentGameState !== 'PRE_GAME') {
            isAutomatedEngineRunning = false;
            currentGameState = 'PAUSED';
            updateHostEngineUI('PAUSED');
          }
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
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      resolve([{
        id: `slide_${Date.now()}_1_${Math.random().toString(36).substring(2, 6)}`,
        name: file.name,
        dataUrl: e.target.result,
        type: 'image',
        page: 1,
        totalPages: 1,
        timestamp: Date.now()
      }]);
    };
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
  ctx.font = "900 30px 'Outfit', 'Inter', sans-serif";
  ctx.fillStyle = '#ffffff';
  ctx.textAlign = 'left';
  ctx.fillText('BRING THE EXCITEMENT OF PUB TRIVIA HOME!', 110, botY + 102);

  // Explanatory Paragraph
  const homeDesc = 'No pens, no paper answer sheets, and no manual score calculation! Hook up your laptop, tablet, or smart TV, gather your friends and family, and start playing in under 60 seconds.';
  wrapText(homeDesc, 110, botY + 140, leftW - 80, 26, '#94a3b8', "500 17px 'Inter', sans-serif");

  // 4 Event Chips
  const eventChips = [
    { label: '👨‍👩‍👧‍👦 Family Game Nights', stroke: 'rgba(0, 230, 118, 0.5)', bg: 'rgba(0, 230, 118, 0.1)' },
    { label: '🍻 Friends & House Parties', stroke: 'rgba(255, 214, 0, 0.5)', bg: 'rgba(255, 214, 0, 0.1)' },
    { label: '🏢 Office & Team Socials', stroke: 'rgba(0, 229, 255, 0.5)', bg: 'rgba(0, 229, 255, 0.1)' },
    { label: '🎉 Holiday & Birthday Parties', stroke: 'rgba(255, 0, 122, 0.5)', bg: 'rgba(255, 0, 122, 0.1)' }
  ];

  eventChips.forEach((chip, i) => {
    const chipX = 110 + (i % 2) * 520;
    const chipY = botY + 215 + Math.floor(i / 2) * 52;
    roundRect(chipX, chipY, 490, 42, 10, chip.bg, chip.stroke, 1.5);
    ctx.font = "700 15px 'Outfit', 'Inter', sans-serif";
    ctx.fillStyle = '#ffffff';
    ctx.fillText(chip.label, chipX + 18, chipY + 27);
  });

  // Footer Tagline on Left Card
  ctx.font = "600 14px 'Inter', sans-serif";
  ctx.fillStyle = 'rgba(255, 255, 255, 0.7)';
  ctx.fillText('★ Compatible with any Smart TV, Projector, Laptop, Tablet, Android Phone & iPhone ★', 110, botY + 342);

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
  if (!officialAd) return [...customAdSlides];
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
    return;
  }

  const allSlides = getAllActiveAdSlides();

  // Idle / Lobby mode:
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
    const isLiveActive = btnLive?.classList.contains('active');
    if (!isLiveActive) {
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

  const totalMs = (adSlideDurationSeconds || 10) * 1000;
  const startTime = Date.now();
  const progressFill = document.getElementById('tv-ad-progress-fill');
  if (progressFill) progressFill.style.width = '0%';

  adProgressBarInterval = setInterval(() => {
    const elapsed = Date.now() - startTime;
    const pct = Math.min(100, (elapsed / totalMs) * 100);
    if (progressFill) progressFill.style.width = `${pct}%`;
    if (elapsed >= totalMs) {
      clearInterval(adProgressBarInterval);
    }
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
  const progressFill = document.getElementById('tv-ad-progress-fill');
  if (progressFill) progressFill.style.width = '0%';
}

function displayAdSlide(index) {
  const allSlides = getAllActiveAdSlides();
  const slide = allSlides[index];
  if (!slide) return;

  const img = document.getElementById('tv-ad-slide-img');
  const counterText = document.getElementById('tv-ad-slide-counter-text');

  if (img) {
    if (!img.src || img.src === window.location.href || img.src.endsWith('/') || img.classList.contains('fading')) {
      img.src = slide.dataUrl;
      img.classList.remove('fading');
    } else {
      img.classList.add('fading');
      setTimeout(() => {
        img.src = slide.dataUrl;
        img.classList.remove('fading');
      }, 250);
    }
  }

  if (counterText) {
    counterText.textContent = `Ad ${index + 1} of ${allSlides.length}`;
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
      slidesCount: allSlides.length,
      isAdModeActive
    });
  } catch (e) {
    console.warn('Ad slides broadcast error:', e);
  }
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
  if (payload && Array.isArray(payload.slides)) {
    customAdSlides = payload.slides;
    await idbAdStorage.saveSlides(customAdSlides);
  } else {
    customAdSlides = await idbAdStorage.loadSlides();
  }
  renderHostAdGallery();
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

  // Master switch
  if (toggleAdMode) {
    toggleAdMode.checked = isAdModeActive;
    toggleAdMode.addEventListener('change', () => {
      isAdModeActive = toggleAdMode.checked;
      safeStorage.setItem('bar_trivia_ad_mode_active', String(isAdModeActive));
      broadcastAdModeChange();
      syncTvSignageDisplay();
    });
  }

  // Sound Effects toggle
  const toggleSound = document.getElementById('host-toggle-sound');
  if (toggleSound) {
    toggleSound.checked = isSoundEffectsEnabled;
    toggleSound.addEventListener('change', () => {
      setSoundEffectsEnabled(toggleSound.checked, true);
    });
  }

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
        renderHostAdGallery();
        broadcastAdSlidesUpdated();

        // Automatically toggle Ad Mode ON if it was OFF
        if (!isAdModeActive) {
          isAdModeActive = true;
          safeStorage.setItem('bar_trivia_ad_mode_active', 'true');
          if (toggleAdMode) toggleAdMode.checked = true;
          broadcastAdModeChange();
        }

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
  } catch (e) {
    console.warn('Could not load ad slides:', e);
    customAdSlides = [];
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
    btnStartAuto.disabled = isRunning;
    if (isRunning) {
      btnStartAuto.classList.add('disabled', 'btn-greyed-out');
    } else {
      btnStartAuto.classList.remove('disabled', 'btn-greyed-out');
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
    const calculatedRound = Math.floor(currentQuestionIndex / 10) + 1;
    currentRound = Math.max(currentRound, calculatedRound);
    if (Math.floor(currentQuestionIndex / 10) + 1 < currentRound) {
      currentQuestionIndex = (currentRound - 1) * 10;
    }
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
    timerEndsAtGlobalMs = Date.now() + (durationSeconds * 1000);
    hostTargetEpochMs = timerEndsAtGlobalMs;
    hostEngineState = 'QUESTION_ACTIVE';
    startHostHeartbeatLoop();

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
      timer_ends_at_epoch_ms: timerEndsAtGlobalMs,
      category: question.category || activeRoundGenre,
      genre: question.category || activeRoundGenre,
      question_text: question.text,
      option_a: question.options.A,
      option_b: question.options.B,
      option_c: question.options.C,
      option_d: question.options.D,
      options: question.options,
      correct_option: question.correct,
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
        duration_seconds: durationSeconds,
        timer_ends_at: timerEndsAtGlobalMs,
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
    autoEngineTimeout = setTimeout(() => {
      checkHostEngineTick();
    }, durationSeconds * 1000);
  } catch (loopErr) {
    console.error('[Automated Engine] Recovering from step error:', loopErr);
    setTimeout(() => {
      if (isAutomatedEngineRunning) {
        currentQuestionIndex++;
        runNextAutomatedStep();
      }
    }, 3000);
  }
}

function handleHostQuestionTimeout(question, currentRound, questionInRound) {
  if (!isAutomatedEngineRunning || hostEngineState !== 'QUESTION_ACTIVE') return;

  const reviewDurationMs = 10000; // Synchronized 10-second review: 5s result modal + 5s dedicated countdown screen
  hostTargetEpochMs = Date.now() + reviewDurationMs;

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
    game_play_mode: 'Auto',
  };

  currentGameState = 'QUESTION_REVIEW';
  hostEngineState = 'QUESTION_REVIEW';

  broadcastRealtimeEvent('timer_expired', expiredPayload);
  onTimerExpired(expiredPayload);

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
  autoEngineTimeout = setTimeout(() => {
    checkHostEngineTick();
  }, reviewDurationMs);
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
    const interRoundSecs = Math.max(5, selectedInterRoundDuration || 60);
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
      roundWinner.score = (Number(roundWinner.score ?? roundWinner.cumulative_score ?? 0)) + 20;
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

      top3 = validPlayers.slice(0, 3);
      winnerPayload = {
        roundNumber: currentRound,
        winnerName: roundWinner.nickname,
        winnerScore: roundWinner.score,
        top3Winners: top3,
        delaySeconds: interRoundSecs
      };
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
      next_round_starts_at_epoch_ms: hostTargetEpochMs,
    });
    onRoundWinner(winnerPayload);

    autoEngineTimeout = setTimeout(() => {
      checkHostEngineTick();
    }, interRoundSecs * 1000);
  } else {
    runNextAutomatedStep();
  }
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
    text: qObj.text || qObj.question_text || payload.question_text || payload.text || payload.question || '',
    options: {
      A: optA,
      B: optB,
      C: optC,
      D: optD,
    },
    correct: correct,
  };

  const roundNumber = payload.roundNumber || payload.round_number || currentRound || 1;
  currentRound = Number(roundNumber);
  const questionNumberInRound = payload.questionNumberInRound || payload.question_number_in_round || ((currentQuestionIndex % 10) + 1);
  const durationSeconds = payload.durationSeconds || payload.duration_seconds || payload.time_limit_seconds || selectedQuestionDuration || 20;
  const activeDifficulty = payload.difficulty || questionData.difficulty || selectedDifficulty || 'Standard';

  currentQuestionData = questionData;
  totalTimerDuration = durationSeconds;
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
  clearInterval(modalCountdownInterval);
  clearInterval(playerReviewInterval);

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
  const cleanQText = (questionData.text || '')
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

  // UNHIDE & START TV COUNTDOWN TIMER IMMEDIATELY
  if (tvTimerContainer) tvTimerContainer.classList.remove('hidden');
  startCountdown(totalTimerDuration);
  // Silent countdown: do not play sound until last 5 seconds (playSound('question_start') omitted during countdown)

  // Reset player answer choice state and dismiss previous result modal for new question
  playerChoiceSubmitted = null;
  isCurrentQuestionScored = false;
  hideResultModal();
  hideWinnerModals();
  hideInterQuestionCountdown();

  // Update Player Phone Display & Difficulty Pill
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
  if (pOptA) pOptA.textContent = questionData.options.A;
  const pOptB = document.getElementById('p-opt-b');
  if (pOptB) pOptB.textContent = questionData.options.B;
  const pOptC = document.getElementById('p-opt-c');
  if (pOptC) pOptC.textContent = questionData.options.C;
  const pOptD = document.getElementById('p-opt-d');
  if (pOptD) pOptD.textContent = questionData.options.D;

  if (playerStatusBadge) {
    playerStatusBadge.className = 'status-badge status-active';
    playerStatusBadge.innerHTML = `<span id="status-icon">⏱️</span> UNLOCKED`;
  }

  answerBtns.forEach(btn => {
    btn.disabled = false;
    btn.classList.remove('selected', 'unselected', 'review-correct', 'review-wrong');
    const existingBadge = btn.querySelector('.player-correct-badge');
    if (existingBadge) existingBadge.remove();
  });
}

function startCountdown(seconds) {
  clearInterval(countdownInterval);
  totalTimerDuration = seconds;
  if (!timerEndsAtGlobalMs || timerEndsAtGlobalMs <= Date.now()) {
    timerEndsAtGlobalMs = Date.now() + seconds * 1000;
  }
  remainingTimerSeconds = Math.max(0, Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000));
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

function startPlayerReviewCountdown(seconds, targetEpochMs) {
  clearInterval(playerReviewInterval);
  const targetEpoch = targetEpochMs || (Date.now() + (seconds * 1000));

  const updateBadge = () => {
    const rem = Math.max(0, Math.ceil((targetEpoch - Date.now()) / 1000));
    const playerStatusBadge = document.getElementById('player-status-badge');
    if (playerStatusBadge) {
      if (rem > 0) {
        playerStatusBadge.className = 'status-badge status-active';
        playerStatusBadge.innerHTML = `<span id="status-icon">⏳</span> <span id="status-text">NEXT QUESTION IN ${rem}s...</span>`;
      } else {
        playerStatusBadge.innerHTML = `<span id="status-icon">🚀</span> <span id="status-text">PREPARING NEXT QUESTION...</span>`;
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
  const rawCorrect = payload?.correctOption || currentQuestionData?.correct || '';
  const correctOpt = rawCorrect.toUpperCase().trim();
  const correctTextStr = payload?.correctText || `${correctOpt}) ${currentQuestionData?.options?.[correctOpt] || ''}`;

  const btnTvBack = document.getElementById('btn-tv-back');
  if (btnTvBack) btnTvBack.classList.remove('question-hidden');

  clearMockPlayerTimeouts();

  const playerStatusBadge = document.getElementById('player-status-badge');
  const answerBtns = document.querySelectorAll('.btn-answer');

  const curQ = ((currentQuestionIndex - 1) % 10) + 1;
  updatePlayerHeaderCard(currentRound, curQ, 'Review');

  // Calculate review seconds remaining for next question countdown (synchronized 15s)
  const nextEpoch = payload?.next_question_starts_at_epoch_ms || 
                    payload?.nextQuestionStartsAtEpochMs || 
                    (Date.now() + 15000);
  const reviewSeconds = Math.max(1, Math.ceil((nextEpoch - Date.now()) / 1000));

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
    hostStageQCounter.textContent = `Reviewing Answer (Next Question in ${reviewSeconds}s)`;
  }
  if (hostTimerSecs) {
    hostTimerSecs.textContent = `${reviewSeconds}s`;
  }

  startPlayerReviewCountdown(reviewSeconds, nextEpoch);

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
      tvTimerSublabel.textContent = 'Next question';
      tvTimerSublabel.classList.remove('hidden');
    }
  }

  const updateTvCountdown = () => {
    const remNextQSecs = Math.max(0, Math.ceil((nextEpoch - Date.now()) / 1000));
    if (tvNextQVal) tvNextQVal.textContent = remNextQSecs;
    if (tvTimerVal) tvTimerVal.textContent = remNextQSecs;
    if (timerProgress) {
      const ratio = remNextQSecs / 15.0;
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

  if (tvNextQBanner) {
    tvNextQBanner.classList.remove('hidden');
  }
  updateTvCountdown();
  clearInterval(tvNextQCountdownInterval);
  tvNextQCountdownInterval = setInterval(updateTvCountdown, 500);

  // ACCURATE SCORING: Evaluate answer ONLY once when timer expires
  const qIdentifier = (currentQuestionData?.id || currentQuestionData?.text || `r${currentRound}_q${currentQuestionIndex}`);
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
      currentPlayer.score += pointsEarned;
      const scoreVal = document.getElementById('player-score-val');
      if (scoreVal) scoreVal.textContent = currentPlayer.score;

      const targetPlayer = playersLeaderboard.find(p => p.nickname.toLowerCase() === currentPlayer.nickname.toLowerCase());
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
      showResultModal(true, `+${pointsEarned} PTS`, correctTextStr, randomQuote, reviewSeconds, nextEpoch);
      confetti({ particleCount: 60, spread: 80, origin: { y: 0.6 } });
    } else {
      if (currentPlayer) {
        currentPlayer.streak = 0;
      }
      const randomQuote = getRandomItem(funnyWrongQuotes);
      showResultModal(false, "0 PTS", correctTextStr, randomQuote, reviewSeconds, nextEpoch);
    }

    // Clear playerChoiceSubmitted after grading this question
    playerChoiceSubmitted = null;
  }
}

function getRandomItem(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function showResultModal(isCorrect, pointsText, correctTextStr, funnyQuote, countdownSeconds = 15, targetEpochMs = null) {
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

  if (correctTextEl) correctTextEl.textContent = correctTextStr;
  if (quote) quote.textContent = `"${funnyQuote}"`;

  const targetEpoch = targetEpochMs || (Date.now() + Math.round(countdownSeconds * 1000));

  const updateModalCountdown = () => {
    const rem = Math.max(0, Math.ceil((targetEpoch - Date.now()) / 1000));
    if (modalTimerVal) modalTimerVal.textContent = rem;
    if (rem <= 5) {
      clearInterval(modalCountdownInterval);
      hideResultModal();
      showInterQuestionCountdown(targetEpoch);
    }
  };

  updateModalCountdown();
  clearInterval(modalCountdownInterval);
  modalCountdownInterval = setInterval(updateModalCountdown, 500);

  overlay.classList.remove('hidden');
  // Tap-to-dismiss immediately transitions to dedicated countdown screen
  overlay.onclick = () => {
    clearInterval(modalCountdownInterval);
    hideResultModal();
    showInterQuestionCountdown(targetEpoch);
  };
}

let playerInterQuestionInterval = null;

function showInterQuestionCountdown(targetEpochMs) {
  hideResultModal();
  clearInterval(playerInterQuestionInterval);

  const interQScreen = document.getElementById('player-inter-question-screen');
  const timerVal = document.getElementById('player-inter-q-timer');
  const subtextVal = document.getElementById('player-inter-q-subtext');
  const qCard = document.querySelector('.player-question-card');
  const btnGrid = document.querySelector('.button-grid-2x2');

  // Immediately hide previous question and previous choices
  if (qCard) qCard.classList.add('hidden');
  if (btnGrid) btnGrid.classList.add('hidden');
  if (interQScreen) interQScreen.classList.remove('hidden');

  const updateCountdown = () => {
    const rem = Math.max(0, Math.ceil((targetEpochMs - Date.now()) / 1000));
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
      clearInterval(playerInterQuestionInterval);
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
  if (interQScreen) interQScreen.classList.add('hidden');
  if (qCard) qCard.classList.remove('hidden');
  if (btnGrid) btnGrid.classList.remove('hidden');
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

  let remWinnerSecs = payload?.delaySeconds || selectedInterRoundDuration || 60;
  const formatRoundTimer = (s) => {
    const mins = Math.floor(s / 60);
    const secs = s % 60;
    return `${mins}:${String(secs).padStart(2, '0')}`;
  };

  if (tvNextRoundTimer) tvNextRoundTimer.textContent = remWinnerSecs >= 60 ? formatRoundTimer(remWinnerSecs) : remWinnerSecs;
  if (playerWinnerTimer) playerWinnerTimer.textContent = formatRoundTimer(remWinnerSecs);

  // Also display NEXT ROUND STARTING IN..... directly on the player question card
  const playerQuestionText = document.getElementById('player-question-text');
  const playerCategoryPill = document.getElementById('player-category-pill');
  const statusText = document.getElementById('status-text');
  if (playerQuestionText) {
    playerQuestionText.innerHTML = `
      <div style="text-align:center; padding: 12px 0;">
        <div style="font-size:13px; font-weight:900; color:var(--accent-yellow); letter-spacing:1.5px; text-transform:uppercase; margin-bottom:8px;">NEXT ROUND STARTING IN.....</div>
        <div style="font-size:42px; font-weight:900; color:#fff; letter-spacing:2px;" id="player-card-round-timer">${formatRoundTimer(remWinnerSecs)}</div>
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

  clearInterval(winnerCountdownInterval);
  winnerCountdownInterval = setInterval(() => {
    remWinnerSecs--;
    const currentSecs = Math.max(0, remWinnerSecs);
    if (tvNextRoundTimer) tvNextRoundTimer.textContent = currentSecs >= 60 ? formatRoundTimer(currentSecs) : currentSecs;
    if (playerWinnerTimer) playerWinnerTimer.textContent = formatRoundTimer(currentSecs);
    const cardTimer = document.getElementById('player-card-round-timer');
    if (cardTimer) cardTimer.textContent = formatRoundTimer(currentSecs);

    if (remWinnerSecs <= 0) {
      clearInterval(winnerCountdownInterval);
      if (tvNextRoundTimer) tvNextRoundTimer.textContent = '0:00';
      if (playerWinnerTimer) playerWinnerTimer.textContent = '0:00';
      if (cardTimer) cardTimer.textContent = '0:00';
    }
  }, 1000);

  confetti({ particleCount: 120, spread: 100, origin: { y: 0.5 } });
  playSound('fanfare');
}

function hideWinnerModals() {
  const tvWinnerOverlay = document.getElementById('tv-winner-modal-overlay');
  const playerWinnerOverlay = document.getElementById('player-winner-modal-overlay');

  if (tvWinnerOverlay) tvWinnerOverlay.classList.add('hidden');
  if (playerWinnerOverlay) playerWinnerOverlay.classList.add('hidden');
  clearInterval(winnerCountdownInterval);
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
      const remSecs = timerEndsAtGlobalMs > 0
        ? Math.max(1, Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000))
        : (remainingTimerSeconds || 20);
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
          const rNum = Number(session.current_round || session.round_number || 0);
          if (rNum > 0) {
            currentRound = Math.max(currentRound, rNum);
          }
          if (session.status === 'pre_game_countdown') {
            const rem = Math.max(1, Math.ceil((session.starts_at - Date.now()) / 1000));
            handleIncomingPreGameCountdown({ countdown_seconds: rem, round_number: rNum || currentRound, genre: session.genre });
          } else if (session.status === 'question_active' && session.question_data) {
            const qData = session.question_data;
            const now = Date.now();
            const endsAt = session.timer_ends_at || (now + 20000);
            if ((endsAt - now) > -15000) {
              const sessionQIdx = session.current_question_index || 0;
              const curQIdx = currentQuestionIndex || 0;
              const qText = qData.text || qData.question || '';
              const curText = currentQuestionData ? (currentQuestionData.text || currentQuestionData.question || '') : '';
              const isNewQuestion = !currentQuestionData ||
                (sessionQIdx > 0 && sessionQIdx !== curQIdx) ||
                (qData.id && currentQuestionData.id && qData.id !== currentQuestionData.id) ||
                (qText && curText && qText !== curText) ||
                currentGameState !== 'QUESTION_ACTIVE';

              if (isNewQuestion) {
                hideResultModal();
                const sessionRound = session.current_round || session.round_number || qData.round_number || qData.roundNumber || currentRound;
                handleIncomingQuestionStart({
                  ...qData,
                  question_index: session.current_question_index || 1,
                  round_number: sessionRound,
                  roundNumber: sessionRound,
                  duration_seconds: session.duration_seconds || 20,
                  timer_ends_at_epoch_ms: session.timer_ends_at
                });
              } else {
                const qNum = ((session.current_question_index - 1) % 10) + 1;
                updatePlayerHeaderCard(currentRound, qNum);
              }
            }
          } else if (session.status === 'round_summary' || session.status === 'inter_round') {
            updatePlayerHeaderCard(currentRound, null, 'Intermission');
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
      if (player.score !== undefined || player.cumulative_score !== undefined) {
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

// RESET GAME -> REVERT TO ROTATING PROMO CAROUSEL
function onGameReset() {
  playersLeaderboard = [];
  selectedGenreQueue = [];
  currentRound = 1;
  currentQuestionIndex = 0;
  updateGenreQueueUI();
  renderLeaderboard();
  currentGameState = 'LOBBY';
  playerChoiceSubmitted = null;
  isCurrentQuestionScored = false;
  lastScoredQuestionKey = null;
  hideResultModal();
  hideWinnerModals();
  hideInterQuestionCountdown();
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
