import { route as accountRoute } from './worker_accounts.js';
import { verifyMedia } from './crypto.js';
import { proxyDriveFile, driveMediaMode } from './drive_public.js';

const jsonHeaders = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' };
const json = (status, value) => new Response(value === undefined ? null : JSON.stringify(value), { status, headers: jsonHeaders });

function productionReady(env) {
  const issues = [];
  if (!env.DB) issues.push('DB binding missing');
  for (const name of ['AUTH_SECRET', 'MEDIA_SECRET', 'PASSWORD_PEPPER']) {
    if (typeof env[name] !== 'string' || env[name].length < 32) issues.push(`${name} is not configured`);
  }
  return { ok: issues.length === 0, issues };
}

async function ready(env) {
  const state = productionReady(env);
  if (!state.ok) return json(503, { ok: false, durable: true, backend: 'cloudflare-d1', mediaMode: driveMediaMode(), issues: state.issues });
  try {
    const row = await env.DB.prepare("SELECT v FROM state WHERE k='revision'").first();
    return json(200, { ok: true, durable: true, backend: 'cloudflare-d1', mediaMode: driveMediaMode(), revision: row ? Number(row.v) : 1 });
  } catch {
    return json(503, { ok: false, durable: true, backend: 'cloudflare-d1', mediaMode: driveMediaMode(), issues: ['D1 unavailable'] });
  }
}

async function publicMedia(request, env, edition) {
  const url = new URL(request.url);
  const expires = Number(url.searchParams.get('expires'));
  const signature = url.searchParams.get('sig');
  if (!await verifyMedia(edition, expires, signature, env.MEDIA_SECRET)) return json(403, { error: 'invalid_media_signature' });
  const meta = await env.DB.prepare('SELECT source_file_id FROM media WHERE edition=?').bind(edition).first();
  if (!meta) return json(404, { error: 'media_not_found' });
  try { return await proxyDriveFile(request, env, meta.source_file_id); }
  catch (error) {
    console.error(JSON.stringify({ event: 'public_drive_error', message: error?.message || String(error) }));
    return json(502, { error: 'media_upstream_unavailable' });
  }
}

export async function route(request, env) {
  const url = new URL(request.url);
  if (request.method === 'GET' && url.pathname === '/v1/ready') return ready(env);
  const media = url.pathname.match(/^\/v1\/media-bytes\/([^/]+)$/);
  if (media && (request.method === 'GET' || request.method === 'HEAD')) return publicMedia(request, env, decodeURIComponent(media[1]));
  return accountRoute(request, env);
}

export default {
  async fetch(request, env) {
    try { return await route(request, env); }
    catch (error) {
      console.error(JSON.stringify({ event: 'request_error_production', message: error?.message || String(error) }));
      return json(500, { error: 'internal_error' });
    }
  }
};
