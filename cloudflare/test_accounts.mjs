import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import { webcrypto } from 'node:crypto';

if (!globalThis.crypto) globalThis.crypto = webcrypto;
if (!globalThis.btoa) globalThis.btoa = s => Buffer.from(s, 'binary').toString('base64');
if (!globalThis.atob) globalThis.atob = s => Buffer.from(s, 'base64').toString('binary');

import { passwordMac } from './src/crypto.js';
import { MAX_PROFILES, route } from './src/worker_accounts.js';

const longTestValue = c => `unit-test-${c}-` + c.repeat(32);
const AUTH_SECRET = longTestValue('a');
const MEDIA_SECRET = longTestValue('m');
const PASSWORD_PEPPER = longTestValue('p');
const ADMIN_PASSWORD = 'admin-password-for-tests';

class D1Statement {
  constructor(db, sql, args = []) { this.db = db; this.sql = sql; this.args = args; }
  bind(...args) { return new D1Statement(this.db, this.sql, args); }
  async first() { return this.db.prepare(this.sql).get(...this.args) ?? null; }
  async all() { return { results: this.db.prepare(this.sql).all(...this.args) }; }
  async run() {
    const result = this.db.prepare(this.sql).run(...this.args);
    return { success: true, meta: { changes: Number(result.changes || 0), last_row_id: Number(result.lastInsertRowid || 0) } };
  }
}

class D1Database {
  constructor(raw) { this.raw = raw; }
  prepare(sql) { return new D1Statement(this.raw, sql); }
  async batch(statements) {
    this.raw.exec('BEGIN');
    try {
      const out = [];
      for (const statement of statements) out.push(await statement.run());
      this.raw.exec('COMMIT');
      return out;
    } catch (error) {
      this.raw.exec('ROLLBACK');
      throw error;
    }
  }
}

async function fixture() {
  const raw = new DatabaseSync(':memory:');
  raw.exec(readFileSync(new URL('./migrations/0001_initial.sql', import.meta.url), 'utf8'));
  raw.exec(readFileSync(new URL('./migrations/0002_self_service_accounts.sql', import.meta.url), 'utf8'));
  const adminMac = await passwordMac(PASSWORD_PEPPER, ADMIN_PASSWORD);
  raw.prepare(`INSERT INTO users(username,profile_id,role,password_mac,active,full_name,class_name,created_at)
    VALUES(?,?,?,?,1,?,?,?)`).run('admin', 'admin-lume', 'admin', adminMac, 'Administrador LUME', 'Administração', Date.now());
  return {
    raw,
    env: {
      DB: new D1Database(raw), AUTH_SECRET, MEDIA_SECRET, PASSWORD_PEPPER,
      GDRIVE_CLIENT_EMAIL: 'service@example.invalid', GDRIVE_PRIVATE_KEY: 'test-key',
    },
  };
}

