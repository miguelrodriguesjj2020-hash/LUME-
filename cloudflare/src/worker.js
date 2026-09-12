import { passwordMac, signMedia, signSession, verifyMedia, verifySession } from './crypto.js';
import { shouldAcceptProgress, validateCatalogManifest, validateProgress } from './catalog.js';
import { proxyDriveFile, driveMediaMode } from './drive.js';

const jsonHeaders = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' };
const json = (status, value) => new Response(value === undefined ? null : JSON.stringify(value), { status, headers: jsonHeaders });

function strong(secret) { return typeof secret === 'string' && secret.length >= 32; }
export function runtimeReady(env) {
  const issues = [];
  if (!env.DB) issues.push('DB binding missing');
  if (!strong(env.AUTH_SECRET)) issues.push('AUTH_SECRET must be at least 32 characters');
  if (!strong(env.MEDIA_SECRET)) issues.push('MEDIA_SECRET must be at least 32 characters');
  if (!strong(env.PASSWORD_PEPPER)) issues.push('PASSWORD_PEPPER must be at least 32 characters');
  return { ok: issues.length === 0, issues, mediaMode: driveMediaMode(env) };
}

async function readJson(request) {
  const type = request.headers.get('content-type') || '';
  if (!type.toLowerCase().includes('application/json')) throw new Error('invalid_json');
  try { return await request.json(); } catch { throw new Error('invalid_json'); }
}
function bearer(request) {
  const h = request.headers.get('authorization') || '';
  return /^Bearer\s+(.+)$/i.exec(h)?.[1] || null;
}
async function auth(request, env) { return verifySession(bearer(request), env.AUTH_SECRET); }
function canAccessProfile(session, profile) { return session && (session.role === 'admin' || session.sub === profile); }

async function getRevision(db) {
  const row = await db.prepare("SELECT v FROM state WHERE k='revision'").first();
  return row ? Number(row.v) : 1;
}
async function sha256Hex(value) {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)));
  return [...digest].map(b => b.toString(16).padStart(2, '0')).join('');
}

async function installCatalog(db, manifest) {
  validateCatalogManifest(manifest);
  const revision = await getRevision(db);
  const catalogJson = JSON.stringify({ works: manifest.works, tombstones: manifest.tombstones || [] });
  const incomingHash = await sha256Hex(catalogJson);
  const priorHash = await db.prepare("SELECT v FROM state WHERE k='catalog_hash'").first();
  if (manifest.revision < revision) throw new Error('stale revision');
  if (manifest.revision === revision && priorHash) {
    if (priorHash.v !== incomingHash) throw new Error('revision reuse with different catalog');
    return revision;
  }
  const statements = [
    db.prepare('DELETE FROM works'), db.prepare('DELETE FROM tombstones'), db.prepare('DELETE FROM media')
  ];
  manifest.works.forEach((w, ordinal) => {
    statements.push(db.prepare('INSERT INTO works(id,ordinal,json) VALUES(?,?,?)').bind(w.id, ordinal, JSON.stringify(w)));
    for (const e of w.editions) {
      statements.push(db.prepare('INSERT INTO media(edition,source_file_id,file_name,format,byte_size,etag,sha256) VALUES(?,?,?,?,?,?,?)')
        .bind(e.id, e.sourceFileId, e.fileName, e.format, e.byteSize ?? null, e.etag ?? null, e.sha256 ?? null));
    }
  });
  (manifest.tombstones || []).forEach((t, ordinal) => statements.push(
    db.prepare('INSERT INTO tombstones(ordinal,json) VALUES(?,?)').bind(ordinal, JSON.stringify(t))
  ));
  statements.push(db.prepare("INSERT INTO state(k,v) VALUES('revision',?) ON CONFLICT(k) DO UPDATE SET v=excluded.v").bind(String(manifest.revision)));
  statements.push(db.prepare("INSERT INTO state(k,v) VALUES('catalog_hash',?) ON CONFLICT(k) DO UPDATE SET v=excluded.v").bind(incomingHash));
  await db.batch(statements);
  return manifest.revision;
}

async function bootstrap(db, since) {
  const revision = await getRevision(db);
  if (Number(since) === revision) return null;
  const works = (await db.prepare('SELECT json FROM works ORDER BY ordinal').all()).results.map(r => JSON.parse(r.json));
  const tombstones = (await db.prepare('SELECT json FROM tombstones ORDER BY ordinal').all()).results.map(r => JSON.parse(r.json));
  return { revision, full: true, works, tombstones };
}

async function currentProgress(db, profile, edition) {
  const row = await db.prepare('SELECT json FROM progress WHERE profile=? AND edition=?').bind(profile, edition).first();
  return row ? JSON.parse(row.json) : null;
}

