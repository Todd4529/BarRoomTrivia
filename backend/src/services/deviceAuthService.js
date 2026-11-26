import crypto from 'crypto';

/**
 * In-memory storage for short-lived device authorization sessions.
 * In a multi-instance production cluster, swap with Redis / KeyDB.
 */
class DeviceAuthService {
  constructor() {
    this.sessions = new Map(); // Key: device_token, Value: session data
    this.userCodeIndex = new Map(); // Key: normalized userCode, Value: device_token
    this.DEFAULT_TTL_MS = 5 * 60 * 1000; // 5 minutes TTL
    this.POLL_INTERVAL_SECONDS = 4;
    this.MAX_SESSIONS = 10000;

    // Periodic cleanup of expired tokens every 60 seconds
    setInterval(() => this.cleanupExpiredSessions(), 60 * 1000).unref();
  }

  /**
   * Generates a new short-lived device authorization session.
   * @param {string} baseUrl - Mobile/Web base URL for deep-linking verification
   * @returns {Object} Device authorization codes and verification metadata
   */
  createDeviceCodeSession(baseUrl = 'https://barroomstrivia.com') {
    if (this.sessions.size >= this.MAX_SESSIONS) {
      this.cleanupExpiredSessions();
      if (this.sessions.size >= this.MAX_SESSIONS) {
        return { error: 'Too many active pairing sessions, please retry shortly' };
      }
    }

    const deviceToken = crypto.randomBytes(32).toString('hex');
    const sessionToken = crypto.randomBytes(24).toString('base64url');
    const userCode = crypto.randomBytes(3).toString('hex').toUpperCase(); // e.g. "A4F89C"

    const now = Date.now();
    const expiresAt = now + this.DEFAULT_TTL_MS;

    const verificationUrl = `${baseUrl.replace(/\/$/, '')}/tv-auth?device_token=${encodeURIComponent(deviceToken)}&user_code=${encodeURIComponent(userCode)}`;

    const sessionData = {
      deviceToken,
      sessionToken,
      userCode,
      verificationUrl,
      status: 'pending', // 'pending' | 'verified' | 'expired'
      createdAt: now,
      expiresAt,
      pairedUserId: null,
      pairedUserInfo: null,
      authTokens: null,
    };

    this.sessions.set(deviceToken, sessionData);
    this.userCodeIndex.set(userCode, deviceToken);

    return {
      device_token: deviceToken,
      session_token: sessionToken,
      user_code: userCode,
      verification_url: verificationUrl,
      expires_in: Math.floor(this.DEFAULT_TTL_MS / 1000), // in seconds (300s)
      interval: this.POLL_INTERVAL_SECONDS, // polling frequency in seconds (4s)
    };
  }

  /**
   * Resolves a manual 6-character TV pairing code to its device token.
   */
  resolveTokenByUserCode(userCode) {
    if (!userCode) return null;
    const norm = String(userCode).trim().toUpperCase();
    return this.userCodeIndex.get(norm) || null;
  }

  /**
   * Verifies and pairs a mobile user to an existing device token.
   */
  verifyDevice(deviceToken, userId, userInfo = {}, authTokens = {}) {
    if (!deviceToken || !userId) {
      return { success: false, error: 'Missing device_token or user_id', code: 'INVALID_REQUEST' };
    }

    const session = this.sessions.get(deviceToken);
    if (!session) {
      return { success: false, error: 'Device session not found or already completed', code: 'NOT_FOUND' };
    }

    if (Date.now() > session.expiresAt) {
      this._deleteSession(deviceToken, session);
      return { success: false, error: 'Device pairing session has expired', code: 'EXPIRED_TOKEN' };
    }

    if (session.status === 'verified') {
      return { success: false, error: 'Device session has already been paired', code: 'ALREADY_VERIFIED' };
    }

    // Pair the mobile user to the TV device session
    session.status = 'verified';
    session.pairedUserId = userId;
    session.pairedUserInfo = userInfo;
    session.authTokens = authTokens;
    session.verifiedAt = Date.now();

    return {
      success: true,
      message: 'TV device paired successfully',
      pairedUserId: userId,
      userCode: session.userCode,
    };
  }

  /**
   * Checks the status of a device authorization session.
   * Once verified, consumes and removes the session immediately so auth_tokens are single-use.
   */
  checkSessionStatus(deviceToken) {
    if (!deviceToken) {
      return { status: 'invalid', error: 'Missing device_token' };
    }

    const session = this.sessions.get(deviceToken);
    if (!session) {
      return { status: 'expired', error: 'Session not found or expired' };
    }

    if (Date.now() > session.expiresAt) {
      this._deleteSession(deviceToken, session);
      return { status: 'expired', error: 'Session expired' };
    }

    if (session.status === 'verified') {
      const payload = {
        status: 'verified',
        user_id: session.pairedUserId,
        user_info: session.pairedUserInfo,
        session_token: session.sessionToken,
        auth_tokens: session.authTokens,
      };
      // Consume immediately so sensitive auth_tokens cannot be polled repeatedly
      this._deleteSession(deviceToken, session);
      return payload;
    }

    return {
      status: 'pending',
      expires_in: Math.max(0, Math.floor((session.expiresAt - Date.now()) / 1000)),
      interval: this.POLL_INTERVAL_SECONDS,
    };
  }

  _deleteSession(deviceToken, session) {
    this.sessions.delete(deviceToken);
    if (session?.userCode) {
      this.userCodeIndex.delete(session.userCode);
    }
  }

  /**
   * Cleans up expired sessions from memory
   */
  cleanupExpiredSessions() {
    const now = Date.now();
    for (const [token, session] of this.sessions.entries()) {
      if (now > session.expiresAt) {
        this._deleteSession(token, session);
      }
    }
  }
}

export const deviceAuthService = new DeviceAuthService();