function request(path, { method = 'GET', body, token } = {}) {
  const headers = {};
  if (body !== undefined) headers['content-type'] = 'application/json';
  if (token) headers.authorization = `Bearer ${token}`;
  return new Request(`https://lume.test${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
}

async function result(response) {
  return { status: response.status, body: response.status === 304 ? null : await response.json() };
}

async function login(env, username, password) {
  return result(await route(request('/v1/auth/login', { method: 'POST', body: { username, password } }), env));
}

test('self-service lifecycle exposes turma and immediately blocks disabled accounts', async () => {
  const { env } = await fixture();
  const adminLogin = await login(env, 'ADMIN', ADMIN_PASSWORD);
  assert.equal(adminLogin.status, 200);
  const adminToken = adminLogin.body.token;

  const created = await result(await route(request('/v1/auth/register', {
    method: 'POST', body: { fullName: 'João da Silva', username: 'Joao.Silva', password: 'senha-forte-123', className: '2º A' },
  }), env));
  assert.equal(created.status, 201);
  assert.equal(created.body.username, 'joao.silva');
  assert.equal(created.body.activeCount, 2);
  assert.equal(created.body.maxUsers, MAX_PROFILES);

  const duplicate = await result(await route(request('/v1/auth/register', {
    method: 'POST', body: { fullName: 'Outro Nome', username: 'joao.silva', password: 'outra-senha-123', className: '2º B' },
  }), env));
  assert.equal(duplicate.status, 409);
  assert.equal(duplicate.body.error, 'username_taken');

  const studentLogin = await login(env, 'JOAO.SILVA', 'senha-forte-123');
  assert.equal(studentLogin.status, 200);
  const studentToken = studentLogin.body.token;

  const listed = await result(await route(request('/v1/admin/users', { token: adminToken }), env));
  assert.equal(listed.status, 200);
  const student = listed.body.users.find(u => u.username === 'joao.silva');
  assert.equal(student.fullName, 'João da Silva');
  assert.equal(student.className, '2º A');
  assert.equal(student.active, true);
  assert.equal(student.sessionActive, true);

  const disabled = await result(await route(request('/v1/admin/users/joao.silva', {
    method: 'PATCH', token: adminToken, body: { active: false },
  }), env));
  assert.equal(disabled.status, 200);
  assert.equal(disabled.body.active, false);

  const disabledLogin = await login(env, 'joao.silva', 'senha-forte-123');
  assert.equal(disabledLogin.status, 403);
  assert.equal(disabledLogin.body.error, 'account_disabled');

  const blockedSession = await result(await route(request('/v1/bootstrap', { token: studentToken }), env));
  assert.equal(blockedSession.status, 401);
  assert.equal(blockedSession.body.error, 'account_disabled');

  const reenabled = await result(await route(request('/v1/admin/users/joao.silva', {
    method: 'PATCH', token: adminToken, body: { active: true },
  }), env));
  assert.equal(reenabled.status, 200);
  assert.equal((await login(env, 'joao.silva', 'senha-forte-123')).status, 200);

  const protectAdmin = await result(await route(request('/v1/admin/users/admin', {
    method: 'PATCH', token: adminToken, body: { active: false },
  }), env));
  assert.equal(protectAdmin.status, 409);
  assert.equal(protectAdmin.body.error, 'admin_cannot_be_disabled');
});

test('91 active profiles includes admin and disabling frees one slot', async () => {
  const { env, raw } = await fixture();
  const mac = await passwordMac(PASSWORD_PEPPER, 'irrelevant-password');
  const insert = raw.prepare(`INSERT INTO users(username,profile_id,role,password_mac,active,full_name,class_name,created_at)
    VALUES(?,?,'consumer',?,1,?,?,?)`);
  for (let i = 0; i < 90; i++) {
    const id = String(i).padStart(3, '0');
    insert.run(`u${id}`, `profile-${id}`, mac, `Aluno ${id}`, 'Turma A', Date.now());
  }
  assert.equal(raw.prepare('SELECT COUNT(*) AS c FROM users WHERE active=1').get().c, MAX_PROFILES);

  const full = await result(await route(request('/v1/auth/register', {
    method: 'POST', body: { fullName: 'Novo Aluno', username: 'novo.aluno', password: 'senha-nova-123', className: '3º A' },
  }), env));
  assert.equal(full.status, 409);
  assert.equal(full.body.error, 'user_limit_reached');

  const adminToken = (await login(env, 'admin', ADMIN_PASSWORD)).body.token;
  assert.equal((await result(await route(request('/v1/admin/users/u000', {
    method: 'PATCH', token: adminToken, body: { active: false },
  }), env))).status, 200);
  assert.equal(raw.prepare('SELECT COUNT(*) AS c FROM users WHERE active=1').get().c, MAX_PROFILES - 1);

  const created = await result(await route(request('/v1/auth/register', {
    method: 'POST', body: { fullName: 'Novo Aluno', username: 'novo.aluno', password: 'senha-nova-123', className: '3º A' },
  }), env));
  assert.equal(created.status, 201);
  assert.equal(created.body.activeCount, MAX_PROFILES);

  const cannotOverfill = await result(await route(request('/v1/admin/users/u000', {
    method: 'PATCH', token: adminToken, body: { active: true },
  }), env));
  assert.equal(cannotOverfill.status, 409);
  assert.equal(cannotOverfill.body.error, 'user_limit_reached');
  assert.equal(raw.prepare('SELECT COUNT(*) AS c FROM users WHERE active=1').get().c, MAX_PROFILES);
});

test('registration validation is enforced server-side', async () => {
  const { env } = await fixture();
  const invalid = await result(await route(request('/v1/auth/register', {
    method: 'POST', body: { fullName: 'A', username: 'x', password: '123', className: '' },
  }), env));
  assert.equal(invalid.status, 400);
  assert.equal(invalid.body.error, 'invalid_registration');
});
