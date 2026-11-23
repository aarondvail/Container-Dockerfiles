"""sharebox command line.

  sharebox serve                 run watcher + Torznab API + announce proxy (default)
  sharebox friend add NAME       create a friend: tracker key + Torznab API key
  sharebox friend list
  sharebox friend show NAME      print a friend's Prowlarr settings again
  sharebox friend remove NAME    revoke tracker key and API key
  sharebox list [TEXT]           what's being shared
  sharebox scan                  scan the library now
  sharebox init-qbit             write qBittorrent.conf if missing (compose init job)
"""
import argparse
import base64
import datetime
import hashlib
import logging
import os
import secrets
import sys
import threading
import time

from . import config, db, media


def _prowlarr_help(name, apikey):
    return f"""
Prowlarr settings for {name}
  Indexers > Add Indexer > "Generic Torznab"
    Name:      sharebox
    URL:       {config.PUBLIC_URL}
    API Path:  /api
    API Key:   {apikey}
    Categories: TV (5000) and/or Movies (2000)
  Their torrent client must accept private torrents (default in qBittorrent,
  Transmission, Deluge). Their downloads announce to:
    {config.TRACKER_PUBLIC_URL}/announce/<their personal key>
"""


def cmd_friend(args):
    from .clients import TrackerAPI
    conn = db.connect()
    if args.action == "add":
        if conn.execute("SELECT 1 FROM friends WHERE name=?", (args.name,)).fetchone():
            sys.exit(f"friend {args.name!r} already exists")
        apikey = secrets.token_hex(16)
        key = TrackerAPI().key_create()
        with conn:
            conn.execute("INSERT INTO friends(name,apikey,tracker_key,created) VALUES(?,?,?,?)",
                         (args.name, apikey, key, int(time.time())))
        print(_prowlarr_help(args.name, apikey))
    elif args.action == "show":
        row = conn.execute("SELECT * FROM friends WHERE name=?", (args.name,)).fetchone()
        if not row:
            sys.exit(f"no friend {args.name!r}")
        print(_prowlarr_help(row["name"], row["apikey"]))
    elif args.action == "remove":
        row = conn.execute("SELECT * FROM friends WHERE name=?", (args.name,)).fetchone()
        if not row:
            sys.exit(f"no friend {args.name!r}")
        TrackerAPI().key_delete(row["tracker_key"])
        with conn:
            conn.execute("DELETE FROM friends WHERE name=?", (args.name,))
        print(f"removed {args.name}: API key and tracker key revoked")
    else:
        rows = conn.execute("SELECT * FROM friends ORDER BY name").fetchall()
        if not rows:
            print("no friends yet: sharebox friend add NAME")
        for r in rows:
            seen = (datetime.datetime.fromtimestamp(r["last_seen"]).strftime("%Y-%m-%d %H:%M")
                    if r["last_seen"] else "never")
            print(f"{r['name']:<20} last Prowlarr contact: {seen}")


def cmd_list(args):
    conn = db.connect()
    rows = conn.execute("SELECT * FROM torrents ORDER BY added DESC").fetchall()
    tok = media.norm(args.text or "")
    n = size = 0
    for r in rows:
        if tok and tok not in media.norm(r["release"]):
            continue
        n += 1
        size += r["size"]
        print(f"{media.CAT_NAMES[r['category']]:<11} {r['size']/1e9:7.2f} GB  {r['release']}")
    print(f"-- {n} torrent(s), {size/1e12:.2f} TB")


def cmd_scan(_args):
    from .watcher import scan_once
    scan_once()


def cmd_init_qbit(_args):
    path = os.path.join(config.QBIT_CONFIG_DIR, "qBittorrent", "qBittorrent.conf")
    if os.path.exists(path):
        print(f"{path} exists, leaving it alone")
        return
    if not config.QBIT_WEBUI_PASS:
        sys.exit("QBIT_WEBUI_PASS is required to seed qBittorrent.conf")
    salt = os.urandom(16)
    dk = hashlib.pbkdf2_hmac("sha512", config.QBIT_WEBUI_PASS.encode(), salt, 100000, 64)
    pw = f"@ByteArray({base64.b64encode(salt).decode()}:{base64.b64encode(dk).decode()})"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(f"""[BitTorrent]
Session\\Port={config.TORRENT_PORT}
Session\\QueueingSystemEnabled=false
Session\\DHTEnabled=false
Session\\PeXEnabled=false
Session\\LSDEnabled=false
Session\\AnonymousModeEnabled=false
Session\\DefaultSavePath=/downloads

[LegalNotice]
Accepted=true

[Network]
PortForwardingEnabled=false

[Preferences]
Connection\\UPnP=false
WebUI\\Port=8080
WebUI\\Username={config.QBIT_WEBUI_USER}
WebUI\\Password_PBKDF2="{pw}"
WebUI\\AuthSubnetWhitelistEnabled=true
WebUI\\AuthSubnetWhitelist={config.QBIT_AUTH_BYPASS}
WebUI\\LocalHostAuth=true
WebUI\\HostHeaderValidation=false
""")
    for p in (path, os.path.dirname(path), config.QBIT_CONFIG_DIR):
        try:
            os.chown(p, config.PUID, config.PGID)
        except PermissionError:
            pass
    print(f"wrote {path}")


def cmd_serve(_args):
    import uvicorn
    from . import watcher, web

    threading.Thread(target=watcher.run_forever, name="watcher", daemon=True).start()
    proxy = uvicorn.Server(uvicorn.Config(web.proxy, host="0.0.0.0",
                                          port=config.ANNOUNCE_PROXY_PORT, log_level="warning"))
    threading.Thread(target=proxy.run, name="announce-proxy", daemon=True).start()
    uvicorn.run(web.api, host="0.0.0.0", port=config.API_PORT, log_level="info",
                proxy_headers=True, forwarded_allow_ips="*")


def main(argv=None):
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    ap = argparse.ArgumentParser(prog="sharebox")
    sub = ap.add_subparsers(dest="cmd")
    sub.add_parser("serve").set_defaults(fn=cmd_serve)
    f = sub.add_parser("friend")
    f.add_argument("action", choices=["add", "list", "show", "remove"])
    f.add_argument("name", nargs="?")
    f.set_defaults(fn=cmd_friend)
    li = sub.add_parser("list")
    li.add_argument("text", nargs="?")
    li.set_defaults(fn=cmd_list)
    sub.add_parser("scan").set_defaults(fn=cmd_scan)
    sub.add_parser("init-qbit").set_defaults(fn=cmd_init_qbit)
    args = ap.parse_args(argv)
    if not getattr(args, "fn", None):
        args = ap.parse_args(["serve"])
    if args.cmd == "friend" and args.action != "list" and not args.name:
        ap.error("friend add/show/remove needs a NAME")
    args.fn(args)


if __name__ == "__main__":
    main()
