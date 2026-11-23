"""Library watcher: new/changed media file -> private torrent -> whitelisted -> seeding.
Removed/replaced file -> torrent removed from qBittorrent, whitelist and index."""
import fcntl
import logging
import os
import time

from . import config, db, media
from .clients import QBit, TrackerAPI

log = logging.getLogger("sharebox")


def seeder_announce(conn):
    key = db.get_setting(conn, "seeder_key")
    return f"{config.SEEDER_ANNOUNCE_BASE}/announce/{key}"


def ensure_seeder_key(conn, tracker):
    if not db.get_setting(conn, "seeder_key"):
        db.set_setting(conn, "seeder_key", tracker.key_create())
        log.info("created tracker key for the seeder (qBittorrent)")


def _iter_media(root):
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d.lower() not in ("@eadir", "#recycle")]
        for f in files:
            if f.startswith(".") or not f.lower().endswith(config.VIDEO_EXTS):
                continue
            if "sample" in f.lower() or "-trailer" in f.lower():
                continue
            yield os.path.join(dirpath, f)


def _remove(conn, tracker, qbit, row, why):
    ih = row["infohash"]
    try:
        qbit.delete(ih)
    except Exception as e:
        log.warning("qBittorrent delete %s failed: %s", ih, e)
    try:
        tracker.whitelist_remove(ih)
    except Exception as e:
        log.warning("whitelist remove %s failed: %s", ih, e)
    with conn:
        conn.execute("DELETE FROM torrents WHERE infohash=?", (ih,))
    log.info("removed (%s): %s", why, row["release"])


def _share(conn, tracker, qbit, path, root, kind, st):
    meta = media.describe(path, root, kind)
    log.info("hashing: %s (%.1f GB)", meta["release"], st.st_size / 1e9)
    ih, blob = media.create_torrent(path, seeder_announce(conn))
    # The file may have changed while hashing (e.g. still being written).
    st2 = os.stat(path)
    if (st2.st_size, st2.st_mtime) != (st.st_size, st.st_mtime):
        log.info("changed while hashing, will retry: %s", path)
        return
    tracker.whitelist_add(ih)
    qbit.add(blob, os.path.dirname(path), meta["release"])
    with conn:
        conn.execute("DELETE FROM torrents WHERE infohash=? OR path=?", (ih, path))
        conn.execute(
            "INSERT INTO torrents(infohash,path,root,kind,release,title,season,episode,year,"
            "resolution,category,size,mtime,added,torrent) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (ih, path, root, kind, meta["release"], meta["title"], meta["season"], meta["episode"],
             meta["year"], meta["resolution"], meta["category"], st.st_size, st.st_mtime,
             int(time.time()), blob))
    log.info("sharing: %s [%s] %s", meta["release"], media.CAT_NAMES[meta["category"]], ih)


def reconcile(conn, tracker, qbit):
    """Make sure everything in the index is whitelisted and seeding (e.g. after
    qBittorrent or the tracker lost state)."""
    have = qbit.hashes()
    rows = conn.execute("SELECT infohash, path, release, torrent FROM torrents").fetchall()
    for row in rows:
        try:
            tracker.whitelist_add(row["infohash"])
            if row["infohash"] not in have and os.path.exists(row["path"]):
                qbit.add(row["torrent"], os.path.dirname(row["path"]), row["release"])
                log.info("re-added to qBittorrent: %s", row["release"])
        except Exception as e:
            log.warning("reconcile %s: %s", row["release"], e)


def scan_once(tracker=None, qbit=None):
    os.makedirs(config.DATA_DIR, exist_ok=True)
    with open(os.path.join(config.DATA_DIR, "scan.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        tracker = tracker or TrackerAPI()
        qbit = qbit or QBit()
        conn = db.connect()
        try:
            ensure_seeder_key(conn, tracker)
            since = 0.0
            if not config.SHARE_EXISTING:
                since = float(db.get_setting(conn, "share_since") or 0) or time.time()
                db.set_setting(conn, "share_since", since)
            known = {r["path"]: r for r in conn.execute("SELECT * FROM torrents")}
            seen, healthy_roots = set(), []
            now = time.time()
            for kind, root in config.SHARE_PATHS:
                # Guard: an unmounted/empty share must not wipe its torrents.
                if not os.path.isdir(root) or not os.listdir(root):
                    log.warning("share %s is missing or empty, skipping (no removals)", root)
                    continue
                healthy_roots.append(root)
                for path in _iter_media(root):
                    try:
                        st = os.stat(path)
                    except FileNotFoundError:
                        continue
                    seen.add(path)
                    row = known.get(path)
                    if row and row["size"] == st.st_size and abs(row["mtime"] - st.st_mtime) < 1:
                        continue
                    if st.st_size < config.MIN_SIZE_MB * 1024 * 1024:
                        continue
                    if now - st.st_mtime < config.SETTLE_SECONDS:
                        continue  # still being written/moved; next scan
                    if st.st_mtime < since:
                        continue  # SHARE_EXISTING=false: only files newer than first run
                    if row:
                        _remove(conn, tracker, qbit, row, "file changed")
                    try:
                        _share(conn, tracker, qbit, path, root, kind, st)
                    except Exception as e:
                        log.error("failed to share %s: %s", path, e)
            for path, row in known.items():
                if path not in seen and row["root"] in healthy_roots and not os.path.exists(path):
                    _remove(conn, tracker, qbit, row, "file gone")
        finally:
            conn.close()


def run_forever():
    tracker, qbit = TrackerAPI(), QBit()
    # Wait for the tracker and qBittorrent to come up
    while True:
        try:
            conn = db.connect()
            ensure_seeder_key(conn, tracker)
            qbit.ensure_category()
            reconcile(conn, tracker, qbit)
            conn.close()
            break
        except Exception as e:
            log.warning("waiting for tracker/qBittorrent: %s", e)
            time.sleep(15)
    while True:
        try:
            scan_once(tracker, qbit)
        except Exception as e:
            log.error("scan failed: %s", e)
        time.sleep(config.SCAN_INTERVAL)