async function putProgress(db, profile, edition, p) {
  validateProgress(edition, p);
  const priorOp = await db.prepare('SELECT edition FROM ops WHERE profile=? AND op_id=?').bind(profile, p.opId).first();
  if (priorOp) {
    if (priorOp.edition !== edition) throw new Error('opId reused for different edition');
    return { duplicate: true, current: await currentProgress(db, profile, edition) };
  }
  const old = await currentProgress(db, profile, edition);
  const incoming = { ...p, profileId: profile, editionId: edition };
  const accept = shouldAcceptProgress(old, incoming);
  const statements = [db.prepare('INSERT INTO ops(profile,op_id,edition) VALUES(?,?,?)').bind(profile, p.opId, edition)];
  if (accept) {
    statements.push(db.prepare(`INSERT INTO progress(profile,edition,json,client_updated_at,completed) VALUES(?,?,?,?,?)
      ON CONFLICT(profile,edition) DO UPDATE SET json=excluded.json,client_updated_at=excluded.client_updated_at,completed=excluded.completed`)
      .bind(profile, edition, JSON.stringify(incoming), incoming.clientUpdatedAt, incoming.completed ? 1 : 0));
    statements.push(db.prepare('INSERT INTO events(profile,edition,json) VALUES(?,?,?)').bind(profile, edition, JSON.stringify(incoming)));
  }
  try { await db.batch(statements); }
  catch (e) {
    const duplicate = await db.prepare('SELECT edition FROM ops WHERE profile=? AND op_id=?').bind(profile, p.opId).first();
    if (duplicate) {
      if (duplicate.edition !== edition) throw new Error('opId reused for different edition');
      return { duplicate: true, current: await currentProgress(db, profile, edition) };
    }
    throw e;
  }
  let seq;
  if (accept) seq = (await db.prepare('SELECT MAX(seq) AS seq FROM events WHERE profile=? AND edition=?').bind(profile, edition).first())?.seq;
  return { duplicate: false, accepted: accept, ...(seq ? { seq } : {}), current: accept ? incoming : old };
}

async function sync(db, profile, cursor, ops) {
  const after = Number(cursor || 0);
  const max = Number((await db.prepare('SELECT COALESCE(MAX(seq),0) AS maxSeq FROM events').first()).maxSeq || 0);
  if (!Number.isInteger(after) || after < 0 || after > max) throw new Error('invalid cursor');
  const ack = [], rejected = [];
  for (const op of Array.isArray(ops) ? ops : []) {
    if (!op || op.kind !== 'progress') { if (op?.opId) rejected.push({ opId: op.opId, reason: 'unsupported operation' }); continue; }
    try { await putProgress(db, profile, op.editionId, op); ack.push(op.opId); }
    catch (e) { if (op?.opId) rejected.push({ opId: op.opId, reason: e.message || 'invalid operation' }); }
  }
  const rows = (await db.prepare('SELECT seq,edition,json FROM events WHERE profile=? AND seq>? ORDER BY seq').bind(profile, after).all()).results;
  const events = rows.map(r => ({ seq: r.seq, profile, edition: r.edition, payload: JSON.parse(r.json) }));
  return { cursor: String(events.length ? events.at(-1).seq : after), events, ack, rejected };
}

async function descriptor(request, env, editionId) {
  const meta = await env.DB.prepare('SELECT * FROM media WHERE edition=?').bind(editionId).first();
  if (!meta) return null;
  const expiresAt = Date.now() + 300_000;
  const sig = await signMedia(editionId, expiresAt, env.MEDIA_SECRET);
  const origin = new URL(request.url).origin;
  return {
    strategy: 'signed', editionId, expiresAt, token: sig,
    byteSize: meta.byte_size ?? undefined, etag: meta.etag ?? undefined, sha256: meta.sha256 ?? undefined,
    url: `${origin}/v1/media-bytes/${encodeURIComponent(editionId)}?expires=${expiresAt}&sig=${encodeURIComponent(sig)}`
  };
}

