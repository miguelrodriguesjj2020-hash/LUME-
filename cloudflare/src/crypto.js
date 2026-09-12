const te = new TextEncoder();
const td = new TextDecoder();

export function bytesToBase64Url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

export function base64UrlToBytes(value) {
  const s = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = s + '='.repeat((4 - (s.length % 4)) % 4);
  const raw = atob(padded);
  return Uint8Array.from(raw, c => c.charCodeAt(0));
}

export function encodeJsonBase64Url(value) {
  return bytesToBase64Url(te.encode(JSON.stringify(value)));
}

export function decodeJsonBase64Url(value) {
  return JSON.parse(td.decode(base64UrlToBytes(value)));
}

async function hmacBytes(secret, message) {
  const key = await crypto.subtle.importKey(
    'raw', te.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, te.encode(message)));
}

export async function hmacHex(secret, message) {
  const bytes = await hmacBytes(secret, message);
  return [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
}

export async function hmacBase64Url(secret, message) {
  return bytesToBase64Url(await hmacBytes(secret, message));
}

export function constantTimeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function passwordMac(pepper, password) {
  return hmacHex(pepper, `lume-password-v1:${password}`);
}

export async function signSession(payload, secret) {
  const body = encodeJsonBase64Url(payload);
  return `${body}.${await hmacBase64Url(secret, `lume-session-v1:${body}`)}`;
}

export async function verifySession(token, secret, now = Date.now()) {
  if (!token || !secret) return null;
  const [body, sig, extra] = String(token).split('.');
  if (!body || !sig || extra !== undefined) return null;
  const expected = await hmacBase64Url(secret, `lume-session-v1:${body}`);
  if (!constantTimeEqual(sig, expected)) return null;
  try {
    const payload = decodeJsonBase64Url(body);
    if (!payload || typeof payload.sub !== 'string' || !payload.sub) return null;
    if (!['consumer', 'admin'].includes(payload.role)) return null;
    if (!Number.isInteger(payload.exp) || payload.exp <= now) return null;
    return payload;
  } catch { return null; }
}

export async function signMedia(editionId, expiresAt, secret) {
  return hmacBase64Url(secret, `lume-media-v1:${editionId}:${expiresAt}`);
}

export async function verifyMedia(editionId, expiresAt, signature, secret, now = Date.now()) {
  if (!Number.isInteger(expiresAt) || expiresAt <= now || expiresAt > now + 10 * 60 * 1000) return false;
  const expected = await signMedia(editionId, expiresAt, secret);
  return constantTimeEqual(String(signature || ''), expected);
}
