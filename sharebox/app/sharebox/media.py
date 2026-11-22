"""Torrent creation/rewriting and release-name parsing."""
import io
import os
import re

from guessit import guessit
from torf import Torrent

from . import config

# Newznab/Torznab categories
CATS = {
    "tv": {"base": 5000, "SD": 5030, "HD": 5040, "UHD": 5045},
    "movies": {"base": 2000, "SD": 2030, "HD": 2040, "UHD": 2045},
}
CAT_NAMES = {5000: "TV", 5030: "TV/SD", 5040: "TV/HD", 5045: "TV/UHD",
             2000: "Movies", 2030: "Movies/SD", 2040: "Movies/HD", 2045: "Movies/UHD"}


def norm(text):
    return re.sub(r"[^a-z0-9]+", " ", (text or "").lower()).strip()


def _first(v):
    return v[0] if isinstance(v, list) and v else v


def describe(path, root, kind):
    """Parse a media file into release metadata."""
    rel = os.path.relpath(path, root)
    g = guessit(rel, {"type": "episode" if kind == "tv" else "movie"})
    title = _first(g.get("title"))
    season = _first(g.get("season"))
    episode = _first(g.get("episode"))
    year = _first(g.get("year"))
    res = str(_first(g.get("screen_size")) or "")
    tier = "UHD" if res in ("2160p", "4320p") else "HD" if res in ("720p", "1080p", "1080i") else "SD"
    stem = os.path.splitext(os.path.basename(path))[0]
    release = stem
    # e.g. "Show/Season 01/S01E02 - Pilot.mkv": put the show name into the release title
    if title and norm(title) not in norm(stem):
        release = f"{title} - {stem}"
    return {
        "release": release, "title": title,
        "season": int(season) if isinstance(season, int) else None,
        "episode": int(episode) if isinstance(episode, int) else None,
        "year": int(year) if isinstance(year, int) else None,
        "resolution": res or None,
        "category": CATS[kind][tier],
    }


def create_torrent(path, announce):
    """Private single-file torrent. Returns (infohash, bytes)."""
    t = Torrent(path=path, trackers=[announce], private=True,
                created_by="sharebox", randomize_infohash=False)
    t.generate(threads=max(1, config.HASH_THREADS))
    buf = io.BytesIO()
    t.write_stream(buf)
    return t.infohash.lower(), buf.getvalue()


def with_announce(blob, announce):
    """Same torrent (same infohash) with a different announce URL."""
    t = Torrent.read_stream(io.BytesIO(blob), validate=False)
    t.trackers = [announce]
    buf = io.BytesIO()
    t.write_stream(buf, validate=False)
    return buf.getvalue()
