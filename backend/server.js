import express from 'express';
import cors from 'cors';
import authRoutes from './src/routes/authRoutes.js';

const app = express();
const PORT = process.env.PORT || 4000;

// Respect X-Forwarded-Proto/Host behind reverse proxies
app.set('trust proxy', 1);

// Security headers
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  next();
});

// Allowlist CORS origins (configurable via ALLOWED_ORIGINS env var)
const defaultAllowedOrigins = [
  'https://barroomstrivia.com',
  'https://www.barroomstrivia.com',
  'http://localhost:3000',
  'http://localhost:5173',
  'http://127.0.0.1:5173',
];
const envOrigins = (process.env.ALLOWED_ORIGINS || '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);
const allowedOrigins = envOrigins.length > 0 ? envOrigins : defaultAllowedOrigins;

app.use(cors({
  origin: (origin, callback) => {
    // Allow non-browser / native mobile & TV clients (no Origin header) and allowlisted origins
    if (!origin || allowedOrigins.includes(origin) || origin.endsWith('.barroomstrivia.com')) {
      return callback(null, true);
    }
    return callback(new Error('Origin not allowed by CORS'));
  },
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// Simple in-memory per-IP rate limiter for auth routes
const rateHits = new Map();
setInterval(() => rateHits.clear(), 60 * 1000).unref();
app.use('/auth', (req, res, next) => {
  const ip = req.ip || req.socket?.remoteAddress || 'unknown';
  const count = (rateHits.get(ip) || 0) + 1;
  rateHits.set(ip, count);
  if (count > 120) {
    return res.status(429).json({ success: false, error: 'Too many requests, please retry shortly' });
  }
  return next();
});

// Body parsers with payload size limit
app.use(express.json({ limit: '64kb' }));
app.use(express.urlencoded({ extended: true, limit: '64kb' }));

// Redacted request logging (never log query string tokens)
app.use((req, res, next) => {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] ${req.method} ${req.path}`);
  next();
});

// Mount device authorization routes
app.use('/auth', authRoutes);

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', uptime: process.uptime() });
});

// 404 Handler
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Unhandled server error:', err?.message || err);
  res.status(500).json({ error: 'Internal Server Error' });
});

// Start listening if run directly
if (process.env.NODE_ENV !== 'test') {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`Device Auth Backend running on http://0.0.0.0:${PORT}`);
  });
}

export default app;
