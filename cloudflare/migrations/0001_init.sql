CREATE TABLE docs (
  key        TEXT NOT NULL PRIMARY KEY CHECK (key IN ('settings','plan','schedule','athlete','coach')),
  data       TEXT    NOT NULL,          -- JSON object
  updated_at INTEGER NOT NULL,          -- epoch ms of the edit (informational for docs)
  seq        INTEGER NOT NULL           -- version: the change sequence number of the last write
);
CREATE TABLE workouts (
  id         TEXT NOT NULL PRIMARY KEY,
  d          TEXT    NOT NULL,          -- 'YYYY-MM-DD' local date the session started
  start      INTEGER,                   -- epoch ms
  routine_id TEXT,
  data       TEXT,                      -- full Workout JSON; NULL when deleted
  deleted    INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,          -- LWW clock
  seq        INTEGER NOT NULL
);
CREATE INDEX workouts_seq ON workouts(seq);
CREATE INDEX workouts_date ON workouts(d, start);
CREATE TABLE bodyweight (
  d          TEXT NOT NULL PRIMARY KEY, -- 'YYYY-MM-DD'
  w          REAL,                      -- NULL when deleted
  t          INTEGER,                   -- epoch ms of the entry
  deleted    INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  seq        INTEGER NOT NULL
);
CREATE INDEX bodyweight_seq ON bodyweight(seq);
CREATE TABLE ex_weights (
  ex_id      TEXT NOT NULL PRIMARY KEY,
  w          REAL,                      -- NULL when deleted
  d          TEXT,                      -- 'YYYY-MM-DD'
  deleted    INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  seq        INTEGER NOT NULL
);
CREATE INDEX ex_weights_seq ON ex_weights(seq);
CREATE TABLE proposals (
  id          TEXT NOT NULL PRIMARY KEY,-- 'p' + 16 hex
  kind        TEXT NOT NULL CHECK (kind IN ('plan','changes','nochange')),
  status      TEXT NOT NULL CHECK (status IN ('pending','applied','dismissed','superseded','expired')),
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL,         -- created_at + 14 days
  plan_hash   TEXT,                     -- planHash of the plan doc when created (§5.4)
  unit        TEXT NOT NULL,            -- settings.unit when created
  iteration   INTEGER NOT NULL DEFAULT 1,
  summary     TEXT NOT NULL DEFAULT '',
  data        TEXT NOT NULL,            -- JSON body, see §4.5
  resolution  TEXT,                     -- JSON {outcome, accepted[], rejected[], stale[], schedule?}
  resolved_at INTEGER,
  reverted_at INTEGER,
  seq         INTEGER NOT NULL
);
CREATE INDEX proposals_seq ON proposals(seq);
CREATE TABLE devices (
  id           TEXT NOT NULL PRIMARY KEY, -- 'd' + 16 hex
  name         TEXT NOT NULL,
  token_hash   TEXT NOT NULL UNIQUE,    -- hex SHA-256 of the bearer token
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER,
  tz           TEXT                     -- IANA zone from the X-Timezone header
);
CREATE TABLE auth_failures (ip TEXT NOT NULL, at INTEGER NOT NULL);
CREATE INDEX auth_failures_ip ON auth_failures(ip, at);
CREATE TABLE limits_log (kind TEXT NOT NULL, at INTEGER NOT NULL);   -- MCP write rate limits
CREATE INDEX limits_log_kind ON limits_log(kind, at);
CREATE TABLE guard (ok INTEGER NOT NULL CHECK (ok = 1));              -- abort helper, §3.4
CREATE TABLE counters (name TEXT NOT NULL PRIMARY KEY, value INTEGER NOT NULL);
INSERT INTO counters (name, value) VALUES ('seq', 0);
INSERT INTO counters (name, value) VALUES ('epoch', abs(random()) % 9007199254740991);
