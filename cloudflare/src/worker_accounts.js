import { hmacHex, passwordMac, signSession, verifySession, constantTimeEqual } from './crypto.js';
import { route as coreRoute } from './worker.js';

export const MAX_PROFILES = 91;
const jsonHeaders = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' };
const json = (status, value) => new Response(value === undefined ? null : JSON.stringify(value), { status, headers: jsonHeaders });

function strong(secret) { return typeof secret === 'string' && secret.length >= 32; }
function authReady(env) {
  return Boolean(env.DB && strong(env.AUTH_SECRET) && strong(env.PASSWORD_PEPPER));
}

function cleanText(value, max) {
  return String(value ?? '').replace(/[\u0000-\u001F\u007F]/g, '').trim().replace(/\s+/g, ' ').slice(0, max);
}
function normalizeUsername(value) { return String(value ?? '').trim().toLowerCase(); }
function validUsername(value) { return /^[a-z0-9._-]{3,24}$/.test(value); }
function validPassword(value) { return typeof value === 'string' && value.length >= 8 && value.length <= 128; }
function randomId(bytes = 16) {
  const data = new Uint8Array(bytes);
  crypto.getRandomValues(data);
  return [...data].map(b => b.toString(16).padStart(2, '0')).join('');
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

export async function passwordMacV2(pepper, username, salt, password) {
  return hmacHex(pepper, `lume-password-v2:${username}:${salt}:${password}`);
}

async function sessionFromRequest(request, env, { requireActive = true } = {}) {
  const session = await verifySession(bearer(request), env.AUTH_SECRET);
  if (!session) return null;
  if (!requireActive) return session;
  const user = await env.DB.prepare('SELECT active,role FROM users WHERE profile_id=?').bind(session.sub).first();
  if (!user || !user.active) return null;
  return session;
}

async function requireAdmin(request, env) {
  const session = await sessionFromRequest(request, env);
  return session?.role === 'admin' ? session : null;
}

async function login(request, env) {
  if (!authReady(env)) return json(503, { error: 'auth_not_configured' });
  let body; try { body = await readJson(request); } catch { return json(400, { error: 'invalid_json' }); }
  const username = normalizeUsername(body.username);
  const password = String(body.password ?? '');
  const user = await env.DB.prepare(`SELECT username,profile_id,role,password_mac,active,
      COALESCE(auth_salt,'') AS auth_salt,
      COALESCE(auth_scheme,'hmac-sha256-pepper-v1') AS auth_scheme
    FROM users WHERE username=?`).bind(username).first();
  if (!user) return json(401, { error: 'invalid_credentials' });
  if (!user.active) return json(403, { error: 'account_disabled' });
  const expected = user.auth_scheme === 'hmac-sha256-pepper-v2'
    ? await passwordMacV2(env.PASSWORD_PEPPER, user.username, user.auth_salt, password)
    : await passwordMac(env.PASSWORD_PEPPER, password);
  if (!constantTimeEqual(expected, user.password_mac)) return json(401, { error: 'invalid_credentials' });
  const now = Date.now();
  const expiresAt = now + 8 * 60 * 60 * 1000;
  const token = await signSession({ sub: user.profile_id, role: user.role, exp: expiresAt }, env.AUTH_SECRET);
  await env.DB.prepare('UPDATE users SET last_login_at=?, session_expires_at=? WHERE username=?').bind(now, expiresAt, username).run();
  return json(200, { token, profileId: user.profile_id, role: user.role, expiresAt });
}

async function register(request, env) {
  if (!authReady(env)) return json(503, { error: 'auth_not_configured' });
  let body; try { body = await readJson(request); } catch { return json(400, { error: 'invalid_json' }); }
  const fullName = cleanText(body.fullName, 80);
  const username = normalizeUsername(body.username);
  const password = String(body.password ?? '');
  const className = cleanText(body.className, 40);
  if (fullName.length < 2) return json(400, { error: 'invalid_registration', field: 'fullName', message: 'Informe seu nome verdadeiro.' });
  if (!validUsername(username)) return json(400, { error: 'invalid_registration', field: 'username', message: 'O usuário deve ter de 3 a 24 caracteres válidos.' });
  if (!validPassword(password)) return json(400, { error: 'invalid_registration', field: 'password', message: 'A senha precisa ter pelo menos 8 caracteres.' });
  if (!className) return json(400, { error: 'invalid_registration', field: 'className', message: 'Informe sua turma.' });

  const salt = randomId(16);
  const profileId = `usr_${randomId(16)}`;
  const mac = await passwordMacV2(env.PASSWORD_PEPPER, username, salt, password);
  const now = Date.now();
  let result;
  try {
    result = await env.DB.prepare(`INSERT OR IGNORE INTO users(
        username,profile_id,role,password_mac,active,full_name,class_name,auth_salt,auth_scheme,created_at
      )
      SELECT ?,?,'consumer',?,1,?,?,?,'hmac-sha256-pepper-v2',?
      WHERE (SELECT COUNT(*) FROM users WHERE active=1) < ?`)
      .bind(username, profileId, mac, fullName, className, salt, now, MAX_PROFILES).run();
  } catch (e) {
    console.error(JSON.stringify({ event: 'register_insert_error', message: e?.message || String(e) }));
    return json(500, { error: 'registration_failed' });
  }
  if (Number(result?.meta?.changes || 0) === 1) {
    const activeCount = Number((await env.DB.prepare('SELECT COUNT(*) AS c FROM users WHERE active=1').first())?.c || 0);
    return json(201, { ok: true, username, profileId, activeCount, maxUsers: MAX_PROFILES });
  }
  const existing = await env.DB.prepare('SELECT 1 AS found FROM users WHERE username=?').bind(username).first();
  if (existing) return json(409, { error: 'username_taken' });
  const activeCount = Number((await env.DB.prepare('SELECT COUNT(*) AS c FROM users WHERE active=1').first())?.c || 0);
  if (activeCount >= MAX_PROFILES) return json(409, {
    error: 'user_limit_reached',
    message: 'Número máximo de usuários atingido, busque contato com um membro do grêmio para entender.',
    activeCount,
    maxUsers: MAX_PROFILES,
  });
  return json(409, { error: 'registration_conflict' });
}

async function listUsers(request, env) {
  if (!await requireAdmin(request, env)) return json(403, { error: 'forbidden' });
  const now = Date.now();
  const rows = (await env.DB.prepare(`SELECT username,profile_id,role,active,
      COALESCE(full_name,username) AS full_name,
      class_name,created_at,last_login_at,session_expires_at
    FROM users
    ORDER BY CASE WHEN role='admin' THEN 0 ELSE 1 END, active DESC, full_name COLLATE NOCASE, username`).all()).results;
  const activeCount = rows.reduce((n, r) => n + (r.active ? 1 : 0), 0);
  return json(200, {
    activeCount,
    maxUsers: MAX_PROFILES,
    users: rows.map(r => ({
      username: r.username,
      profileId: r.profile_id,
      role: r.role,
      active: Boolean(r.active),
      fullName: r.full_name,
      className: r.class_name,
      createdAt: r.created_at || null,
      lastLoginAt: r.last_login_at || null,
      sessionActive: Boolean(r.active && r.session_expires_at && Number(r.session_expires_at) > now),
    })),
  });
}

async function setUserStatus(request, env, rawUsername) {
  if (!await requireAdmin(request, env)) return json(403, { error: 'forbidden' });
  let body; try { body = await readJson(request); } catch { return json(400, { error: 'invalid_json' }); }
  if (typeof body.active !== 'boolean') return json(400, { error: 'invalid_active_state' });
  const username = normalizeUsername(decodeURIComponent(rawUsername));
  const target = await env.DB.prepare('SELECT username,role,active FROM users WHERE username=?').bind(username).first();
  if (!target) return json(404, { error: 'user_not_found' });
  if (target.role === 'admin') return json(409, { error: 'admin_cannot_be_disabled' });
  if (Boolean(target.active) === body.active) return json(200, { ok: true, username, active: body.active });

  if (!body.active) {
    await env.DB.prepare('UPDATE users SET active=0,session_expires_at=NULL WHERE username=? AND role<>\'admin\'').bind(username).run();
    return json(200, { ok: true, username, active: false });
  }

  const result = await env.DB.prepare(`UPDATE users SET active=1
      WHERE username=? AND active=0 AND role<>'admin'
        AND (SELECT COUNT(*) FROM users WHERE active=1) < ?`)
    .bind(username, MAX_PROFILES).run();
  if (Number(result?.meta?.changes || 0) !== 1) {
    const activeCount = Number((await env.DB.prepare('SELECT COUNT(*) AS c FROM users WHERE active=1').first())?.c || 0);
    if (activeCount >= MAX_PROFILES) return json(409, {
      error: 'user_limit_reached',
      message: 'Número máximo de usuários atingido, busque contato com um membro do grêmio para entender.',
      activeCount,
      maxUsers: MAX_PROFILES,
    });
    return json(409, { error: 'user_status_conflict' });
  }
  return json(200, { ok: true, username, active: true });
}

function isPublicCorePath(request, path) {
  if (path === '/v1/health' || path === '/v1/ready') return true;
  if (/^\/v1\/media-bytes\/[^/]+$/.test(path) && (request.method === 'GET' || request.method === 'HEAD')) return true;
  return false;
}

export async function route(request, env) {
  const url = new URL(request.url);
  const path = url.pathname;
  if (request.method === 'POST' && path === '/v1/auth/register') return register(request, env);
  if (request.method === 'POST' && path === '/v1/auth/login') return login(request, env);
  if (request.method === 'GET' && path === '/v1/admin/users') return listUsers(request, env);
  const um = path.match(/^\/v1\/admin\/users\/([^/]+)$/);
  if (request.method === 'PATCH' && um) return setUserStatus(request, env, um[1]);

  if (!isPublicCorePath(request, path)) {
    const token = bearer(request);
    if (token) {
      const raw = await verifySession(token, env.AUTH_SECRET);
      if (raw) {
        const user = await env.DB.prepare('SELECT active FROM users WHERE profile_id=?').bind(raw.sub).first();
        if (!user || !user.active) return json(401, { error: 'account_disabled' });
      }
    }
  }
  return coreRoute(request, env);
}

export default {
  async fetch(request, env) {
    try { return await route(request, env); }
    catch (e) {
      console.error(JSON.stringify({ event: 'request_error_accounts', message: e?.message || String(e) }));
      return json(500, { error: 'internal_error' });
    }
  }
};
