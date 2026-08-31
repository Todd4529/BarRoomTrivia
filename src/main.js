import QRCode from 'qrcode';
import confetti from 'canvas-confetti';
import mqtt from 'mqtt';
import { createClient } from '@supabase/supabase-js';
import { fetchRealtimeTriviaQuestions, initOpenTdbToken, resetQuestionHistory, ALL_SPECIFIC_GENRES } from './triviaDatabase.js';

const SUPABASE_URL = 'https://tzdikvbvdvgjaiznqkcd.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR6ZGlrdmJ2ZHZnamFpem5xa2NkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDAxNTMwNzksImV4cCI6MjA1NTcyOTA3OX0.12k3oY1iO6wYk_hJ8e2V0n1QY-B5-v1XyPZ47_3q1W8';
const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

let mqttClient = null;

// State & Broadcast Channel
const BROADCAST_CHANNEL_NAME = 'bar_rooms_trivia_TRIV';
const channel = new BroadcastChannel(BROADCAST_CHANNEL_NAME);

const initialUrlParams = new URLSearchParams(window.location.search);
let currentRoomCode = (initialUrlParams.get('room') || initialUrlParams.get('room_id') || 'TRIV').toUpperCase();
let currentPlayer = null;
let currentQuestionIndex = 0;
let selectedQuestionDuration = 20; // Default 20 seconds
let selectedDifficulty = 'Standard'; // Kids, Beginner, Standard, Advanced
let selectedGenreQueue = []; // Up to 10 genres in order
let currentVenueName = localStorage.getItem('bar_trivia_venue_name') || "OUR PUB";
let customBarLogoUrl = localStorage.getItem('bar_trivia_logo_url') || null;
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
let mockPlayerTimeouts = [];

let remainingTimerSeconds = 0;
let totalTimerDuration = 20;
let timerEndsAtGlobalMs = 0;
let currentQuestionData = null;
let currentGameState = 'LOBBY';

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

// INITIALIZE 10 MOCK PLAYERS PLAYING IN THE BACKGROUND WITH STREAK TRACKING
const defaultMockPlayers = [
  { nickname: 'TriviaMaster99', score: 350, streak: 2 },
  { nickname: 'BeerGuru', score: 280, streak: 1 },
  { nickname: 'PubQuizPro', score: 220, streak: 0 },
  { nickname: 'BrewMaster_Joe', score: 190, streak: 1 },
  { nickname: 'HopsAndBarley', score: 170, streak: 0 },
  { nickname: 'PintSizedGenius', score: 140, streak: 3 },
  { nickname: 'WhiskeyWisdom', score: 120, streak: 0 },
  { nickname: 'BarStoolEinstein', score: 90, streak: 1 },
  { nickname: 'CiderSeeker', score: 60, streak: 0 },
  { nickname: 'TavernTactician', score: 30, streak: 0 }
];

let playersLeaderboard = [...defaultMockPlayers];

// MAIN APP INITIALIZER
function initApp() {
  initOpenTdbToken();
  initNavigation();
  initAuthView();
  initQrCodes();
  initHostControls();
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

  startPromoCarouselRotation();
  startLeaderboardAutoScroll();
  renderLeaderboard();
}

// Execute immediately when DOM is ready or completed
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initApp);
} else {
  initApp();
}

