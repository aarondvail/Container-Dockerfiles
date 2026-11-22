"""HTTP side:
  - Torznab API for friends' Prowlarr (port SHAREBOX_PORT, published via SWAG)
  - announce proxy for the local seeder (port ANNOUNCE_PROXY_PORT, internal only):
    qBittorrent -> sharebox -> tracker, adding X-Forwarded-For = your public IP,
    because the tracker runs with on_reverse_proxy = true."""
import logging
import time
from email.utils import formatdate
from xml.sax.saxutils import escape, quoteattr

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import PlainTextResponse, Response

from . import config, db, media

log = logging.getLogger("sharebox")
XML = "application/xml; charset=utf-8"

# ----------------------------------------------------------------- Torznab ---
api = FastAPI(title="sharebox", docs_url=None, redoc_url=None, openapi_url=None)


def _err(code, desc):
    return Response(f'<?xml version="1.0" encoding="UTF-8"?>\n<error code="{code}" '
                    f'description={quoteattr(desc)}/>', media_type=XML)


def _caps():
    def cat(base, kind):
        subs = "".join(f'<subcat id="{c}" name="{media.CAT_NAMES[c]}"/>'
                       for k, c in media.CATS[kind].items() if k != "base")
        return f'<category id="{base}" name="{media.CAT_NAMES[base]}">{subs}</category>'
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<caps>'
            '<server version="1.0" title="sharebox"/>'
            '<limits max="100" default="100"/>'
            '<searching>'
            '<search available="yes" supportedParams="q"/>'
            '<tv-search available="yes" supportedParams="q,season,ep"/>'
            '<movie-search available="yes" supportedParams="q"/>'
            '</searching>'
            f'<categories>{cat(5000, "tv")}{cat(2000, "movies")}</categories></caps>')


def _item(row, apikey):
    link = f"{config.PUBLIC_URL}/dl/{row['infohash']}.torrent?apikey={apikey}"
    cats = [row["category"], media.CATS[row["kind"]]["base"]]
    attrs = [("category", c) for c in cats] + [
        ("size", row["size"]), ("files", 1), ("grabs", 0),
        ("seeders", 1), ("peers", 1), ("infohash", row["infohash"]),
        ("downloadvolumefactor", 0), ("uploadvolumefactor", 1),
    ]
    if row["season"] is not None:
        attrs.append(("season", row["season"]))
    if row["episode"] is not None:
        attrs.append(("episode", row["episode"]))
    if row["year"]:
        attrs.append(("year", row["year"]))
    attr_xml = "".join(f'<torznab:attr name="{n}" value={quoteattr(str(v))}/>' for n, v in attrs)
    return (f"<item><title>{escape(row['release'])}</title>"
            f"<guid isPermaLink=\"false\">{row['infohash']}</guid>"
            f"<link>{escape(link)}</link>"
            f"<pubDate>{formatdate(row['added'], usegmt=True)}</pubDate>"
            f"<size>{row['size']}</size>"
            + "".join(f"<category>{c}</category>" for c in cats) +
            f'<enclosure url={quoteattr(link)} length="{row["size"]}" type="application/x-bittorrent"/>'
            f"{attr_xml}</item>")


def _search(conn, t, q, cats, season, ep, limit, offset):
    sql, args = "SELECT * FROM torrents WHERE 1=1", []
    if t == "tvsearch":
        sql += " AND kind='tv'"
    elif t == "movie":
        sql += " AND kind='movies'"
    if season is not None:
        sql += " AND season=?"
        args.append(season)
    if ep is not None:
        sql += " AND episode=?"
        args.append(ep)
    rows = conn.execute(sql + " ORDER BY added DESC", args).fetchall()
    if cats:
        rows = [r for r in rows if r["category"] in cats or media.CATS[r["kind"]]["base"] in cats]
    tokens = media.norm(q).split()
    if tokens:
        def words(r):
            return set(f"{media.norm(r['release'])} {media.norm(r['title'])}".split())
        rows = [r for r in rows if all(tok in words(r) for tok in tokens)]
    return rows[offset:offset + limit]


