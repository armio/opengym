-- Daily recovery metrics the iPhone app reads from Apple Health (contract §8). Not part of the
-- sync protocol: the app uploads them with POST /api/recovery and only the MCP tools read them.
CREATE TABLE recovery_daily (
  d          TEXT NOT NULL PRIMARY KEY, -- 'YYYY-MM-DD' in the owner's time zone; a night counts toward the day it ends
  rhr        REAL,                      -- resting heart rate, bpm
  hrv        REAL,                      -- heart-rate variability (SDNN), daily mean, ms
  sleep_min  INTEGER,                   -- minutes asleep
  in_bed_min INTEGER,                   -- minutes in bed
  updated_at INTEGER NOT NULL           -- epoch ms of the upload
);
