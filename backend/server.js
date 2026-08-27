import express from 'express';
import cors from 'cors';
import authRoutes from './src/routes/authRoutes.js';

const app = express();
const PORT = process.env.PORT || 4000;

// Enable CORS for mobile apps, TV displays, and web clients
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// Body parsers
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Request logging in development
app.use((req, res, next) => {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] ${req.method} ${req.originalUrl}`);
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
  console.error('Unhandled server error:', err);
  res.status(500).json({ error: 'Internal Server Error' });
});

// Start listening if run directly
if (process.env.NODE_ENV !== 'test') {
  app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Device Auth Backend running on http://0.0.0.0:${PORT}`);
    console.log(`- Device Code Init: GET http://localhost:${PORT}/auth/device/code`);
    console.log(`- Device Verify:    POST http://localhost:${PORT}/auth/device/verify`);
    console.log(`- Status Poll:      GET http://localhost:${PORT}/auth/device/status?device_token=...`);
  });
}

export default app;
