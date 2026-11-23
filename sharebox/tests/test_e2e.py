# Run: pip install fastapi uvicorn httpx torf guessit && python3 sharebox/tests/test_e2e.py
"""End-to-end test of sharebox against mock Torrust + qBittorrent APIs."""
import os, sys, time, threading, json, io, urllib.parse, xml.etree.ElementTree as ET
import uvicorn, httpx
from fastapi import FastAPI, Request, UploadFile, Form
from fastapi.responses import JSONResponse, PlainTextResponse, Response

T = "/tmp/sharebox-test"; os.system(f"rm -rf {T}; mkdir -p {T}/media/tv '{T}/media/tv/The Expanse/Season 01' {T}/media/movies {T}/data")
def mk(p, mb):
    with open(p, "wb") as f: f.write(os.urandom(1024*1024) * mb)
    old = time.time() - 3600; os.utime(p, (old, old))
mk(f"{T}/media/tv/The Expanse/Season 01/The.Expanse.S01E01.Dulcinea.1080p.WEB-DL.x264-GRP.mkv", 3)
mk(f"{T}/media/tv/The Expanse/Season 01/S01E02 - The Big Empty WEBDL-720p.mkv", 2)
mk(f"{T}/media/tv/The Expanse/Season 01/sample.mkv", 2)
mk(f"{T}/media/movies/Arrival (2016) Bluray-2160p.mkv", 3)
mk(f"{T}/media/movies/Dune (2021) WEBDL-1080p.mkv", 2)
fresh = f"{T}/media/tv/The Expanse/Season 01/The.Expanse.S01E03.Remember.the.Cant.1080p.mkv"
with open(fresh, "wb") as f: f.write(os.urandom(2*1024*1024))   # too new -> settle wait

os.environ.update(SHAREBOX_DATA=f"{T}/data", SHARE_PATHS=f"tv={T}/media/tv;movies={T}/media/movies",
    TRACKER_API_URL="http://127.0.0.1:19212", TRACKER_HTTP_URL="http://127.0.0.1:19070",
    TRACKER_API_TOKEN="tok", QBIT_URL="http://127.0.0.1:19080", SEEDER_ANNOUNCE_BASE="http://127.0.0.1:19081",
    SEEDER_PUBLIC_IP="203.0.113.7", SHAREBOX_PUBLIC_URL="https://share.vail.test",
    TRACKER_PUBLIC_URL="https://tracker.vail.test", MIN_SIZE_MB="1", SETTLE_SECONDS="600",
    SHAREBOX_PORT="19090", ANNOUNCE_PROXY_PORT="19081")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app"))

# ---- mock tracker
state = {"white": set(), "keys": set(), "announces": []}
trk = FastAPI()
@trk.post("/api/v1/whitelist/{ih}")
def wl_add(ih: str, token: str):
    assert token == "tok"; state["white"].add(ih); return {"status": "ok"}
@trk.delete("/api/v1/whitelist/{ih}")
def wl_del(ih: str, token: str):
    state["white"].discard(ih); return {"status": "ok"}
@trk.post("/api/v1/keys")
async def key_add(request: Request, token: str):
    body = await request.json(); assert body == {"key": None, "seconds_valid": None}, body
    k = f"K{len(state['keys']):031d}"; state["keys"].add(k); return {"key": k, "valid_until": None}
@trk.delete("/api/v1/key/{k}")
def key_del(k: str, token: str):
    state["keys"].discard(k); return {"status": "ok"}
trk_http = FastAPI()
@trk_http.get("/announce/{k}")
def ann(k: str, request: Request):
    state["announces"].append({"key": k, "xff": request.headers.get("x-forwarded-for"),
                               "raw": request.scope["query_string"].decode("latin-1")})
    return Response(b"d8:intervali1800e5:peers0:e", media_type="text/plain")

# ---- mock qbit
q = {"torrents": {}, "deleted": []}
qb = FastAPI()
@qb.post("/api/v2/torrents/createCategory")
def cat(): return PlainTextResponse("")
@qb.get("/api/v2/torrents/info")
def info(category: str): return [{"hash": h} for h in q["torrents"]]
@qb.post("/api/v2/torrents/add")
async def add(request: Request):
    form = await request.form(); data = await form["torrents"].read()
    from torf import Torrent
    t = Torrent.read_stream(io.BytesIO(data))
    q["torrents"][t.infohash] = {"savepath": form["savepath"], "skip": form["skip_checking"],
                                 "private": t.private, "trackers": t.trackers.flat}
    return PlainTextResponse("Ok.")
