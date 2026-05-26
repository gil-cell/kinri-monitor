/**
 * APNs (Apple Push Notification service) クライアント
 * Cloudflare Worker から APNs HTTP/2 API を呼び出す
 */

export interface APNsConfig {
  teamId: string;
  keyId: string;
  privateKey: string;
  bundleId: string;
  production: boolean;
}

export interface APNsPayload {
  title: string;
  body: string;
  category?: string;
  data?: Record<string, string>;
}

async function createJWT(config: APNsConfig): Promise<string> {
  const header = { alg: 'ES256', kid: config.keyId };
  const now = Math.floor(Date.now() / 1000);
  const payload = { iss: config.teamId, iat: now };

  const headerB64 = base64url(JSON.stringify(header));
  const payloadB64 = base64url(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;

  const pemBody = config.privateKey
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');
  const der = Uint8Array.from(atob(pemBody), c => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    'pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']
  );

  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(signingInput)
  );

  return `${signingInput}.${base64url(derToRaw(new Uint8Array(sig)))}`;
}

function base64url(input: string | Uint8Array): string {
  const b64 = typeof input === 'string' ? btoa(input) : btoa(String.fromCharCode(...input));
  return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function derToRaw(der: Uint8Array): Uint8Array {
  let offset = 2;
  offset += 1;
  const rLen = der[offset++];
  const r = der.slice(offset, offset + rLen);
  offset += rLen + 1;
  const sLen = der[offset++];
  const s = der.slice(offset, offset + sLen);
  const raw = new Uint8Array(64);
  raw.set(r.length > 32 ? r.slice(r.length - 32) : r, 32 - Math.min(r.length, 32));
  raw.set(s.length > 32 ? s.slice(s.length - 32) : s, 64 - Math.min(s.length, 32));
  return raw;
}

export async function sendPush(
  deviceToken: string, payload: APNsPayload, config: APNsConfig,
): Promise<{ success: boolean; status: number; body: string }> {
  const jwt = await createJWT(config);
  const host = config.production
    ? 'https://api.push.apple.com'
    : 'https://api.sandbox.push.apple.com';

  const resp = await fetch(`${host}/3/device/${deviceToken}`, {
    method: 'POST',
    headers: {
      'authorization': `bearer ${jwt}`,
      'apns-topic': config.bundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      aps: {
        alert: { title: payload.title, body: payload.body },
        sound: 'default',
        ...(payload.category ? { category: payload.category } : {}),
      },
      ...(payload.data || {}),
    }),
  });

  return { success: resp.status === 200, status: resp.status, body: await resp.text() };
}

export async function sendPushToAll(
  tokens: string[], payload: APNsPayload, config: APNsConfig,
): Promise<{ sent: number; failed: number }> {
  let sent = 0, failed = 0;
  for (const token of tokens) {
    const r = await sendPush(token, payload, config);
    r.success ? sent++ : failed++;
  }
  return { sent, failed };
}
