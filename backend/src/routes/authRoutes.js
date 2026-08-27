import express from 'express';
import { deviceAuthService } from '../services/deviceAuthService.js';

const router = express.Router();

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
    const baseUrl = req.query.base_url || process.env.CLIENT_BASE_URL || defaultBaseUrl;

    const sessionData = deviceAuthService.createDeviceCodeSession(baseUrl);

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
 * @desc    Pairs a mobile user ID to a pending device token
 * @access  Protected / Authenticated Mobile Client
 */
router.post('/device/verify', (req, res) => {
  try {
    const { device_token, user_id, user_info, auth_tokens } = req.body;

    if (!device_token) {
      return res.status(400).json({
        success: false,
        error: 'Missing required field: device_token',
      });
    }

    if (!user_id) {
      return res.status(400).json({
        success: false,
        error: 'Missing required field: user_id',
      });
    }

    const result = deviceAuthService.verifyDevice(
      device_token,
      user_id,
      user_info || {},
      auth_tokens || {}
    );

    if (!result.success) {
      const statusCode = result.code === 'NOT_FOUND' ? 404 : result.code === 'EXPIRED_TOKEN' ? 410 : 400;
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
 * @access  Public / Device
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