@qb.post("/api/v2/torrents/delete")
async def delete(request: Request):
    form = await request.form(); q["deleted"].append(form["hashes"]); q["torrents"].pop(form["hashes"], None)
    return PlainTextResponse("")

def serve(app, port):
    s = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=port, log_level="error"))
    threading.Thread(target=s.run, daemon=True).start()
for app, port in ((trk, 19212), (trk_http, 19070), (qb, 19080)): serve(app, port)

from sharebox import web, watcher, cli, db, media
serve(web.api, 19090); serve(web.proxy, 19081)
time.sleep(1.5)

ok = lambda c, m: print(("PASS " if c else "FAIL ") + m) or bool(c)
results = []

# 1. scan
watcher.scan_once()
conn = db.connect()
rows = {r["release"]: r for r in conn.execute("SELECT * FROM torrents")}
print("indexed:", list(rows))
results += [ok(len(rows) == 4, "4 files shared (sample skipped, fresh file waiting)")]
results += [ok(all(r["infohash"] in state["white"] for r in rows.values()), "all whitelisted")]
results += [ok(set(q["torrents"]) == {r["infohash"] for r in rows.values()}, "all added to qBittorrent")]
t0 = next(iter(q["torrents"].values()))
results += [ok(t0["private"] and t0["skip"] == "true", "private flag + skip_checking")]
seeder_key = db.get_setting(conn, "seeder_key")
results += [ok(list(t0["trackers"]) == [f"http://127.0.0.1:19081/announce/{seeder_key}"], f"seeder announces via proxy: {t0['trackers']}")]
ep2 = [r for r in rows.values() if r["episode"] == 2][0]
results += [ok(ep2["release"].startswith("The Expanse - S01E02"), f"show name added to bare episode file: {ep2['release']}")]
results += [ok(ep2["category"] == 5040 and rows["Arrival (2016) Bluray-2160p"]["category"] == 2045, "categories 5040 / 2045")]

# 2. friend
from argparse import Namespace
buf = io.StringIO(); _o = sys.stdout; sys.stdout = buf
cli.cmd_friend(Namespace(action="add", name="bob")); sys.stdout = _o
bob = conn.execute("SELECT * FROM friends WHERE name='bob'").fetchone()
results += [ok(bob and bob["tracker_key"] in state["keys"], "friend gets tracker key")]
results += [ok(bob["apikey"] in buf.getvalue() and "Generic Torznab" in buf.getvalue(), "Prowlarr instructions printed")]

c = httpx.Client(base_url="http://127.0.0.1:19090")
ns = {"torznab": "http://torznab.com/schemas/2015/feed"}
caps = ET.fromstring(c.get("/api", params={"t": "caps"}).content)
results += [ok(caps.find("searching/tv-search").get("supportedParams") == "q,season,ep", "caps tv-search params")]
bad = ET.fromstring(c.get("/api", params={"t": "search", "apikey": "nope"}).content)
results += [ok(bad.tag == "error" and bad.get("code") == "100", "bad apikey -> error 100")]
def items(**p):
    p["apikey"] = bob["apikey"]
    root = ET.fromstring(c.get("/api", params=p).content)
    return root.findall("channel/item")
results += [ok(len(items(t="search")) == 4, "RSS (empty search) returns all 4")]
tv = items(t="tvsearch", q="The Expanse", season="1", ep="2")
results += [ok(len(tv) == 1 and "S01E02" in tv[0].findtext("title"), "tvsearch q+season+ep")]
results += [ok(len(items(t="tvsearch", q="expanse", season="1")) == 2, "season search")]
results += [ok(len(items(t="movie", q="arrival")) == 1 and len(items(t="movie", q="expanse")) == 0, "movie search")]
results += [ok(len(items(t="search", cat="2000")) == 2 and len(items(t="search", cat="5040")) == 2, "category filter")]
it = items(t="tvsearch", q="expanse", ep="1")[0]
attrs = {a.get("name"): a.get("value") for a in it.findall("torznab:attr", ns)}
results += [ok(attrs.get("season") == "1" and attrs.get("episode") == "1" and attrs.get("infohash"), f"torznab attrs {attrs}")]

