import test from 'node:test';
import assert from 'node:assert/strict';
import { deviceAuthService } from '../src/services/deviceAuthService.js';

test('DeviceAuthService - creates valid device code session', () => {
  const session = deviceAuthService.createDeviceCodeSession('https://test.barroomstrivia.com');
  
  assert.ok(session.device_token);
  assert.ok(session.session_token);
  assert.ok(session.user_code);
  assert.ok(session.verification_url.includes('/tv-auth?device_token='));
  assert.strictEqual(session.interval, 4);
  assert.strictEqual(session.expires_in, 300);

  // Status check before verification
  const status = deviceAuthService.checkSessionStatus(session.device_token);
  assert.strictEqual(status.status, 'pending');
});

test('DeviceAuthService - verifies and pairs mobile user', () => {
  const session = deviceAuthService.createDeviceCodeSession('https://test.barroomstrivia.com');
  
  const verifyResult = deviceAuthService.verifyDevice(
    session.device_token,
    'user-uuid-12345',
    { email: 'host@barroomstrivia.com', name: 'Quiz Master' },
    { access_token: 'fake-jwt-token' }
  );

  assert.strictEqual(verifyResult.success, true);
  assert.strictEqual(verifyResult.pairedUserId, 'user-uuid-12345');

  // Status check after verification (single-use consumption)
  const status = deviceAuthService.checkSessionStatus(session.device_token);
  assert.strictEqual(status.status, 'verified');
  assert.strictEqual(status.user_id, 'user-uuid-12345');
  assert.strictEqual(status.user_info.email, 'host@barroomstrivia.com');

  // Second poll after consumption must NOT leak auth_tokens again
  const replayStatus = deviceAuthService.checkSessionStatus(session.device_token);
  assert.strictEqual(replayStatus.status, 'expired');
});

test('DeviceAuthService - rejects duplicate verify and resolves manual user_code', () => {
  const session = deviceAuthService.createDeviceCodeSession('https://test.barroomstrivia.com');
  assert.strictEqual(deviceAuthService.resolveTokenByUserCode(session.user_code), session.device_token);

  const first = deviceAuthService.verifyDevice(session.device_token, 'user-1');
  assert.strictEqual(first.success, true);

  const duplicate = deviceAuthService.verifyDevice(session.device_token, 'user-2');
  assert.strictEqual(duplicate.success, false);
  assert.strictEqual(duplicate.code, 'ALREADY_VERIFIED');
});

test('DeviceAuthService - rejects nonexistent or invalid device token', () => {
  const verifyResult = deviceAuthService.verifyDevice('invalid-token', 'user-123');
  assert.strictEqual(verifyResult.success, false);
  assert.strictEqual(verifyResult.code, 'NOT_FOUND');

  const status = deviceAuthService.checkSessionStatus('invalid-token');
  assert.strictEqual(status.status, 'expired');
});
