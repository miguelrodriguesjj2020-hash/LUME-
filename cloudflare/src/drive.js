import { bytesToBase64Url } from './crypto.js';

const te = new TextEncoder();
let cachedToken = null;

function pemToBytes(pem) {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '').replace(/\s+/g, '');
  const raw = atob(body);
  return Uint8Array.from(raw, c => c.charCodeAt(0));
}

async function serviceAccountJwt(email, privateKeyPem, nowSeconds) {
  const header = bytesToBase64Url(te.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })));
  const claims = bytesToBase64Url(te.encode(JSON.stringify({
    iss: email,
    scope: 'https://www.googleapis.com/auth/drive.readonly',
    aud: 'https://oauth2.googleapis.com/token',
    iat: nowSeconds,
    exp: nowSeconds + 3600
  })));
  const input = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    'pkcs8', pemToBytes(privateKeyPem), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = new Uint8Array(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, te.encode(input)));
  return `${input}.${bytesToBase64Url(sig)}`;
}

export function driveMediaMode(env) {
  return env?.GDRIVE_CLIENT_EMAIL && env?.GDRIVE_PRIVATE_KEY ? 'drive-api' : 'drive-public';
}

export async function getDriveAccessToken(env, now = Date.now()) {
  if (cachedToken && cachedToken.expiresAt > now + 60_000) return cachedToken.value;
  if (!env.GDRIVE_CLIENT_EMAIL || !env.GDRIVE_PRIVATE_KEY) throw new Error('drive_not_configured');
  const assertion = await serviceAccountJwt(env.GDRIVE_CLIENT_EMAIL, env.GDRIVE_PRIVATE_KEY, Math.floor(now / 1000));
  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion
  });
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body
  });
  if (!response.ok) throw new Error(`drive_token_failed:${response.status}`);
  const json = await response.json();
  if (!json.access_token) throw new Error('drive_token_missing');
  cachedToken = { value: json.access_token, expiresAt: now + Math.max(60, Number(json.expires_in || 3600)) * 1000 };
  return cachedToken.value;
}

function forwardedHeaders(request, authorization) {
  const headers = new Headers();
  if (authorization) headers.set('authorization', authorization);
  for (const h of ['range', 'if-range']) {
    const value = request.headers.get(h);
    if (value) headers.set(h, value);
  }
  return headers;
}

function toMediaResponse(request, upstream) {
  const out = new Headers();
  for (const h of ['content-type', 'content-length', 'content-range', 'accept-ranges', 'etag', 'last-modified', 'content-disposition']) {
    const value = upstream.headers.get(h);
    if (value) out.set(h, value);
  }
  out.set('cache-control', 'private, no-store');
  return new Response(request.method === 'HEAD' ? null : upstream.body, { status: upstream.status, headers: out });
}

async function proxyAuthenticatedDrive(request, env, fileId) {
  const token = await getDriveAccessToken(env);
  const upstream = await fetch(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}?alt=media&supportsAllDrives=true`, {
    method: request.method === 'HEAD' ? 'HEAD' : 'GET',
    headers: forwardedHeaders(request, `Bearer ${token}`)
  });
  return toMediaResponse(request, upstream);
}

async function proxyPublicDrive(request, fileId) {
  const url = new URL('https://drive.usercontent.google.com/download');
  url.searchParams.set('id', fileId);
  url.searchParams.set('export', 'download');
  url.searchParams.set('confirm', 't');
  const headers = forwardedHeaders(request);
  // Google public downloads are more consistent with GET than HEAD. For HEAD
  // requests ask for one byte upstream, but still return an empty response body.
  if (request.method === 'HEAD' && !headers.has('range')) headers.set('range', 'bytes=0-0');
  const upstream = await fetch(url, { method: 'GET', headers, redirect: 'follow' });
  return toMediaResponse(request, upstream);
}

export async function proxyDriveFile(request, env, fileId) {
  if (env?.GDRIVE_CLIENT_EMAIL && env?.GDRIVE_PRIVATE_KEY) {
    try {
      const response = await proxyAuthenticatedDrive(request, env, fileId);
      if (response.status !== 401 && response.status !== 403 && response.status < 500) return response;
    } catch (error) {
      console.warn(JSON.stringify({ event: 'drive_api_fallback', message: error?.message || String(error) }));
    }
  }
  return proxyPublicDrive(request, fileId);
}
