ALTER TABLE users ADD COLUMN full_name TEXT;
ALTER TABLE users ADD COLUMN class_name TEXT;
ALTER TABLE users ADD COLUMN auth_salt TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN auth_scheme TEXT NOT NULL DEFAULT 'hmac-sha256-pepper-v1';
ALTER TABLE users ADD COLUMN created_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN last_login_at INTEGER;
ALTER TABLE users ADD COLUMN session_expires_at INTEGER;

CREATE INDEX IF NOT EXISTS idx_users_active ON users(active);
CREATE INDEX IF NOT EXISTS idx_users_profile_active ON users(profile_id,active);
CREATE INDEX IF NOT EXISTS idx_users_class ON users(class_name);
