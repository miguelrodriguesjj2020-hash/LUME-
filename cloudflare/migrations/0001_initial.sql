PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS state (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL
);
INSERT OR IGNORE INTO state(k,v) VALUES('schema_version','1');
INSERT OR IGNORE INTO state(k,v) VALUES('revision','1');

CREATE TABLE IF NOT EXISTS users (
  username TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL CHECK(role IN ('consumer','admin')),
  password_mac TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1))
);

CREATE TABLE IF NOT EXISTS works (
  id TEXT PRIMARY KEY,
  ordinal INTEGER NOT NULL,
  json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_works_ordinal ON works(ordinal);

CREATE TABLE IF NOT EXISTS tombstones (
  ordinal INTEGER PRIMARY KEY,
  json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS progress (
  profile TEXT NOT NULL,
  edition TEXT NOT NULL,
  json TEXT NOT NULL,
  client_updated_at INTEGER NOT NULL,
  completed INTEGER NOT NULL CHECK(completed IN (0,1)),
  PRIMARY KEY(profile, edition)
);

CREATE TABLE IF NOT EXISTS events (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  profile TEXT NOT NULL,
  edition TEXT NOT NULL,
  json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_events_profile_seq ON events(profile, seq);

CREATE TABLE IF NOT EXISTS ops (
  profile TEXT NOT NULL,
  op_id TEXT NOT NULL,
  edition TEXT NOT NULL,
  PRIMARY KEY(profile, op_id)
);

CREATE TABLE IF NOT EXISTS media (
  edition TEXT PRIMARY KEY,
  source_file_id TEXT NOT NULL,
  file_name TEXT NOT NULL,
  format TEXT NOT NULL,
  byte_size INTEGER,
  etag TEXT,
  sha256 TEXT
);
