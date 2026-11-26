import express from 'express';
import { deviceAuthService } from '../services/deviceAuthService.js';

const router = express.Router();

const ALLOWED_BASE_HOSTS = new Set([
  'barroomstrivia.com',
  'www.barroomstrivia.com',
  'localhost',
  '127.0.0.1',
]);

function resolveSafeBaseUrl(requestedUrl, fallbackUrl) {
  const candidate = requestedUrl || fallbackUrl;
  try {
    const parsed = new URL(candidate);
    const host = parsed.hostname.toLowerCase();
    const isAllowed =
      (parsed.protocol === 'https:' || (parsed.protocol === 'http:' && (host === 'localhost' || host === '127.0.0.1'))) &&
      (ALLOWED_BASE_HOSTS.has(host) || host.endsWith('.barroomstrivia.com'));
    if (isAllowed) {
      return `${parsed.protocol}//${parsed.host}`;
    }
  } catch (_) {}
  return 'https://barroomstrivia.com';
}

/**
 * @route   GET /auth/device/code
 * @desc    Generates short-lived device token, session token, and QR verification URL
 * @access  Public (Called by Android TV / Big Screen Display)
 */
router.get('/device/code', (req, res) => {
  try {
    const hostHeader = req.get('host');
    const protocol = req.protocol;
    const defaultBaseUrl = `${protocol}://${hostHeader}`;
    const baseUrl = resolveSafeBaseUrl(req.query.base_url || process.env.CLIENT_BASE_URL, defaultBaseUrl);

    const sessionData = deviceAuthService.createDeviceCodeSession(baseUrl);
    if (sessionData.error) {
      return res.status(503).json({ success: false, error: sessionData.error });
    }

    return res.status(200).json({
      success: true,
      ...sessionData,
    });
  } catch (error) {
    console.error('Error generating device code:', error);
    return res.status(500).json({
      success: false,
      error: 'Failed to generate device authorization session',
    });
  }
});

/**
 * @route   POST /auth/device/verify
 * @desc    Pairs an authenticated mobile user to a pending device token or manual user_code
 * @access  Protected / Authenticated Mobile Client
 */
router.post('/device/verify', (req, res) => {
  try {
    const authHeader = req.get('authorization') || '';
    const hasBearerToken = authHeader.toLowerCase().startsWith('bearer ') && authHeader.length > 20;
    if (!hasBearerToken && process.env.ALLOW_UNAUTHENTICATED_VERIFY !== 'true') {
      return res.status(401).json({
        success: false,
        error: 'Authorization bearer token is required',
      });
    }

    const { device_token, user_code, user_id, user_info, auth_tokens } = req.body;
    const resolvedToken = device_token || (user_code ? deviceAuthService.resolveTokenByUserCode(user_code) : null);

    if (!resolvedToken) {
      return res.status(400).json({
        success: false,
        error: 'Missing or invalid device_token / user_code',
      });
    }

    if (!user_id) {
      return res.status(400).json({
        success: false,
        error: 'Missing required field: user_id',
      });
    }

    const result = deviceAuthService.verifyDevice(
      resolvedToken,
      user_id,
      user_info || {},
      auth_tokens || {}
    );

    if (!result.success) {
      const statusCode =
        result.code === 'NOT_FOUND' ? 404 :
        result.code === 'EXPIRED_TOKEN' ? 410 :
        result.code === 'ALREADY_VERIFIED' ? 409 : 400;
      return res.status(statusCode).json(result);
    }

    return res.status(200).json(result);
  } catch (error) {
    console.error('Error verifying device token:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error verifying device token',
    });
  }
});

/**
 * @route   GET /auth/device/status
 * @desc    Poll status endpoint called by Android TV every 4 seconds
 * @access  Public / Device (verified payloads are single-use and immediately consumed)
 */
router.get('/device/status', (req, res) => {
  try {
    const { device_token } = req.query;

    if (!device_token) {
      return res.status(400).json({
        success: false,
        error: 'Missing query parameter: device_token',
      });
    }

    const sessionStatus = deviceAuthService.checkSessionStatus(device_token);

    if (sessionStatus.status === 'expired') {
      return res.status(410).json({
        success: false,
        status: 'expired',
        error: sessionStatus.error,
      });
    }

    return res.status(200).json({
      success: true,
      ...sessionStatus,
    });
  } catch (error) {
    console.error('Error checking device status:', error);
    return res.status(500).json({
      success: false,
      error: 'Internal server error checking device status',
    });
  }
});

export default router;
