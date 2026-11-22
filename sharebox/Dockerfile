# syntax=docker/dockerfile:1
# =============================================================================
#  sharebox — private torrent sharing for friends' Prowlarr / *arr stacks
# =============================================================================
#
#  WHAT IT DOES
#  ------------
#  Watches your TV and movie folders. Every new episode/movie file becomes a
#  private torrent that is whitelisted on your own tracker and seeded by
#  qBittorrent, with no manual steps. Friends add sharebox to their Prowlarr
#  as a "Generic Torznab" indexer; Sonarr/Radarr then search and grab from you
#  like any other indexer.
#
#  THE STACK (sharebox/compose.yaml)
#  ---------------------------------
#    sharebox-tracker      Torrust Tracker, mode private_listed:
#                          a peer needs a personal key  AND  the torrent must be
#                          whitelisted. Nothing else can use your tracker.
#    sharebox-qbittorrent  linuxserver/qbittorrent: seeds your files (media
#                          mounted read-only), DHT/PeX/LSD off.
#    sharebox              THIS image:
#                            - watcher: new file -> torrent -> whitelist -> seed;
#                              file deleted/replaced (Sonarr upgrade) -> removed
#                            - Torznab API (port 8090) for Prowlarr: search, RSS,
#                              .torrent downloads with the friend's own key
#                            - announce proxy (port 8081, internal) so the local
#                              seeder is announced with your PUBLIC IP
#                            - CLI to add/remove friends
#    sharebox-init         one-shot: seeds qBittorrent.conf on first run
#                          (password, queueing off, API auth bypass for sharebox)
#    SWAG (yours)          publishes https://tracker.<domain> (announce/scrape
#                          only) and https://share.<domain> (Torznab only)
#
#  Flow:  friend's Prowlarr --search--> share.<domain>/api
#         friend's Sonarr  --grab-->   share.<domain>/dl/<hash>.torrent?apikey=
#             (announce URL rewritten to tracker.<domain>/announce/<their key>;
#              same infohash for everyone)
#         friend's client  --announce--> tracker  --peers--> your qBittorrent
#
#  BUILD CONTEXT LAYOUT (same convention as the IncrediblePBX repo)
#  ----------------------------------------------------------------
#    Dockerfile                        <- this file; build from this directory
#    sharebox/
#      compose.yaml                    the full stack
#      .env.example                    secrets/settings for compose (copy to .env)
#      app/sharebox/                   the Python app
#        cli.py      watcher.py  web.py  media.py  clients.py  db.py  config.py
#      tracker/tracker.toml            Torrust config (private_listed)
#      swag/tracker.subdomain.conf     SWAG proxy confs
#      swag/share.subdomain.conf
#
#  BUILD
#  -----
#    docker build -t containerrepo.vail-industries.com/sharebox:1.0 .
#    docker push  containerrepo.vail-industries.com/sharebox:1.0
#
#  DEPLOY
#  ------
#    cd sharebox && cp .env.example .env && nano .env
#    sudo mkdir -p /srv/sharebox/{data,qbittorrent,tracker/lib,tracker/log}
#    sudo chown -R 1000:1000 /srv/sharebox            # = PUID:PGID
#    docker compose up -d
#    docker network connect sharebox swag
#    cp swag/*.subdomain.conf /path/to/swag/config/nginx/proxy-confs/
#    docker restart swag
#  DNS: tracker.<domain> and share.<domain> -> your public IP.
#  Router: forward TORRENT_PORT (default 6881) TCP+UDP to the docker host, so
#  friends can connect to your seeder.
#
#  FRIENDS
#  -------
#    docker exec sharebox sharebox friend add bob      # prints Prowlarr settings
#    docker exec sharebox sharebox friend list
#    docker exec sharebox sharebox friend show bob
#    docker exec sharebox sharebox friend remove bob   # revokes key + API key
#  In Prowlarr: Indexers > Add > "Generic Torznab", URL https://share.<domain>,
#  API Path /api, API Key from the command above.
#
#  OTHER COMMANDS
#  --------------
#    docker exec sharebox sharebox list [text]   what's shared
#    docker exec sharebox sharebox scan          scan now instead of waiting
#    docker logs -f sharebox                     hashing / sharing / removals
#
#  ENVIRONMENT (sharebox container)
#  --------------------------------
#    SHARE_PATHS        "tv=/media/tv;movies=/media/movies" (container paths;
#                       must be mounted at the SAME path in qBittorrent)
#    SHARE_EXISTING     true (default): share the whole existing library.
#                       false: only files that appear after first start.
#    SHAREBOX_PUBLIC_URL   https://share.<domain>
#    TRACKER_PUBLIC_URL    https://tracker.<domain>
#    TRACKER_API_TOKEN     shared secret with the tracker container
#    SEEDER_PUBLIC_IP      auto (default, looked up every 30 min) or a fixed IP
#    SCAN_INTERVAL=300     seconds between library scans
#    SETTLE_SECONDS=600    a file must be unchanged this long before it's
#                          hashed (so half-copied files aren't shared)
#    MIN_SIZE_MB=20        smaller files ignored; "sample"/"-trailer" ignored
#    HASH_THREADS=2        CPU threads used for hashing
#    VIDEO_EXTS            mkv,mp4,avi,m4v,ts,webm,mov,wmv
#    QBIT_URL, TRACKER_API_URL, TRACKER_HTTP_URL, SEEDER_ANNOUNCE_BASE
#                          internal URLs (defaults match compose.yaml)
#    QBIT_USER/QBIT_PASS   only if you turn off the qBittorrent auth bypass
#  sharebox-init only: QBIT_WEBUI_USER, QBIT_WEBUI_PASS, QBIT_AUTH_BYPASS,
#                      TORRENT_PORT, PUID, PGID
#
#  HOW TORRENTS ARE BUILT
#  ----------------------
#  - One single-file torrent per video file, private flag set (BEP 27), so
#    clients use only your tracker: no DHT, PeX or LSD leaks.
#  - Release title = the file name. If the file name lacks the show name
#    (e.g. "S01E02 - Pilot.mkv"), it's taken from the folder: "Show - S01E02...".
#  - Categories: TV 5030/5040/5045 (SD/HD/UHD), Movies 2030/2040/2045.
#  - Hashing reads the whole file once. A large existing library takes a
#    while on first start (roughly disk-read speed); progress is in the logs.
#
#  SAFETY / CAVEATS
#  ----------------
#  - If a share folder is missing or completely empty (e.g. NAS not mounted),
#    nothing under it is removed. Side effect: deleting the very last file in
#    a share won't remove its torrent until something else is in that folder.
#  - qBittorrent's Web API auth is bypassed ONLY for sharebox's fixed IP
#    (172.31.77.10). Don't publish qBittorrent's web UI through SWAG on the
#    sharebox network without keeping that whitelist to /32.
#  - The tracker trusts X-Forwarded-For; the SWAG conf sets it to the client
#    address. Behind Cloudflare you'd need the real-IP module instead.
#  - Share only content you have the right to distribute.
#
# =============================================================================

FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app

# FastAPI + uvicorn (HTTP), httpx (tracker/qBittorrent/announce proxy),
# torf (torrent creation), guessit (season/episode/resolution parsing)
RUN pip install --no-cache-dir \
      "fastapi>=0.115" "uvicorn>=0.32" "httpx>=0.28" "torf>=4.2" "guessit>=3.8"

COPY sharebox/app /app
RUN printf '#!/bin/sh\nexec python -m sharebox.cli "$@"\n' > /usr/local/bin/sharebox \
 && chmod 0755 /usr/local/bin/sharebox \
 && mkdir -p /data && chmod 0777 /data \
 && python -c "import sharebox.cli, sharebox.web, sharebox.watcher"   # import smoke test

# 8090 Torznab API (via SWAG)   8081 announce proxy (internal network only)
EXPOSE 8090 8081
VOLUME ["/data"]

HEALTHCHECK --interval=60s --timeout=5s --start-period=30s \
  CMD python -c "import urllib.request,sys; urllib.request.urlopen('http://127.0.0.1:8090/health', timeout=4)" || exit 1

ENTRYPOINT ["sharebox"]
CMD ["serve"]
