"""SQLite storage: friends, shared torrents, settings."""
import os
import sqlite3
import time

from . import config

SCHEMA = """
CREATE TABLE IF NOT EXISTS settings (k TEXT PRIMARY KEY, v TEXT);
CREATE TABLE IF NOT EXISTS friends (
    name        TEXT PRIMARY KEY,
    apikey      TEXT UNIQUE NOT NULL,
    tracker_key TEXT NOT NULL,
    created     INTEGER NOT NULL,
    last_seen   INTEGER
);
CREATE TABLE IF NOT EXISTS torrents (
    infohash   TEXT PRIMARY KEY,
    path       TEXT UNIQUE NOT NULL,
    root       TEXT NOT NULL,
    kind       TEXT NOT NULL,          -- tv | movies
    release    TEXT NOT NULL,          -- title shown to Prowlarr/Sonarr/Radarr
    title      TEXT,
    season     INTEGER,
    episode    INTEGER,
    year       INTEGER,
    resolution TEXT,
    category   INTEGER NOT NULL,
    size       INTEGER NOT NULL,
    mtime      REAL NOT NULL,
    added      INTEGER NOT NULL,
    torrent    BLOB NOT NULL
);
CREATE INDEX IF NOT EXISTS torrents_added ON torrents(added DESC);
"""


def connect():
    os.makedirs(config.DATA_DIR, exist_ok=True)
    conn = sqlite3.connect(config.DB_PATH, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=30000")
    conn.executescript(SCHEMA)
    return conn


def get_setting(conn, key, default=None):
    row = conn.execute("SELECT v FROM settings WHERE k=?", (key,)).fetchone()
    return row["v"] if row else default


def set_setting(conn, key, value):
    with conn:
        conn.execute("INSERT INTO settings(k,v) VALUES(?,?) "
                     "ON CONFLICT(k) DO UPDATE SET v=excluded.v", (key, str(value)))


def friend_by_apikey(conn, apikey):
    if not apikey:
        return None
    row = conn.execute("SELECT * FROM friends WHERE apikey=?", (apikey,)).fetchone()
    if row:
        with conn:
            conn.execute("UPDATE friends SET last_seen=? WHERE name=?", (int(time.time()), row["name"]))
    return row
