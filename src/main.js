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
let mockPlayerTimeouts = [];
let currentRoundQuestions = [];

let remainingTimerSeconds = 0;
let totalTimerDuration = 20;
let timerEndsAtGlobalMs = 0;
let currentQuestionData = null;
let currentGameState = 'LOBBY';

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

document.addEventListener('visibilitychange', async () => {
  if (document.visibilityState === 'visible' && !screenWakeLock) {
    await requestScreenWakeLock();
  }
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

// COMPREHENSIVE FICTITIOUS & BOGUS PLAYER PURGE HELPER
function isFictitiousPlayer(nickname) {
  if (!nickname) return true;
  const lower = nickname.toString().trim().toLowerCase();
  if (lower.startsWith('mock-') || lower.startsWith('mock_')) return true;
  if (lower === 'host' || lower === 'host user' || lower === 'todd4529') return true;
  const banned = [
    'beerwhisperer', 'trivianinja', 'quizquark', 'hopsandglory', 'professorpint',
    'smartypints', 'brewmasterflex', 'mindovermug', 'alechemist', 'factchecker',
    'stoutscholars', 'brainybarley', 'pubeinstein', 'lagerlegend', 'quizcrafter',
    'triviamaster99', 'beerguru', 'pubquizpro', 'brewmaster_joe', 'hopsandbarley',
    'pintsizedgenius', 'whiskeywisdom', 'barstooleinstein', 'ciderseeker',
    'taverntactician', 'player 1', 'champion', 'runner up', 'third place'
  ];
  return banned.some(b => lower === b || lower.includes(b));
}

// INITIALIZE LEADERBOARD FOR REAL PLAYERS ONLY (No bogus / mock players)
let playersLeaderboard = [];

function loadInitialPlayers() {
  const normRoom = (currentRoomCode || 'TRIV').toUpperCase();
  try {
    supabase.from('players')
      .delete()
      .or('nickname.ilike.%todd4529%,nickname.ilike.%host%')
      .then(() => {})
      .catch(() => {});
  } catch (_) {}

  try {
    supabase.from('players')
      .select('*')
      .or(`room_code.eq.${normRoom},room_code.eq.TRIV`)
      .order('cumulative_score', { ascending: false })
      .then(({ data, error }) => {
        if (!error && data && data.length > 0) {
          // Filter out any legacy bogus players if present in DB, while retaining all real players even with score 0
          const realPlayers = data.filter(p => !isFictitiousPlayer(p.nickname));
          if (realPlayers.length > 0) {
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
        }
      }).catch(() => {});
  } catch (_) {}
}

// MAIN APP INITIALIZER
function initApp() {
  initOpenTdbToken();
  syncWeeklyTriviaInBackground();
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
  loadInitialPlayers();
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
          updated_at: new Date().toISOString()
        },
        {
          room_code: targetRoom,
          host_id: user.id,
          status: 'waiting_for_host',
          updated_at: new Date().toISOString()
        }
      ], { onConflict: 'room_code' }).catch(() => {});
    } catch (_) {}

    // Send immediately and retry multiple times
    sendAll();
    setTimeout(sendAll, 300);
    setTimeout(sendAll, 800);
    setTimeout(sendAll, 1600);

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
        roundNumber: currentRound,
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
        roundNumber: currentRound,
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

let liveRoomChannel = null;
let liveDefaultChannel = null;
let liveGlobalChannel = null;

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