def _int(v):
    try:
        return int(v) if v not in (None, "") else None
    except ValueError:
        return None


@api.get("/api")
def torznab(request: Request):
    p = request.query_params
    t = (p.get("t") or "search").lower()
    if t == "caps":
        return Response(_caps(), media_type=XML)
    conn = db.connect()
    try:
        friend = db.friend_by_apikey(conn, p.get("apikey"))
        if not friend:
            return _err(100, "Incorrect user credentials")
        if t not in ("search", "tvsearch", "movie"):
            return _err(202, f"No such function ({t})")
        cats = {c for c in (_int(x) for x in (p.get("cat") or "").split(",")) if c}
        limit = min(_int(p.get("limit")) or 100, 100)
        offset = _int(p.get("offset")) or 0
        rows = _search(conn, t, p.get("q"), cats, _int(p.get("season")), _int(p.get("ep")),
                       limit, offset)
        body = "".join(_item(r, friend["apikey"]) for r in rows)
        return Response(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" '
            'xmlns:torznab="http://torznab.com/schemas/2015/feed"><channel>'
            f"<title>sharebox</title><description>Private share</description>"
            f"<link>{escape(config.PUBLIC_URL)}</link>"
            f'<torznab:response offset="{offset}" total="{len(rows)}"/>'
            f"{body}</channel></rss>", media_type=XML)
    finally:
        conn.close()


@api.get("/dl/{infohash}.torrent")
def download(infohash: str, apikey: str = ""):
    conn = db.connect()
    try:
        friend = db.friend_by_apikey(conn, apikey)
        if not friend:
            return PlainTextResponse("forbidden", status_code=403)
        row = conn.execute("SELECT release, torrent FROM torrents WHERE infohash=?",
                           (infohash.lower(),)).fetchone()
        if not row:
            return PlainTextResponse("not found", status_code=404)
        blob = media.with_announce(
            row["torrent"], f"{config.TRACKER_PUBLIC_URL}/announce/{friend['tracker_key']}")
        safe = "".join(c if c.isalnum() or c in " .-_()[]" else "_" for c in row["release"])
        return Response(blob, media_type="application/x-bittorrent",
                        headers={"Content-Disposition": f'attachment; filename="{safe}.torrent"'})
    finally:
        conn.close()


@api.get("/health")
def health():
    return PlainTextResponse("ok")


# ---------------------------------------------------- seeder announce proxy ---
proxy = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
_ip = {"value": None, "at": 0.0}


async def public_ip():
    if config.SEEDER_PUBLIC_IP != "auto":
        return config.SEEDER_PUBLIC_IP
    if _ip["value"] and time.time() - _ip["at"] < 1800:
        return _ip["value"]
    for url in ("https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com"):
        try:
            async with httpx.AsyncClient(timeout=10) as c:
                ip = (await c.get(url)).text.strip()
            if ip and len(ip) <= 45:
                if ip != _ip["value"]:
                    log.info("seeder public IP: %s", ip)
                _ip.update(value=ip, at=time.time())
                return ip
        except Exception:
            continue
    return _ip["value"]


@proxy.get("/{action}/{key}")
async def announce_proxy(action: str, key: str, request: Request):
    if action not in ("announce", "scrape") or not key.isalnum():
        return PlainTextResponse("not found", status_code=404)
    ip = await public_ip()
    if not ip:
        return PlainTextResponse("public IP unknown", status_code=503)
    # Raw query string, untouched: info_hash is percent-encoded binary.
    raw = request.scope.get("query_string", b"").decode("latin-1")
    url = f"{config.TRACKER_HTTP_URL}/{action}/{key}" + (f"?{raw}" if raw else "")
    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.get(httpx.URL(url), headers={"X-Forwarded-For": ip})
    return Response(r.content, status_code=r.status_code,
                    media_type=r.headers.get("content-type", "text/plain"))
