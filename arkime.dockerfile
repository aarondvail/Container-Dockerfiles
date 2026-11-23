# syntax=docker/dockerfile:1
# =============================================================================
#  Arkime — full packet capture, indexed in Elasticsearch, searchable in a
#  web UI (sessions, SPI view, Connections graph, pcap export)
#  Debian 13 "trixie" + Arkime 6 (official .deb) — capture + viewer in one
# =============================================================================
#
#  WHAT THIS IS
#  ------------
#  A pull-and-run Arkime for a single box: one container runs both the
#  capture process (sniffs a mirror-port NIC, writes pcap, indexes sessions
#  into your existing Elasticsearch) and the viewer (web UI on 8005). The
#  database init/upgrade and the admin user are handled on start, so there
#  is no manual Configure / db.pl / add-user step.
#
#  BUILD CONTEXT LAYOUT
#  --------------------
#  Built from the repo root:
#
#    arkime.dockerfile
#    arkime/rootfs/
#      usr/local/sbin/arkime-entrypoint   config seed, NIC tuning, db init,
#                                         admin user, runs capture + viewer
#
#  BUILD
#  -----
#    docker build -f arkime.dockerfile -t aarondvail/arkime .
#    docker build -f arkime.dockerfile --build-arg VERSION_NUMBER=6.9.2 -t aarondvail/arkime:6.9.2 .
#
#  Build args:
#    VERSION_NUMBER     Arkime release to install (Jenkins passes this);
#                       empty = ARKIME_VERSION
#    ARKIME_VERSION     default release (6.9.2)
#    ARKIME_DEB_REV=1   package revision in the .deb file name
#  The .deb comes from github.com/arkime/arkime/releases. The IANA and OUI
#  lookup files are fetched at build time; MaxMind GeoLite2 is not included
#  (needs a MaxMind account) - Arkime just logs a warning without it.
#
#  RUN
#  ---
#    docker run -d --name Arkime --restart unless-stopped \
#      --network host --cap-add NET_RAW --cap-add NET_ADMIN --stop-timeout 60 \
#      -e ES_URL=http://127.0.0.1:9200 -e ES_USER=elastic -e ES_PASS=... \
#      -e CAPTURE_INTERFACE=eth1 -e ARKIME_ADMIN_PASSWORD=... \
#      -v /opt/port/Arkime/etc:/opt/arkime/etc \
#      -v /opt/port/Arkime/raw:/opt/arkime/raw \
#      aarondvail/arkime
#    then browse to http://<docker-host>:8005/ and log in as admin
#
#  Why those flags:
#    --network host       to see the mirror-port NIC
#    NET_RAW, NET_ADMIN   capture, promiscuous mode, ethtool offload tuning
#    --stop-timeout 60    capture writes out open sessions on shutdown
#
#  RUNTIME ENVIRONMENT
#  -------------------
#  Elasticsearch / OpenSearch (Elasticsearch 7.10+ or 8.x, or OpenSearch):
#    ES_URL=http://127.0.0.1:9200
#    ES_USER, ES_PASS        if security is on; passed as env, never written
#                            to config.ini
#    ES_INSECURE=0|1         1 = don't verify a self-signed TLS certificate
#    ARKIME_PREFIX=arkime_   prefix on every Arkime index, so they sit apart
#                            from anything else in the cluster
#  Capture:
#    CAPTURE_INTERFACE       NIC on the mirror/SPAN port (no IP address);
#                            several: "eth1;eth2". Unset = viewer only.
#    ARKIME_CAPTURE=1        0 = viewer only (e.g. on a second host)
#    ARKIME_NODE=arkime      Arkime node name (keeps pcap/session links
#                            stable if the Docker host is renamed)
#    ARKIME_TUNE_INTERFACE=1 set the NIC up/promiscuous and turn offloads off
#                            (this is the HOST's NIC - fine for a dedicated
#                            mirror NIC; 0 to leave it alone)
#  Retention:
#    ARKIME_FREESPACE=5%     oldest pcap files are deleted to keep this much
#                            disk free on /opt/arkime/raw (or e.g. 100 for GB)
#    ARKIME_EXPIRE_DAYS=30   daily session indices kept in Elasticsearch;
#                            0 = never expire
#  Viewer:
#    ARKIME_VIEW_PORT=8005
#    ARKIME_ADMIN_USER=admin
#    ARKIME_ADMIN_PASSWORD   creates the admin user on first start only;
#                            change it later in the UI (Users page)
#  Anything else: any ARKIME__<setting>=value overrides that config.ini
#  setting, e.g. ARKIME__maxFileSizeG=4
#
#  BIND MOUNTS
#  -----------
#    /opt/arkime/etc   config.ini (created on first start, then yours to edit),
#                      ipv4-address-space.csv, oui.txt
#    /opt/arkime/raw   pcap files - this is what fills your disk; size it,
#                      and set ARKIME_FREESPACE
#
#  KNOWN CAVEATS
#  -------------
#  - Encrypted payloads (TLS) are indexed by metadata only (SNI, certificates).
#  - Elasticsearch needs real heap for this (4 GB+). A single-node cluster
#    reports yellow; that's expected and fine.
#  - The viewer is plain HTTP with its own login. Put it behind SWAG for HTTPS.
# =============================================================================

FROM debian:trixie-slim

LABEL maintainer="aarondvail" description="Arkime capture + viewer"

ARG VERSION_NUMBER=
ARG ARKIME_VERSION=6.9.2
ARG ARKIME_DEB_REV=1

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# Install the official .deb (pulls its own runtime deps from Debian), fetch
# the IANA/OUI lookup files, then keep the packaged etc/ as samples so an
# empty bind mount on /opt/arkime/etc can be seeded from it.
RUN set -eux; \
    v="${VERSION_NUMBER:-$ARKIME_VERSION}"; v="${v#v}"; \
    arch="$(dpkg --print-architecture)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl procps iproute2 ethtool tini tzdata; \
    curl -fsSL -o /tmp/arkime.deb \
        "https://github.com/arkime/arkime/releases/download/v${v}/arkime_${v}-${ARKIME_DEB_REV}.debian13_${arch}.deb"; \
    apt-get install -y --no-install-recommends /tmp/arkime.deb; \
    rm /tmp/arkime.deb; \
    MOLOCH_DIR=/opt/arkime /opt/arkime/bin/arkime_update_geo.sh || true; \
    mv /opt/arkime/etc /opt/arkime/samples; \
    mkdir -p /opt/arkime/etc /opt/arkime/raw; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

COPY arkime/rootfs/ /
RUN chmod 0755 /usr/local/sbin/arkime-entrypoint

ENV ARKIME_VIEW_PORT=8005

EXPOSE 8005
VOLUME ["/opt/arkime/etc", "/opt/arkime/raw"]

# The viewer answers 401 until you log in, which still means "up".
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD ["sh", "-c", "c=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:${ARKIME_VIEW_PORT}/); [ \"$c\" = 401 ] || [ \"$c\" = 200 ]"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/sbin/arkime-entrypoint"]