function handleIncomingPreGameCountdown(rawPayload) {
  const payload = rawPayload?.payload || rawPayload || {};
  console.log('[Realtime] Processing pre_game_countdown:', payload);
  const countdownSecs = payload.countdown_seconds || 10;
  currentGameState = 'COUNTDOWN';
  currentQuestionData = null;
  playerChoiceSubmitted = null;

  const rNum = Number(payload.round_number || payload.roundNumber);
  if (rNum && rNum > 0) {
    currentRound = Math.max(currentRound, rNum);
  }

  hideResultModal();
  hideWinnerModals();

  // If in TV view, automatically transition from rotating promo ads to live stage
  const tvPromoScreen = document.getElementById('tv-promo-screen');
  const tvLiveGrid = document.getElementById('tv-live-grid');
  const btnPromo = document.getElementById('btn-tv-toggle-promo');
  const btnLive = document.getElementById('btn-tv-toggle-live');
  if (tvPromoScreen) tvPromoScreen.classList.add('hidden');
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
  if (btnSkip) btnSkip.classList.add('hidden');

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
  const rFromPayload = Number(payload.round_number || payload.roundNumber);
  const roundNum = (rFromPayload && rFromPayload > 0)
    ? Math.max(currentRound, rFromPayload)
    : Math.max(currentRound, (payload.cumulative_question_index ? Math.floor((payload.cumulative_question_index - 1) / 10) + 1 : 1));
  currentRound = roundNum;
  const qNumInRound = Number(payload.question_number_in_round || payload.questionNumberInRound) || (((qIndex - 1) % 10) + 1);

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
  const payload = data.payload || data;

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
    onRoundWinner({ top3Winners: list, delaySeconds: 15, roundNumber: currentRound });
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
  } else if (normEvent === 'leaderboard_updated') {
    const list = payload?.players || payload?.leaderboard;
    if (Array.isArray(list)) {
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
        if (myIdx === -1) {
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
  }
}

function initRealtimeEngine() {
  // Always initialize Supabase Realtime Channels for Internet-wide broadcasting
  initRealtimeSupabaseChannels();

  const topic = getMqttTopic();
  const topicsToSub = [topic, 'barrooms_trivia/room_TRIV', 'tv_pairing'];

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
                const jsonStr = JSON.stringify(p);
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
      const isAllowed = (
        receivedTopic === topic ||
        receivedTopic === 'barrooms_trivia/room_TRIV' ||
        receivedTopic === 'tv_pairing' ||
        receivedTopic === `barrooms_trivia/room_${normRoom}`
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
  const btnSkipQuestion = document.getElementById('btn-skip-question');
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

  // SKIP QUESTION ACTION
  btnSkipQuestion?.addEventListener('click', () => {
    if (!isAutomatedEngineRunning) return;
    if (hostEngineState === 'QUESTION_ACTIVE' && currentQuestionData) {
      clearTimeout(autoEngineTimeout);
      const qInRound = (currentQuestionIndex % 10) + 1;
      handleHostQuestionTimeout(currentQuestionData, currentRound, qInRound);
    } else if (hostEngineState === 'QUESTION_REVIEW') {
      clearTimeout(autoEngineTimeout);
      const qInRound = (currentQuestionIndex % 10) + 1;
      handleHostAdvanceAfterReview(qInRound, currentRound);
    }
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
    isAutomatedEngineRunning = false;
    stopHostHeartbeatLoop();
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

    channel.postMessage({ type: 'GAME_RESET', payload: { roomCode: currentRoomCode } });
    onGameReset({ roomCode: currentRoomCode });
  });

  // Initial UI Render
  updateGenreQueueUI();
  updateHostEngineUI('NOT STARTED');
  renderHostPlayersRoster();
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

  if (btnStartAuto) btnStartAuto.disabled = isRunning;
  if (btnPauseAuto) btnPauseAuto.disabled = !isRunning;
  if (btnSkip && !isRunning) {
    btnSkip.classList.add('hidden');
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
        text: `In the study of ${activeRoundGenre}, which approach ensures highest quality outcomes?`,
        options: {
          A: 'Rigorous empirical standards and safety compliance',
          B: 'Random improvised guesswork without verification',
          C: 'Bypassing all standard inspection procedures',
          D: 'Discarding equipment manuals immediately'
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

  const reviewDurationMs = 15000; // Synchronized 15-second review across TV and player screens
  hostTargetEpochMs = Date.now() + reviewDurationMs;

  const expiredPayload = {
    correctOption: question.correct,
    correctText: `${question.correct}) ${question.options[question.correct]}`,
    next_question_starts_at_epoch_ms: hostTargetEpochMs,
    nextQuestionStartsAtEpochMs: hostTargetEpochMs,
    questionIndex: currentQuestionIndex,
    roundNumber: currentRound,
    questionNumberInRound: questionInRound,
    game_play_mode: 'Auto',
  };

  currentGameState = 'QUESTION_REVIEW';
  hostEngineState = 'QUESTION_REVIEW';

  broadcastRealtimeEvent('timer_expired', expiredPayload);
  onTimerExpired(expiredPayload);

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
    hostTargetEpochMs = Date.now() + 15000;
    
    playersLeaderboard.sort((a, b) => (Number(b.score ?? b.cumulative_score ?? 0)) - (Number(a.score ?? a.cumulative_score ?? 0)));
    const validPlayers = playersLeaderboard.filter(p => p && p.nickname && !isFictitiousPlayer(p.nickname));

    let top3 = [];
    let winnerPayload = {
      roundNumber: currentRound,
      winnerName: '',
      winnerScore: 0,
      top3Winners: [],
      delaySeconds: 15
    };

    if (validPlayers.length > 0) {
      const roundWinner = validPlayers[0];
      roundWinner.score = (Number(roundWinner.score ?? roundWinner.cumulative_score ?? 0)) + 20;
      roundWinner.cumulative_score = roundWinner.score;
      renderLeaderboard();
      broadcastRealtimeEvent('leaderboard_updated', {
        players: playersLeaderboard,
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
        delaySeconds: 15
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
    }, 15000);
  } else {
    runNextAutomatedStep();
  }
}

function handleHostAdvanceAfterRoundSummary() {
  if (!isAutomatedEngineRunning || hostEngineState !== 'ROUND_SUMMARY') return;
  currentRoundQuestions = [];
  currentQuestionData = null;
  playerChoiceSubmitted = null;

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
  const { questionData, roundNumber, questionNumberInRound, durationSeconds, difficulty } = payload;
  currentQuestionData = questionData;
  totalTimerDuration = durationSeconds || selectedQuestionDuration || 20;
  const activeDifficulty = difficulty || selectedDifficulty || 'Standard';
  playerChoiceSubmitted = null;

  hideResultModal();
  hideWinnerModals();
  clearInterval(modalCountdownInterval);
  clearInterval(playerReviewInterval);

  const btnPromo = document.getElementById('btn-tv-toggle-promo');
  const btnLive = document.getElementById('btn-tv-toggle-live');
  if (btnLive) btnLive.classList.add('active');
  if (btnPromo) btnPromo.classList.remove('active');

  const tvPromoScreen = document.getElementById('tv-promo-screen');
  const tvLiveGrid = document.getElementById('tv-live-grid');
  if (tvPromoScreen) tvPromoScreen.classList.add('hidden');
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
  if (btnSkip) {
    btnSkip.classList.remove('hidden');
    btnSkip.disabled = false;
  }

  // Populate Host Answer Key Grid & Highlight Correct Option
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

  // Reset player answer choice state and dismiss previous result modal for new question
  playerChoiceSubmitted = null;
  hideResultModal();
  hideWinnerModals();

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
  if (playerQuestionText) playerQuestionText.textContent = cleanQText;

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
    const existingBadge = btn.querySelector('.player-correct-badge');
    if (existingBadge) existingBadge.remove();
  });
}

function startCountdown(seconds) {
  clearInterval(countdownInterval);
  const initialRem = timerEndsAtGlobalMs > 0 ? Math.max(0, Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000)) : seconds;
  remainingTimerSeconds = Math.min(seconds, initialRem);
  updateTimerUI();

  countdownInterval = setInterval(() => {
    if (timerEndsAtGlobalMs > 0) {
      remainingTimerSeconds = Math.max(0, Math.ceil((timerEndsAtGlobalMs - Date.now()) / 1000));
    } else {
      remainingTimerSeconds--;
    }
    updateTimerUI();
    if (remainingTimerSeconds <= 0) {
      clearInterval(countdownInterval);
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
      }
    }, 500);
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
  if (btnSkip) {
    btnSkip.textContent = '⏩ Next Q';
    btnSkip.classList.remove('hidden');
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
  const isCorrect = Boolean(playerChoiceSubmitted && correctOpt && playerChoiceSubmitted.toUpperCase() === correctOpt);

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

  const targetEpoch = targetEpochMs || (Date.now() + Math.round(countdownSeconds * 1000));

  const updateModalCountdown = () => {
    const rem = Math.max(0, Math.ceil((targetEpoch - Date.now()) / 1000));
    if (modalTimerVal) modalTimerVal.textContent = rem;
    if (rem <= 0) {
      clearInterval(modalCountdownInterval);
    }
  };

  updateModalCountdown();
  clearInterval(modalCountdownInterval);
  modalCountdownInterval = setInterval(updateModalCountdown, 500);

  overlay.classList.remove('hidden');
  // Stay on screen until the next question is loaded (no tap dismissal, no early timeout)
  overlay.onclick = null;
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

  let remWinnerSecs = payload?.delaySeconds || 15;
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
  const nicknameInput = document.getElementById('input-nickname');

  const savedNick = safeStorage.getItem('bar_trivia_player_nickname');
  if (savedNick && nicknameInput && !nicknameInput.value) {
    nicknameInput.value = savedNick;
  }

  function doJoin() {
    const roomInput = document.getElementById('input-room-code');

    const enteredRoom = (roomInput?.value || '').trim();
    if (enteredRoom) {
      currentRoomCode = enteredRoom.toUpperCase().replace(/[^A-Z0-9]/g, '');
    }

    const rawNick = (nicknameInput?.value || '').trim();
    const nickname = rawNick || `Player_${Math.floor(Math.random() * 900 + 100)}`;

    safeStorage.setItem('bar_trivia_player_nickname', nickname);
    safeStorage.setItem('bar_trivia_current_room', currentRoomCode);

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

    function checkActiveGameSession() {
      // Periodic player heartbeat ensures TV display maintains sync
      if (currentPlayer && currentPlayer.nickname && !isFictitiousPlayer(currentPlayer.nickname)) {
        sendJoinBroadcast();
      }

      supabase.from('game_sessions')
        .select('*')
        .or(`room_code.eq.${currentRoomCode},room_code.eq.TRIV`)
        .maybeSingle()
        .then(({ data }) => {
          if (data) {
            if (data.status === 'pre_game_countdown') {
              const rem = Math.max(1, Math.ceil((data.starts_at - Date.now()) / 1000));
              const rNum = data.current_round || data.round_number || currentRound;
              handleIncomingPreGameCountdown({ countdown_seconds: rem, round_number: rNum, genre: data.genre });
            } else if (data.status === 'question_active' && data.question_data) {
              const qData = data.question_data;
              const now = Date.now();
              const endsAt = data.timer_ends_at || (now + 20000);
              if ((endsAt - now) > -15000) {
                if (!currentQuestionData || currentQuestionData.id !== qData.id || currentGameState !== 'QUESTION_ACTIVE') {
                  const rNum = data.current_round || data.round_number || qData.round_number || qData.roundNumber || currentRound;
                  handleIncomingQuestionStart({
                    ...qData,
                    question_index: data.current_question_index || 1,
                    round_number: rNum,
                    roundNumber: rNum,
                    duration_seconds: data.duration_seconds || 20,
                    timer_ends_at_epoch_ms: data.timer_ends_at
                  });
                }
              }
            }
          }
        }).catch(() => {});
    }
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
        playersLeaderboard[idx].score = initialScore;
        playersLeaderboard[idx].cumulative_score = initialScore;
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

function onAnswerSubmitted({ player, choice }) {
  // Answer submission recorded
  console.log(`Player ${player?.nickname} submitted answer: ${choice}`);
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
  hideResultModal();
  hideWinnerModals();

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
  if (btnSkip) btnSkip.classList.add('hidden');

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
  const tvLiveGrid = document.getElementById('tv-live-grid');

  if (tvPromoScreen) tvPromoScreen.classList.remove('hidden');
  if (tvLiveGrid) tvLiveGrid.classList.add('hidden');

  startPromoCarouselRotation();
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