export async function route(request, env) {
  const url = new URL(request.url), path = url.pathname;
  if (request.method === 'GET' && path === '/v1/health') return json(200, { ok: true, service: 'lume', protocol: 1 });
  if (request.method === 'GET' && path === '/v1/ready') {
    const ready = runtimeReady(env);
    if (!ready.ok) return json(503, { ok: false, durable: true, backend: 'cloudflare-d1', mediaMode: ready.mediaMode, issues: ready.issues });
    try { await env.DB.prepare('SELECT 1 AS ok').first(); return json(200, { ok: true, durable: true, backend: 'cloudflare-d1', mediaMode: ready.mediaMode, revision: await getRevision(env.DB) }); }
    catch { return json(503, { ok: false, durable: true, backend: 'cloudflare-d1', mediaMode: ready.mediaMode, issues: ['D1 unavailable'] }); }
  }
  if (request.method === 'POST' && path === '/v1/auth/login') {
    if (!runtimeReady(env).ok) return json(503, { error: 'auth_not_configured' });
    let body; try { body = await readJson(request); } catch { return json(400, { error: 'invalid_json' }); }
    const username = String(body.username || '').trim();
    const user = await env.DB.prepare('SELECT username,profile_id,role,password_mac,active FROM users WHERE username=?').bind(username).first();
    if (!user || !user.active) return json(401, { error: 'invalid_credentials' });
    const mac = await passwordMac(env.PASSWORD_PEPPER, String(body.password || ''));
    if (mac !== user.password_mac) return json(401, { error: 'invalid_credentials' });
    const expiresAt = Date.now() + 8 * 60 * 60 * 1000;
    const token = await signSession({ sub: user.profile_id, role: user.role, exp: expiresAt }, env.AUTH_SECRET);
    return json(200, { token, profileId: user.profile_id, role: user.role, expiresAt });
  }

  const session = await auth(request, env);
  if (request.method === 'GET' && path === '/v1/bootstrap') {
    if (!session) return json(401, { error: 'unauthorized' });
    const value = await bootstrap(env.DB, url.searchParams.get('since'));
    return value ? json(200, value) : new Response(null, { status: 304, headers: { 'cache-control': 'no-store' } });
  }
  if (request.method === 'POST' && path === '/v1/admin/catalog') {
    if (!session) return json(401, { error: 'unauthorized' });
    if (session.role !== 'admin') return json(403, { error: 'forbidden' });
    let body; try { body = await readJson(request); } catch { return json(400, { error: 'invalid_json' }); }
    try { return json(200, { revision: await installCatalog(env.DB, body) }); }
    catch (e) { return json(409, { error: e.message || 'catalog_conflict' }); }
  }

  const sm = path.match(/^\/v1\/profiles\/([^/]+)\/sync$/);
  if (request.method === 'POST' && sm) {
    if (!session) return json(401, { error: 'unauthorized' });
    const profile = decodeURIComponent(sm[1]); if (!canAccessProfile(session, profile)) return json(403, { error: 'forbidden' });
    let body; try { body = await readJson(request); } catch { return json(400, { error: 'invalid_json' }); }
    try { return json(200, await sync(env.DB, profile, body.cursor, body.ops)); }
    catch (e) { return json(409, { error: e.message || 'sync_conflict' }); }
  }
  const pm = path.match(/^\/v1\/profiles\/([^/]+)\/progress\/([^/]+)$/);
  if (pm) {
    if (!session) return json(401, { error: 'unauthorized' });
    const profile = decodeURIComponent(pm[1]), edition = decodeURIComponent(pm[2]);
    if (!canAccessProfile(session, profile)) return json(403, { error: 'forbidden' });
    if (request.method === 'GET') { const p = await currentProgress(env.DB, profile, edition); return p ? json(200, p) : json(404, { error: 'not_found' }); }
    if (request.method === 'PUT') {
      let body; try { body = await readJson(request); } catch { return json(400, { error: 'invalid_json' }); }
      try { return json(200, await putProgress(env.DB, profile, edition, body)); }
      catch (e) { return json(400, { error: e.message || 'invalid_progress' }); }
    }
  }
  const mm = path.match(/^\/v1\/media\/([^/]+)$/);
  if (request.method === 'GET' && mm) {
    if (!session) return json(401, { error: 'unauthorized' });
    const d = await descriptor(request, env, decodeURIComponent(mm[1]));
    return d ? json(200, d) : json(404, { error: 'media_not_found' });
  }
  const mb = path.match(/^\/v1\/media-bytes\/([^/]+)$/);
  if ((request.method === 'GET' || request.method === 'HEAD') && mb) {
    const edition = decodeURIComponent(mb[1]);
    const expires = Number(url.searchParams.get('expires'));
    if (!await verifyMedia(edition, expires, url.searchParams.get('sig'), env.MEDIA_SECRET)) return json(403, { error: 'invalid_media_signature' });
    const meta = await env.DB.prepare('SELECT source_file_id FROM media WHERE edition=?').bind(edition).first();
    if (!meta) return json(404, { error: 'media_not_found' });
    try { return await proxyDriveFile(request, env, meta.source_file_id); }
    catch { return json(502, { error: 'media_upstream_unavailable' }); }
  }
  return json(404, { error: 'not_found' });
}

export default {
  async fetch(request, env) {
    try { return await route(request, env); }
    catch (e) {
      console.error(JSON.stringify({ event: 'request_error', message: e?.message || String(e) }));
      return json(500, { error: 'internal_error' });
    }
  }
};
