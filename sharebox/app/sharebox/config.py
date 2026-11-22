"""All settings come from environment variables (see the Dockerfile header)."""
import os


def _env(key, default=None):
    v = os.environ.get(key)
    return default if v is None or v == "" else v


def _bool(key, default):
    return str(_env(key, default)).lower() in ("1", "true", "yes", "on")


def _share_paths():
    """SHARE_PATHS="tv=/media/tv;movies=/media/movies" -> [("tv", "/media/tv"), ...]"""
    out = []
    for item in _env("SHARE_PATHS", "tv=/media/tv;movies=/media/movies").split(";"):
        item = item.strip()
        if not item:
            continue
        kind, _, path = item.partition("=")
        kind = kind.strip().lower()
        if kind not in ("tv", "movies"):
            raise SystemExit(f"SHARE_PATHS: kind must be tv or movies, got {kind!r}")
        out.append((kind, os.path.normpath(path.strip())))
    return out


DATA_DIR = _env("SHAREBOX_DATA", "/data")
DB_PATH = os.path.join(DATA_DIR, "sharebox.db")
SHARE_PATHS = _share_paths()
SHARE_EXISTING = _bool("SHARE_EXISTING", True)

# Public URLs (through SWAG)
PUBLIC_URL = _env("SHAREBOX_PUBLIC_URL", "https://share.example.com").rstrip("/")
TRACKER_PUBLIC_URL = _env("TRACKER_PUBLIC_URL", "https://tracker.example.com").rstrip("/")

# Internal services
TRACKER_API_URL = _env("TRACKER_API_URL", "http://sharebox-tracker:1212").rstrip("/")
TRACKER_HTTP_URL = _env("TRACKER_HTTP_URL", "http://sharebox-tracker:7070").rstrip("/")
TRACKER_API_TOKEN = _env("TRACKER_API_TOKEN", "")
QBIT_URL = _env("QBIT_URL", "http://sharebox-qbittorrent:8080").rstrip("/")
QBIT_USER = _env("QBIT_USER", "")
QBIT_PASS = _env("QBIT_PASS", "")
QBIT_CATEGORY = _env("QBIT_CATEGORY", "sharebox")
# qBittorrent announces here; sharebox forwards to the tracker with X-Forwarded-For
SEEDER_ANNOUNCE_BASE = _env("SEEDER_ANNOUNCE_BASE", "http://sharebox:8081").rstrip("/")
SEEDER_PUBLIC_IP = _env("SEEDER_PUBLIC_IP", "auto")

# Listening ports
API_PORT = int(_env("SHAREBOX_PORT", "8090"))
ANNOUNCE_PROXY_PORT = int(_env("ANNOUNCE_PROXY_PORT", "8081"))

# Watcher
SCAN_INTERVAL = int(_env("SCAN_INTERVAL", "300"))
SETTLE_SECONDS = int(_env("SETTLE_SECONDS", "600"))
MIN_SIZE_MB = int(_env("MIN_SIZE_MB", "20"))
HASH_THREADS = int(_env("HASH_THREADS", "2"))
VIDEO_EXTS = tuple(
    "." + e.strip().lstrip(".").lower()
    for e in _env("VIDEO_EXTS", "mkv,mp4,avi,m4v,ts,webm,mov,wmv").split(",")
)

# qBittorrent config seeding (sharebox init-qbit)
QBIT_CONFIG_DIR = _env("QBIT_CONFIG_DIR", "/qbit-config")
QBIT_WEBUI_USER = _env("QBIT_WEBUI_USER", "admin")
QBIT_WEBUI_PASS = _env("QBIT_WEBUI_PASS", "")
QBIT_AUTH_BYPASS = _env("QBIT_AUTH_BYPASS", "172.31.77.10/32")
TORRENT_PORT = int(_env("TORRENT_PORT", "6881"))
PUID = int(_env("PUID", "1000"))
PGID = int(_env("PGID", "1000"))