// HOST AUTHENTICATION LOGIC (Mobile & Web)
function initAuthView() {
  const form = document.getElementById('form-host-auth');
  const emailInput = document.getElementById('auth-email-input');
  const passwordInput = document.getElementById('auth-password-input');
  const btnSubmit = document.getElementById('btn-submit-auth');
  const btnToggleSignMode = document.getElementById('btn-toggle-sign-mode');
  const btnGoogle = document.getElementById('btn-oauth-google');
  const btnApple = document.getElementById('btn-oauth-apple');
  const alertBox = document.getElementById('auth-status-alert');
  const tvCodePill = document.getElementById('auth-tv-code-pill');
  const tvCodeLabel = document.getElementById('auth-tv-code-label');
  const subtitleText = document.getElementById('auth-subtitle-text');

  let isSignUpMode = false;

  // Extract device_token and user_code from query params or hash
  const urlParams = new URLSearchParams(window.location.search);
  let deviceToken = urlParams.get('device_token');
  let userCode = urlParams.get('user_code');

  if (!deviceToken && window.location.hash.includes('device_token=')) {
    const hashQuery = window.location.hash.split('?')[1] || '';
    const hashParams = new URLSearchParams(hashQuery);
    deviceToken = hashParams.get('device_token');
    userCode = hashParams.get('user_code');
  }

  if (userCode && tvCodeLabel && tvCodePill) {
    tvCodeLabel.textContent = userCode;
    tvCodePill.classList.remove('hidden');
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
  const globalChannel = supabase.channel('tv_pairing');
  globalChannel.subscribe();

  function broadcastDeviceAuth(user) {
    const token = activeToken;
    const payload = {
      device_token: token,
      user_id: user.id,
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
        globalChannel.send({
          type: 'broadcast',
          event: 'device_authorized',
          payload
        });
      } catch (err) {
        console.warn('Realtime broadcast error:', err);
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

    // Try DB upsert
    try {
      supabase.from('game_sessions').upsert({
        room_code: 'TRIV',
        host_id: user.id,
        status: 'waiting_for_host',
        updated_at: new Date().toISOString()
      }, { onConflict: 'room_code' }).catch(() => {});
    } catch (_) {}

    // Send immediately and retry multiple times
    sendAll();
    setTimeout(sendAll, 300);
    setTimeout(sendAll, 800);
    setTimeout(sendAll, 1600);

    // Immediately show success and transition to Host Panel
    showAlert('TV Connected! Opening Host Controls...', false);
    btnSubmit.textContent = 'CONNECTED! OPENING...';
    setTimeout(() => {
      switchView('host');
    }, 700);
  }

  async function handleAuthAction(e) {
    if (e) e.preventDefault();
    hideAlert();
    const email = emailInput?.value.trim() || 'host@venue.com';
    const password = passwordInput?.value || '123456';

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

      localStorage.setItem('bar_trivia_host_email', email);
      localStorage.setItem('bar_trivia_host_id', finalUser.id);

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
    tvPromoScreen?.classList.remove('hidden');
    tvLiveGrid?.classList.add('hidden');
  });

  btnLive?.addEventListener('click', (e) => {
    e.preventDefault();
    btnLive?.classList.add('active');
    btnPromo?.classList.remove('active');
    tvPromoScreen?.classList.add('hidden');
    tvLiveGrid?.classList.remove('hidden');

    if (currentQuestionData) {
      const remainingSecs = timerEndsAtGlobalMs 
        ? Math.max(0, Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000))
        : remainingTimerSeconds;

      onQuestionStart({
        questionData: currentQuestionData,
        roundNumber: Math.floor(currentQuestionIndex / 10) + 1,
        questionNumberInRound: (currentQuestionIndex % 10) + 1,
        durationSeconds: remainingSecs,
        difficulty: selectedDifficulty
      });
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
      panel.style.display = 'block';
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

  // 4. TV View specific behavior: Show Live Stage when switching to TV
  if (viewName === 'tv') {
    const tvPromoScreen = document.getElementById('tv-promo-screen');
    const tvLiveGrid = document.getElementById('tv-live-grid');
    const btnPromo = document.getElementById('btn-tv-toggle-promo');
    const btnLive = document.getElementById('btn-tv-toggle-live');

    if (tvPromoScreen) tvPromoScreen.classList.add('hidden');
    if (tvLiveGrid) tvLiveGrid.classList.remove('hidden');
    if (btnLive) btnLive.classList.add('active');
    if (btnPromo) btnPromo.classList.remove('active');

    if (currentQuestionData) {
      const remainingSecs = timerEndsAtGlobalMs 
        ? Math.max(0, Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000))
        : remainingTimerSeconds;

      onQuestionStart({
        questionData: currentQuestionData,
        roundNumber: Math.floor(currentQuestionIndex / 10) + 1,
        questionNumberInRound: (currentQuestionIndex % 10) + 1,
        durationSeconds: remainingSecs,
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

  // Initial load view resolution
  const urlParams = new URLSearchParams(window.location.search);
  const roomParam = urlParams.get('room') || urlParams.get('room_id');
  const deviceToken = urlParams.get('device_token') || (window.location.hash.includes('device_token=') ? 'yes' : null);
  if (roomParam) {
    currentRoomCode = roomParam.toUpperCase();
    const roomInput = document.getElementById('input-room-code');
    if (roomInput) roomInput.value = currentRoomCode;
  }

  const viewParam = urlParams.get('view');
  if (viewParam && ['tv', 'player', 'host', 'auth'].includes(viewParam)) {
    switchView(viewParam);
  } else if (deviceToken || window.location.hash.includes('tv-auth')) {
    switchView('auth');
  } else if (urlParams.has('room') && viewParam !== 'tv') {
    switchView('player');
  } else {
    switchView('auth');
  }
}

// Global click delegate to catch inner card clicks
document.addEventListener('click', (e) => {
  const viewTarget = e.target.closest('[data-view]');
  if (viewTarget) {
    const viewName = viewTarget.getAttribute('data-view');
    if (viewName) {
      e.preventDefault();
      switchView(viewName);
    }
  }
});

// 2. DYNAMIC QR CODES
function initQrCodes() {
  const basePath = window.location.pathname.replace(/\/index\.html$/, '').replace(/\/+$/, '');
  const playUrl = `${window.location.origin}${basePath}/?view=player&room=${currentRoomCode}`;

  const canvasStage = document.getElementById('qr-canvas');
  if (canvasStage) {
    QRCode.toCanvas(canvasStage, playUrl, { width: 150, margin: 1 }, (err) => {
      if (err) console.error('Stage QR Code error:', err);
    });
  }

  const canvasPromo = document.getElementById('promo-qr-canvas');
  if (canvasPromo) {
    QRCode.toCanvas(canvasPromo, playUrl, { width: 120, margin: 1 }, (err) => {
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

let liveRoomChannel = null;
let liveDefaultChannel = null;
let liveGlobalChannel = null;

function initRealtimeSupabaseChannels() {
  try {
    const norm = currentRoomCode.toUpperCase();
    liveRoomChannel = supabase.channel(`room_${norm}`);
    liveRoomChannel.subscribe();

    liveDefaultChannel = supabase.channel('room_TRIV');
    liveDefaultChannel.subscribe();

    liveGlobalChannel = supabase.channel('room_GLOBAL');
    liveGlobalChannel.subscribe();
  } catch (e) {
    console.warn('Error setting up Supabase Realtime channels:', e);
  }
}

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
      mqttClient.publish(getMqttTopic(), JSON.stringify(fullPayload));
    } catch (e) {
      console.warn('[Realtime MQTT] Failed to publish:', e);
    }
  }

  // 3. Internet-Wide Supabase Realtime Gateway
  try {
    if (!liveRoomChannel || !liveDefaultChannel) {
      initRealtimeSupabaseChannels();
    }
    liveRoomChannel?.send({
      type: 'broadcast',
      event: event,
      payload: fullPayload
    });
    liveDefaultChannel?.send({
      type: 'broadcast',
      event: event,
      payload: fullPayload
    });
    liveGlobalChannel?.send({
      type: 'broadcast',
      event: event,
      payload: fullPayload
    });
  } catch (err) {
    console.warn('[Supabase Realtime Broadcast] Error:', err);
  }
}

function handleIncomingQuestionStart(rawPayload) {
  if (!rawPayload) return;
  const payload = rawPayload.payload || rawPayload;
  console.log('[Realtime] Processing question_start:', payload);

  const questionData = {
    id: payload.question_id || payload.id || String(Date.now()),
    category: payload.category || 'General Knowledge',
    difficulty: payload.difficulty || selectedDifficulty || 'Standard',
    text: payload.question_text || payload.text || payload.question || '',
    options: {
      A: payload.option_a || payload.options?.A || payload.options?.a || 'Option A',
      B: payload.option_b || payload.options?.B || payload.options?.b || 'Option B',
      C: payload.option_c || payload.options?.C || payload.options?.c || 'Option C',
      D: payload.option_d || payload.options?.D || payload.options?.d || 'Option D',
    },
    correct: (payload.correct_option || payload.correct || 'A').toUpperCase().trim(),
  };

  currentQuestionData = questionData;
  currentGameState = 'QUESTION_ACTIVE';

  const durationSeconds = Number(payload.duration_seconds || payload.time_limit_seconds) || selectedQuestionDuration || 20;
  const qIndex = Number(payload.question_index) || 1;
  const roundNum = Math.floor((qIndex - 1) / 10) + 1;
  const qNumInRound = ((qIndex - 1) % 10) + 1;

  timerEndsAtGlobalMs = payload.timer_ends_at_epoch_ms || (Date.now() + durationSeconds * 1000);
  const remainingSecs = Math.max(1, Math.min(durationSeconds, Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000)));

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
  onTimerExpired({
    correctOption: payload.correct_option || payload.correctOption || payload.correct,
    correctText: payload.correctText,
    nextQuestionStartsAtEpochMs: payload.next_question_starts_at_epoch_ms,
  });
}

function handleRealtimeIncomingEvent(event, data) {
  const normEvent = (event || '').toLowerCase();
  const payload = data.payload || data;

  if (normEvent === 'question_start') {
    handleIncomingQuestionStart(payload);
  } else if (normEvent === 'timer_expired') {
    handleIncomingTimerExpired(payload);
  } else if (normEvent === 'round_completed' || normEvent === 'round_winner') {
    if (payload?.top3_winners || payload?.top3Winners) {
      onRoundWinner({ top3Winners: payload.top3_winners || payload.top3Winners || [] });
    }
  } else if (normEvent === 'game_reset') {
    onGameReset();
  } else if (normEvent === 'request_state_sync') {
    if (currentGameState === 'QUESTION_ACTIVE' && currentQuestionData) {
      broadcastRealtimeEvent('question_start', {
        question_index: currentQuestionIndex + 1,
        question_id: currentQuestionData.id,
        duration_seconds: remainingTimerSeconds,
        timer_ends_at_epoch_ms: timerEndsAtGlobalMs,
        category: currentQuestionData.category,
        difficulty: selectedDifficulty,
        question_text: currentQuestionData.text,
        option_a: currentQuestionData.options.A,
        option_b: currentQuestionData.options.B,
        option_c: currentQuestionData.options.C,
        option_d: currentQuestionData.options.D,
        correct_option: currentQuestionData.correct,
      });
    }
  } else if (normEvent === 'player_joined') {
    onPlayerJoined(payload);
  } else if (normEvent === 'answer_submitted') {
    onAnswerSubmitted(payload);
  } else if (normEvent === 'leaderboard_updated') {
    if (payload?.players || payload?.leaderboard) {
      playersLeaderboard = payload.players || payload.leaderboard;
      renderLeaderboard();
    }
  }
}

function initRealtimeEngine() {
  if (mqttClient) {
    try { mqttClient.end(true); } catch (_) {}
  }

  const topic = getMqttTopic();
  console.log(`[Realtime Engine] Connecting to MQTT broker for ${topic}...`);

  try {
    mqttClient = mqtt.connect('wss://broker.emqx.io:8084/mqtt', {
      clientId: `barrooms_${Math.random().toString(16).substring(2, 10)}`,
      keepalive: 30,
      reconnectPeriod: 2000,
    });

    mqttClient.on('connect', () => {
      console.log(`[Realtime Engine] Connected! Subscribing to ${topic}...`);
      mqttClient.subscribe(topic, { qos: 0 }, (err) => {
        if (!err) {
          console.log(`[Realtime Engine] Subscribed to ${topic}!`);
          // Request current state from host immediately
          broadcastRealtimeEvent('request_state_sync', { room_code: currentRoomCode });
        }
      });
    });

    mqttClient.on('message', (receivedTopic, message) => {
      if (receivedTopic !== topic) return;
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
          selectedDifficulty,
          selectedQuestionDuration,
          currentVenueName,
          customBarLogoUrl,
          playersLeaderboard,
          timerEndsAtGlobalMs,
          totalTimerDuration
        }
      });
    } else if (type === 'STATE_SYNC_RESPONSE') {
      onStateSyncResponse(payload);
    } else if (type === 'QUESTION_START') {
      onQuestionStart(payload);
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
    } else if (type === 'LEADERBOARD_UPDATED') {
      playersLeaderboard = payload.leaderboard;
      renderLeaderboard();
    } else if (type === 'GAME_RESET') {
      onGameReset(payload);
    } else if (type === 'LOGO_UPDATED') {
      onLogoUpdated(payload);
    } else if (type === 'VENUE_NAME_UPDATED') {
      onVenueNameUpdated(payload);
    }
  };
}

function onStateSyncResponse(payload) {
  if (!payload) return;

  if (payload.currentVenueName) {
    currentVenueName = payload.currentVenueName;
    localStorage.setItem('bar_trivia_venue_name', currentVenueName);
    onVenueNameUpdated({ venueName: currentVenueName });
  }

  if (payload.customBarLogoUrl !== undefined) {
    customBarLogoUrl = payload.customBarLogoUrl;
    if (customBarLogoUrl) localStorage.setItem('bar_trivia_logo_url', customBarLogoUrl);
    else localStorage.removeItem('bar_trivia_logo_url');
    onLogoUpdated({ logoUrl: customBarLogoUrl });
  }

  if (payload.playersLeaderboard) {
    playersLeaderboard = payload.playersLeaderboard;
    renderLeaderboard();
  }

  if (payload.currentGameState === 'QUESTION_ACTIVE' && payload.currentQuestionData) {
    currentGameState = payload.currentGameState;
    currentQuestionData = payload.currentQuestionData;
    currentQuestionIndex = payload.currentQuestionIndex || 0;
    selectedDifficulty = payload.selectedDifficulty || 'Standard';
    timerEndsAtGlobalMs = payload.timerEndsAtGlobalMs || 0;

    const remainingSecs = payload.timerEndsAtGlobalMs 
      ? Math.max(0, Math.ceil((payload.timerEndsAtGlobalMs - Date.now()) / 1000))
      : payload.totalTimerDuration;

    onQuestionStart({
      questionData: payload.currentQuestionData,
      roundNumber: Math.floor(payload.currentQuestionIndex / 10) + 1,
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

  // Venue Name Input Handler
  hostVenueInput?.addEventListener('input', (e) => {
    currentVenueName = e.target.value.trim() || "OUR PUB";
    localStorage.setItem('bar_trivia_venue_name', currentVenueName);
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
        localStorage.setItem('bar_trivia_logo_url', customBarLogoUrl);
        updateHostLogoPreview(customBarLogoUrl);
        channel.postMessage({ type: 'LOGO_UPDATED', payload: { logoUrl: customBarLogoUrl } });
        onLogoUpdated({ logoUrl: customBarLogoUrl });
      };
      reader.readAsDataURL(file);
    }
  });

  btnRemoveLogo?.addEventListener('click', () => {
    customBarLogoUrl = null;
    localStorage.removeItem('bar_trivia_logo_url');
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
    if (isAutomatedEngineRunning) return;
    await initOpenTdbToken();
    isAutomatedEngineRunning = true;
    updateHostEngineUI('IN PROGRESS');
    runNextAutomatedStep();
  });

  btnPauseAuto?.addEventListener('click', () => {
    isAutomatedEngineRunning = false;
    clearTimeout(autoEngineTimeout);
    clearInterval(countdownInterval);
    clearInterval(modalCountdownInterval);
    clearInterval(tvNextQCountdownInterval);
    clearInterval(winnerCountdownInterval);
    clearMockPlayerTimeouts();
    updateHostEngineUI('PAUSED');
  });

  btnResetGame?.addEventListener('click', () => {
    isAutomatedEngineRunning = false;
    clearTimeout(autoEngineTimeout);
    clearInterval(countdownInterval);
    clearInterval(modalCountdownInterval);
    clearInterval(tvNextQCountdownInterval);
    clearInterval(winnerCountdownInterval);
    clearMockPlayerTimeouts();
    resetQuestionHistory();
    currentQuestionIndex = 0;
    currentGameState = 'LOBBY';
    updateHostEngineUI('NOT STARTED');

    channel.postMessage({ type: 'GAME_RESET', payload: { roomCode: currentRoomCode } });
    onGameReset({ roomCode: currentRoomCode });
  });
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

function updateHostEngineUI(statusText) {
  const btnStartAuto = document.getElementById('btn-start-auto');
  const btnPauseAuto = document.getElementById('btn-pause-auto');
  const engineStatus = document.getElementById('host-engine-status');
  const statPlayers = document.getElementById('stat-players-count');

  const isRunning = (statusText === 'IN PROGRESS');

  if (btnStartAuto) btnStartAuto.disabled = isRunning;
  if (btnPauseAuto) btnPauseAuto.disabled = !isRunning;

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

  if (statPlayers) statPlayers.textContent = playersLeaderboard.length;
}

// AUTOMATED GAME LOOP LOGIC
async function runNextAutomatedStep() {
  if (!isAutomatedEngineRunning) return;

  const currentRound = Math.floor(currentQuestionIndex / 10) + 1;
  const questionInRound = (currentQuestionIndex % 10) + 1;

  let activeRoundGenre = 'Auto Select';

  // QUEUE OR AUTO SELECT ROTATION LOGIC
  if (selectedGenreQueue.length > 0) {
    const qIndex = (currentRound - 1) % selectedGenreQueue.length;
    activeRoundGenre = selectedGenreQueue[qIndex];
  } else {
    // AUTO SELECT: PICK ONE SINGLE SPECIFIC GENRE FOR THIS GAME/ROUND, AND ROTATE NEXT GAME!
    const autoGenre = shuffledAutoGenres[(currentRound - 1) % shuffledAutoGenres.length];
    activeRoundGenre = autoGenre;
  }

  // FETCH REAL-TIME QUESTIONS
  const durationSeconds = selectedQuestionDuration;
  const questionBatch = await fetchRealtimeTriviaQuestions(activeRoundGenre, selectedDifficulty, 10);
  const question = questionBatch[(questionInRound - 1) % questionBatch.length];

  timerEndsAtGlobalMs = Date.now() + (durationSeconds * 1000);

  const payload = {
    questionIndex: currentQuestionIndex,
    roundNumber: currentRound,
    questionNumberInRound: questionInRound,
    questionData: question,
    difficulty: selectedDifficulty,
    durationSeconds,
    timerEndsAtMs: timerEndsAtGlobalMs
  };

  currentGameState = 'QUESTION_ACTIVE';
  broadcastRealtimeEvent('question_start', {
    question_index: currentQuestionIndex + 1,
    question_id: question.id,
    duration_seconds: durationSeconds,
    timer_ends_at_epoch_ms: timerEndsAtGlobalMs,
    category: question.category,
    difficulty: selectedDifficulty,
    question_text: question.text,
    option_a: question.options.A,
    option_b: question.options.B,
    option_c: question.options.C,
    option_d: question.options.D,
    correct_option: question.correct,
  });
  onQuestionStart(payload);

  autoEngineTimeout = setTimeout(() => {
    const expiredPayload = {
      correctOption: question.correct,
      correctText: `${question.correct}) ${question.options[question.correct]}`,
      questionIndex: currentQuestionIndex,
      roundNumber: currentRound,
      questionNumberInRound: questionInRound
    };

    currentGameState = 'QUESTION_REVIEW';

    setTimeout(() => {
      broadcastRealtimeEvent('timer_expired', {
        correct_option: question.correct,
        correctText: `${question.correct}) ${question.options[question.correct]}`,
        next_question_starts_at_epoch_ms: Date.now() + 20000,
      });
      onTimerExpired(expiredPayload);

      autoEngineTimeout = setTimeout(() => {
        currentQuestionIndex++;

        if (questionInRound === 10) {
          currentGameState = 'ROUND_SUMMARY';
          
          playersLeaderboard.sort((a, b) => b.score - a.score);
          const roundWinner = playersLeaderboard[0] || { nickname: 'Player 1', score: 0 };
          
          roundWinner.score += 250;
          renderLeaderboard();
          broadcastRealtimeEvent('leaderboard_updated', {
            players: playersLeaderboard,
          });

          const winnerPayload = {
            roundNumber: currentRound,
            winnerName: roundWinner.nickname,
            winnerScore: roundWinner.score,
            delaySeconds: 60
          };

          broadcastRealtimeEvent('round_completed', {
            top3_winners: playersLeaderboard.slice(0, 3),
            next_round_starts_at_epoch_ms: Date.now() + 60000,
          });
          onRoundWinner(winnerPayload);

          autoEngineTimeout = setTimeout(() => {
            if (isAutomatedEngineRunning) runNextAutomatedStep();
          }, 60000);
        } else {
          if (isAutomatedEngineRunning) runNextAutomatedStep();
        }
      }, 20000);
    }, 1000);

  }, durationSeconds * 1000);
}

// SIMULATE 10 BACKGROUND MOCK PLAYERS WITH SPEED & STREAK MULTIPLIER SCORING
function triggerMockPlayersSimulation(questionData, durationSeconds) {
  clearMockPlayerTimeouts();

  playersLeaderboard.forEach(player => {
    if (currentPlayer && player.nickname.toLowerCase() === currentPlayer.nickname.toLowerCase()) return;

    const maxDelaySecs = Math.max(2, durationSeconds - 2);
    const delaySecs = Math.random() * maxDelaySecs + 1;
    const delayMs = Math.floor(delaySecs * 1000);

    const t = setTimeout(() => {
      const isCorrect = Math.random() < 0.75;
      if (isCorrect) {
        let speedBonus = 10;
        if (delaySecs <= 3) speedBonus = 50;
        else if (delaySecs <= durationSeconds / 2) speedBonus = 25;

        player.streak = (player.streak || 0) + 1;
        let streakMult = 1.0;
        if (player.streak >= 3) streakMult = 1.5;
        else if (player.streak === 2) streakMult = 1.2;

        const pts = Math.round((100 + speedBonus) * streakMult);
        player.score += pts;
      } else {
        player.streak = 0;
      }
      renderLeaderboard();
      channel.postMessage({ type: 'LEADERBOARD_UPDATED', payload: { leaderboard: playersLeaderboard } });
    }, delayMs);

    mockPlayerTimeouts.push(t);
  });
}

function clearMockPlayerTimeouts() {
  mockPlayerTimeouts.forEach(t => clearTimeout(t));
  mockPlayerTimeouts = [];
}

// 5. QUESTION START HANDLER (STARTS TV & PLAYER COUNTDOWN TIMERS IMMEDIATELY)
function onQuestionStart(payload) {
  const { questionData, roundNumber, questionNumberInRound, durationSeconds, difficulty } = payload;
  currentQuestionData = questionData;
  totalTimerDuration = durationSeconds || selectedQuestionDuration || 20;
  const activeDifficulty = difficulty || selectedDifficulty || 'Standard';
  playerChoiceSubmitted = null;

  hideResultModal();
  hideWinnerModals();

  const btnPromo = document.getElementById('btn-tv-toggle-promo');
  const btnLive = document.getElementById('btn-tv-toggle-live');
  if (btnLive) btnLive.classList.add('active');
  if (btnPromo) btnPromo.classList.remove('active');

  triggerMockPlayersSimulation(questionData, totalTimerDuration);

  const tvNextQBanner = document.getElementById('tv-next-q-banner');
  if (tvNextQBanner) tvNextQBanner.classList.add('hidden');
  clearInterval(tvNextQCountdownInterval);

  const tvPromoScreen = document.getElementById('tv-promo-screen');
  const tvLiveGrid = document.getElementById('tv-live-grid');

  if (tvPromoScreen) tvPromoScreen.classList.add('hidden');
  if (tvLiveGrid) tvLiveGrid.classList.remove('hidden');

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
  if (tvQuestionText) tvQuestionText.textContent = questionData.text;

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

  // Reset player answer choice state for new question
  playerChoiceSubmitted = null;

  // Update Player Phone Display & Difficulty Pill
  const playerDispRoom = document.getElementById('player-disp-room');
  const playerCategoryPill = document.getElementById('player-category-pill');
  const playerDiffPill = document.getElementById('player-difficulty-pill');
  const playerQuestionText = document.getElementById('player-question-text');
  const playerStatusBadge = document.getElementById('player-status-badge');
  const answerBtns = document.querySelectorAll('.btn-answer');

  if (playerDispRoom) playerDispRoom.textContent = `ROOM: ${currentRoomCode} • ROUND ${roundNumber || 1} (Q${questionNumberInRound || 1}/10)`;
  if (playerCategoryPill) playerCategoryPill.textContent = `${categoryIcon} ${categoryName.toUpperCase()}`;
  if (playerDiffPill) {
    playerDiffPill.className = `difficulty-pill-sm ${diffClassMap[activeDifficulty] || 'diff-standard'}`;
    playerDiffPill.textContent = `${diffEmojiMap[activeDifficulty] || '🎯'} ${activeDifficulty.toUpperCase()}`;
  }
  if (playerQuestionText) playerQuestionText.textContent = questionData.text;

  const optA = document.getElementById('p-opt-a');
  if (optA) optA.textContent = questionData.options.A;
  const optB = document.getElementById('p-opt-b');
  if (optB) optB.textContent = questionData.options.B;
  const optC = document.getElementById('p-opt-c');
  if (optC) optC.textContent = questionData.options.C;
  const optD = document.getElementById('p-opt-d');
  if (optD) optD.textContent = questionData.options.D;

  if (playerStatusBadge) {
    playerStatusBadge.className = 'status-badge status-active';
    playerStatusBadge.innerHTML = `<span id="status-icon">⏱️</span> UNLOCKED`;
  }

  answerBtns.forEach(btn => {
    btn.disabled = false;
    btn.classList.remove('selected', 'unselected', 'review-correct', 'review-wrong');
  });
}

function startCountdown(seconds) {
  clearInterval(countdownInterval);
  remainingTimerSeconds = seconds;
  updateTimerUI();

  countdownInterval = setInterval(() => {
    remainingTimerSeconds--;
    updateTimerUI();
    if (remainingTimerSeconds <= 0) {
      clearInterval(countdownInterval);
    }
  }, 1000);
}

function updateTimerUI() {
  const currentSecs = Math.max(0, remainingTimerSeconds);

  const tvTimerVal = document.getElementById('tv-timer-val');
  const timerProgress = document.getElementById('timer-progress');
  if (tvTimerVal) tvTimerVal.textContent = currentSecs;

  const playerTimerVal = document.getElementById('player-timer-val');
  if (playerTimerVal) playerTimerVal.textContent = currentSecs;

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

// 6. TIMER EXPIRED -> HIGHLIGHT CORRECT OPTION TILE ON TV & START NEXT QUESTION COUNTDOWN TIMER ON TV
function onTimerExpired(payload) {
  const rawCorrect = payload?.correctOption || currentQuestionData?.correct || '';
  const correctOpt = rawCorrect.toUpperCase().trim();
  const correctTextStr = payload?.correctText || `${correctOpt}) ${currentQuestionData?.options?.[correctOpt] || ''}`;

  clearMockPlayerTimeouts();

  const playerStatusBadge = document.getElementById('player-status-badge');
  const answerBtns = document.querySelectorAll('.btn-answer');

  if (playerStatusBadge) {
    playerStatusBadge.className = 'status-badge status-locked';
    playerStatusBadge.innerHTML = `<span id="status-icon">🔒</span> TIME EXPIRED`;
  }

  answerBtns.forEach(btn => {
    btn.disabled = true;
    const choice = (btn.dataset.choice || '').toUpperCase();
    if (choice === correctOpt) {
      btn.classList.add('review-correct');
      btn.classList.remove('unselected');
    } else if (btn.classList.contains('selected')) {
      btn.classList.add('review-wrong');
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

  if (tvNextQBanner && tvNextQVal) {
    tvNextQBanner.classList.remove('hidden');
    let remNextQSecs = 20;
    tvNextQVal.textContent = remNextQSecs;

    clearInterval(tvNextQCountdownInterval);
    tvNextQCountdownInterval = setInterval(() => {
      remNextQSecs--;
      if (tvNextQVal) tvNextQVal.textContent = Math.max(0, remNextQSecs);
      if (remNextQSecs <= 0) {
        clearInterval(tvNextQCountdownInterval);
        tvNextQBanner.classList.add('hidden');
      }
    }, 1000);
  }

  // ACCURATE SCORING: Evaluate answer ONLY once when timer expires
  const isCorrect = Boolean(playerChoiceSubmitted && correctOpt && playerChoiceSubmitted.toUpperCase() === correctOpt);

  if (isCorrect && currentPlayer) {
    let speedBonus = 10;
    if (remainingTimerSeconds >= totalTimerDuration - 3) speedBonus = 50;
    else if (remainingTimerSeconds >= Math.floor(totalTimerDuration / 2)) speedBonus = 25;

    currentPlayer.streak = (currentPlayer.streak || 0) + 1;
    let streakMult = 1.0;
    if (currentPlayer.streak >= 3) streakMult = 1.5;
    else if (currentPlayer.streak === 2) streakMult = 1.2;

    const pointsEarned = Math.round((100 + speedBonus) * streakMult);
    currentPlayer.score += pointsEarned;
    const scoreVal = document.getElementById('player-score-val');
    if (scoreVal) scoreVal.textContent = currentPlayer.score;

    const targetPlayer = playersLeaderboard.find(p => p.nickname.toLowerCase() === currentPlayer.nickname.toLowerCase());
    if (targetPlayer) {
      targetPlayer.score = currentPlayer.score;
      targetPlayer.streak = currentPlayer.streak;
    } else {
      playersLeaderboard.push({ nickname: currentPlayer.nickname, score: currentPlayer.score, streak: currentPlayer.streak });
    }
    renderLeaderboard();
    broadcastRealtimeEvent('leaderboard_updated', {
      players: playersLeaderboard,
    });

    const randomQuote = getRandomItem(funnyCorrectQuotes);
    showResultModal(true, `+${pointsEarned} PTS`, correctTextStr, randomQuote, 20);
    confetti({ particleCount: 60, spread: 80, origin: { y: 0.6 } });
  } else {
    if (currentPlayer) {
      currentPlayer.streak = 0;
    }
    const randomQuote = getRandomItem(funnyWrongQuotes);
    showResultModal(false, "0 PTS", correctTextStr, randomQuote, 20);
  }
}

function getRandomItem(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function showResultModal(isCorrect, pointsText, correctTextStr, funnyQuote, countdownSeconds = 20) {
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
    if (title) title.textContent = 'NAILED IT!';
    if (scorePill) scorePill.textContent = pointsText;
  } else {
    card.className = 'result-modal-card is-wrong';
    if (icon) icon.textContent = '❌';
    if (title) title.textContent = 'OOF! MISSED IT!';
    if (scorePill) scorePill.textContent = pointsText;
  }

  if (correctTextEl) correctTextEl.textContent = correctTextStr;
  if (quote) quote.textContent = `"${funnyQuote}"`;

  let remSecs = countdownSeconds;
  if (modalTimerVal) modalTimerVal.textContent = remSecs;

  overlay.classList.remove('hidden');

  clearInterval(modalCountdownInterval);
  modalCountdownInterval = setInterval(() => {
    remSecs--;
    if (modalTimerVal) modalTimerVal.textContent = Math.max(0, remSecs);
    if (remSecs <= 0) {
      clearInterval(modalCountdownInterval);
      hideResultModal();
    }
  }, 1000);
}

function hideResultModal() {
  const overlay = document.getElementById('result-modal-overlay');
  if (overlay) overlay.classList.add('hidden');
  clearInterval(modalCountdownInterval);
}

// 7. MULTI-LAYER ROUND WINNER CELEBRATION MODAL WITH LIVE COUNTDOWN
function onRoundWinner(payload) {
  const top3 = payload?.top3Winners || playersLeaderboard.slice(0, 3);
  if (!top3 || top3.length === 0) return;

  const winner1 = top3[0] || { nickname: 'Champion', score: 0 };
  const winner2 = top3[1] || { nickname: 'Runner Up', score: 0 };
  const winner3 = top3[2] || { nickname: 'Third Place', score: 0 };

  const tvWinnerOverlay = document.getElementById('tv-winner-modal-overlay');
  const playerWinnerOverlay = document.getElementById('player-winner-modal-overlay');

  const tvW1Name = document.getElementById('tv-w1-name');
  const tvW1Score = document.getElementById('tv-w1-score');
  const tvW2Name = document.getElementById('tv-w2-name');
  const tvW2Score = document.getElementById('tv-w2-score');
  const tvW3Name = document.getElementById('tv-w3-name');
  const tvW3Score = document.getElementById('tv-w3-score');

  if (tvW1Name) tvW1Name.textContent = winner1.nickname;
  if (tvW1Score) tvW1Score.textContent = `${winner1.score} PTS`;
  if (tvW2Name) tvW2Name.textContent = winner2.nickname;
  if (tvW2Score) tvW2Score.textContent = `${winner2.score} PTS`;
  if (tvW3Name) tvW3Name.textContent = winner3.nickname;
  if (tvW3Score) tvW3Score.textContent = `${winner3.score} PTS`;

  const pW1Name = document.getElementById('player-w1-name');
  const pW1Score = document.getElementById('player-w1-score');
  const pW2Name = document.getElementById('player-w2-name');
  const pW2Score = document.getElementById('player-w2-score');
  const pW3Name = document.getElementById('player-w3-name');
  const pW3Score = document.getElementById('player-w3-score');

  if (pW1Name) pW1Name.textContent = winner1.nickname;
  if (pW1Score) pW1Score.textContent = `${winner1.score} PTS`;
  if (pW2Name) pW2Name.textContent = winner2.nickname;
  if (pW2Score) pW2Score.textContent = `${winner2.score} PTS`;
  if (pW3Name) pW3Name.textContent = winner3.nickname;
  if (pW3Score) pW3Score.textContent = `${winner3.score} PTS`;

  const tvNextRoundTimer = document.getElementById('tv-winner-next-round-timer');
  const playerWinnerTimer = document.getElementById('player-winner-next-round-timer');

  if (tvWinnerOverlay) tvWinnerOverlay.classList.remove('hidden');
  if (playerWinnerOverlay) playerWinnerOverlay.classList.remove('hidden');

  let remWinnerSecs = 60;
  if (tvNextRoundTimer) tvNextRoundTimer.textContent = remWinnerSecs;
  if (playerWinnerTimer) playerWinnerTimer.textContent = remWinnerSecs;

  clearInterval(winnerCountdownInterval);
  winnerCountdownInterval = setInterval(() => {
    remWinnerSecs--;
    const currentSecs = Math.max(0, remWinnerSecs);
    if (tvNextRoundTimer) tvNextRoundTimer.textContent = currentSecs;
    if (playerWinnerTimer) playerWinnerTimer.textContent = currentSecs;

    if (remWinnerSecs <= 0) {
      clearInterval(winnerCountdownInterval);
      hideWinnerModals();
    }
  }, 1000);

  confetti({ particleCount: 120, spread: 100, origin: { y: 0.5 } });
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

  function doJoin() {
    const roomInput = document.getElementById('input-room-code');
    const nicknameInput = document.getElementById('input-nickname');

    const enteredRoom = (roomInput?.value || '').trim();
    if (enteredRoom) {
      currentRoomCode = enteredRoom.toUpperCase();
    }

    const rawNick = (nicknameInput?.value || '').trim();
    const nickname = rawNick || `Player_${Math.floor(Math.random() * 900 + 100)}`;

    currentPlayer = { nickname, score: 0, streak: 0 };
    if (playerDispNickname) playerDispNickname.textContent = nickname.toUpperCase();
    if (playerDispRoom) playerDispRoom.textContent = `ROOM: ${currentRoomCode} • ROUND 1`;

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

    // Broadcast join
    broadcastRealtimeEvent('player_joined', {
      nickname: currentPlayer.nickname,
      score: currentPlayer.score,
    });
    onPlayerJoined(currentPlayer);

    if (currentQuestionData) {
      const qText = document.getElementById('player-question-text');
      if (qText) qText.textContent = currentQuestionData.text;
      const optA = document.getElementById('p-opt-a');
      if (optA) optA.textContent = currentQuestionData.options?.A || 'A';
      const optB = document.getElementById('p-opt-b');
      if (optB) optB.textContent = currentQuestionData.options?.B || 'B';
      const optC = document.getElementById('p-opt-c');
      if (optC) optC.textContent = currentQuestionData.options?.C || 'C';
      const optD = document.getElementById('p-opt-d');
      if (optD) optD.textContent = currentQuestionData.options?.D || 'D';
    }
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
      if (!choice) return;

      playerChoiceSubmitted = choice;

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
        score: currentPlayer.score,
      });
    };
  });
}

function onPlayerJoined(player) {
  const exists = playersLeaderboard.some(p => p.nickname.toLowerCase() === player.nickname.toLowerCase());
  if (!exists) {
    playersLeaderboard.push({ nickname: player.nickname, score: 0, streak: 0 });
    renderLeaderboard();
    channel.postMessage({ type: 'LEADERBOARD_UPDATED', payload: { leaderboard: playersLeaderboard } });
  }
  updateHostEngineUI(isAutomatedEngineRunning ? 'IN PROGRESS' : 'NOT STARTED');
}

function onAnswerSubmitted({ player, choice }) {
  // Answer submission recorded
  console.log(`Player ${player?.nickname} submitted answer: ${choice}`);
}

// RESET GAME -> REVERT TO ROTATING PROMO CAROUSEL
function onGameReset() {
  playersLeaderboard = [...defaultMockPlayers];
  selectedGenreQueue = [];
  updateGenreQueueUI();
  renderLeaderboard();
  currentGameState = 'LOBBY';
  hideResultModal();
  hideWinnerModals();

  const btnPromo = document.getElementById('btn-tv-toggle-promo');
  const btnLive = document.getElementById('btn-tv-toggle-live');
  if (btnPromo) btnPromo.classList.add('active');
  if (btnLive) btnLive.classList.remove('active');

  const tvNextQBanner = document.getElementById('tv-next-q-banner');
  if (tvNextQBanner) tvNextQBanner.classList.add('hidden');
  clearInterval(tvNextQCountdownInterval);

  const tvPromoScreen = document.getElementById('tv-promo-screen');
  const tvLiveGrid = document.getElementById('tv-live-grid');

  if (tvPromoScreen) tvPromoScreen.classList.remove('hidden');
  if (tvLiveGrid) tvLiveGrid.classList.add('hidden');

  startPromoCarouselRotation();
}

// 9. CLEAN LEADERBOARD RENDER WITHOUT CLUTTERED TEXT BADGES
function renderLeaderboard() {
  const list = document.getElementById('tv-leaderboard-list');
  if (!list) return;

  playersLeaderboard.sort((a, b) => b.score - a.score);

  if (playersLeaderboard.length === 0) {
    list.innerHTML = `<li class="lb-empty">No players connected yet...</li>`;
    return;
  }

  list.innerHTML = playersLeaderboard.map((p, index) => {
    const topClass = index < 3 ? `top-${index + 1}` : '';
    return `
      <li class="lb-item ${topClass}">
        <div style="display:flex; align-items:center;">
          <span class="lb-rank">#${index + 1}</span>
          <span>${escapeHtml(p.nickname)}</span>
        </div>
        <span class="lb-score">${p.score} pts</span>
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