# 3. download -> per-friend announce, same infohash
link = it.find("enclosure").get("url").replace("https://share.vail.test", "")
r = c.get(link)
from torf import Torrent
tt = Torrent.read_stream(io.BytesIO(r.content))
results += [ok(r.headers["content-type"] == "application/x-bittorrent", "download content-type")]
results += [ok(list(tt.trackers.flat) == [f"https://tracker.vail.test/announce/{bob['tracker_key']}"], f"friend announce: {tt.trackers.flat}")]
results += [ok(tt.infohash == attrs["infohash"] and tt.private, "same infohash, private")]
results += [ok(c.get(link.split("?")[0] + "?apikey=bad").status_code == 403, "download needs apikey")]

# 4. announce proxy: raw binary info_hash preserved + XFF
raw_ih = urllib.parse.quote_from_bytes(bytes.fromhex(attrs["infohash"]))
qs = f"info_hash={raw_ih}&peer_id=-qB5000-abcdefghijkl&port=6881&uploaded=0&downloaded=0&left=0&compact=1"
pr = httpx.get(f"http://127.0.0.1:19081/announce/{seeder_key}?{qs}")
last = state["announces"][-1]
results += [ok(pr.status_code == 200 and last["xff"] == "203.0.113.7", "proxy adds X-Forwarded-For public IP")]
results += [ok(last["raw"] == qs, "raw query passed through byte-exact")]

# 5. settle: fresh file appears after it ages
old = time.time() - 3600; os.utime(fresh, (old, old)); watcher.scan_once()
results += [ok(conn.execute("SELECT COUNT(*) FROM torrents").fetchone()[0] == 5, "settled file picked up on later scan")]

# 6. upgrade/removal: delete a file -> removed everywhere
gone = rows["Arrival (2016) Bluray-2160p"]
os.remove(gone["path"]); watcher.scan_once()
results += [ok(gone["infohash"] in q["deleted"] and gone["infohash"] not in state["white"]
               and not conn.execute("SELECT 1 FROM torrents WHERE infohash=?", (gone["infohash"],)).fetchone(),
               "deleted file -> removed from qBit, whitelist, index")]

# 7. unmounted share must not wipe torrents
os.rename(f"{T}/media/tv", f"{T}/media/tv.off"); os.makedirs(f"{T}/media/tv"); watcher.scan_once()
results += [ok(conn.execute("SELECT COUNT(*) FROM torrents WHERE kind='tv'").fetchone()[0] == 3, "empty/unmounted share -> no removals")]
os.rmdir(f"{T}/media/tv"); os.rename(f"{T}/media/tv.off", f"{T}/media/tv")

# 8. qBittorrent lost state -> reconcile re-adds
q["torrents"].clear(); watcher.reconcile(conn, watcher.TrackerAPI(), watcher.QBit())
results += [ok(len(q["torrents"]) == 4, "reconcile re-adds missing torrents to qBittorrent")]

# 9. friend removal revokes
cli.cmd_friend(Namespace(action="remove", name="bob"))
results += [ok(bob["tracker_key"] not in state["keys"], "friend remove revokes tracker key")]
results += [ok(ET.fromstring(c.get("/api", params={"t": "search", "apikey": bob["apikey"]}).content).tag == "error", "revoked apikey rejected")]

# 10. init-qbit
os.environ["QBIT_CONFIG_DIR"] = f"{T}/qbitcfg"; os.environ["QBIT_WEBUI_PASS"] = "s3cret!"
import importlib; from sharebox import config; importlib.reload(config); importlib.reload(cli)
cli.cmd_init_qbit(None)
conf = open(f"{T}/qbitcfg/qBittorrent/qBittorrent.conf").read()
import base64, hashlib, re
m = re.search(r'Password_PBKDF2="@ByteArray\(([^:]+):([^)]+)\)"', conf)
salt, dk = base64.b64decode(m.group(1)), base64.b64decode(m.group(2))
results += [ok(hashlib.pbkdf2_hmac("sha512", b"s3cret!", salt, 100000, 64) == dk, "qBittorrent PBKDF2 password verifies")]
results += [ok("QueueingSystemEnabled=false" in conf and "AuthSubnetWhitelist=172.31.77.10/32" in conf, "queueing off, auth bypass only for sharebox IP")]

print(f"\n{sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
