# syntax=docker/dockerfile:1
# =============================================================================
#  NetworkMiner (free edition) — pull files, images and emails out of pcaps,
#  in a browser
#  Debian 13 "trixie" + Mono + NetworkMiner + TigerVNC + noVNC
# =============================================================================
#
#  WHAT THIS IS
#  ------------
#  NetworkMiner rebuilds what went across the wire: files, images, emails
#  (with MIME attachments), credentials, hosts and sessions. It is a Windows
#  .NET app that Netresec supports on Linux under Mono, so the container runs
#  it on a private X/VNC desktop and serves that desktop to your browser with
#  noVNC.
#
#  Encrypted traffic (HTTPS, SMTP/IMAP over TLS) can't be reassembled; plain
#  HTTP, FTP, SMB, SMTP, MQTT etc. can.
#
#  WAYS TO FEED IT
#  ---------------
#   1. Open a pcap: File > Open, e.g. from /pcap or from Arkime's pcap folder
#      mounted read-only at /arkime-raw.
#   2. Live: set CAPTURE_INTERFACE, then in NetworkMiner choose
#      File > Receive PCAP over IP > Start Receiving (port 57013). The
#      built-in feeder (gui-sidecar) notices the listener and streams the
#      interface into it with tcpdump. Do this again after NetworkMiner restarts.
#
#  BUILD CONTEXT LAYOUT
#  --------------------
#  Built from the repo root:
#
#    networkminer.dockerfile
#    novnc-gui/rootfs/                 shared with etherape.dockerfile
#      usr/local/sbin/gui-entrypoint     Xtigervnc + openbox + noVNC, runs gui-app
#    networkminer/rootfs/
#      usr/local/bin/gui-prestart        NIC up/promiscuous, creates /data dirs
#      usr/local/bin/gui-app             mono NetworkMiner.exe --noupdatecheck
#      usr/local/bin/gui-sidecar         PCAP-over-IP live feeder (tcpdump | nc)
#
#  BUILD
#  -----
#    docker build -f networkminer.dockerfile -t aarondvail/networkminer .
#
#  Build args (optional):
#    NM_URL=...       download URL (default: Netresec's "latest" link)
#    NM_SHA256=...    pin the zip. Netresec publishes the hash on the
#                     NetworkMiner page; pass it so a changed download fails
#                     the build instead of shipping.
#
#  RUN
#  ---
#    docker run -d --name NetworkMiner --restart unless-stopped \
#      --network host --cap-add NET_RAW --cap-add NET_ADMIN \
#      -e CAPTURE_INTERFACE=eth1 -e VNC_PASSWORD=... -e NOVNC_PORT=6081 \
#      -v /opt/port/NetworkMiner/AssembledFiles:/data/AssembledFiles \
#      -v /opt/port/NetworkMiner/Captures:/data/Captures \
#      -v /opt/port/NetworkMiner/pcap:/pcap \
#      -v /opt/port/Arkime/raw:/arkime-raw:ro \
#      aarondvail/networkminer
#    then browse to http://<docker-host>:6081/
#
#  RUNTIME ENVIRONMENT
#  -------------------
#    CAPTURE_INTERFACE     NIC for the live feeder; unset = pcap files only
#    NM_CAPTURE_FILTER     extra BPF filter for the feeder, e.g. "not port 22"
#    NM_PCAP_OVER_IP_PORT  default 57013
#    NM_OPEN_FILE          pcap to open when NetworkMiner starts
#    VNC_PASSWORD          password the noVNC page asks for (first 8 chars count)
#    NOVNC_PORT=6081       web port on the host (6080 is EtherApe's default)
#    GEOMETRY=1600x900     desktop size
#  Closing the NetworkMiner window restarts it.
#
#  BIND MOUNTS
#  -----------
#    /data/AssembledFiles  everything NetworkMiner extracts (images, files,
#                          emails), one folder per source host
#    /data/Captures        pcaps NetworkMiner itself saves
#    /pcap                 your pcaps to open
#    /arkime-raw           (optional, read-only) Arkime's pcap directory
#
#  KNOWN CAVEATS
#  -------------
#  - Under Mono, NetworkMiner converts Unicode MIME text to ASCII (Netresec's
#    note), so non-English email bodies come out mangled; attachments are fine.
#  - noVNC is plain HTTP. Put it behind SWAG (with auth) beyond the LAN.
# =============================================================================

FROM debian:trixie-slim

LABEL maintainer="aarondvail" description="NetworkMiner (free) under Mono via noVNC"

ARG NM_URL="https://www.netresec.com/?download=NetworkMiner"
ARG NM_SHA256=

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      mono-complete libgdiplus libgtk2.0-0 \
      tigervnc-standalone-server tigervnc-tools \
      novnc python3-websockify \
      openbox fonts-dejavu-core \
      tcpdump netcat-openbsd iproute2 procps \
      ca-certificates curl unzip tini tzdata \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- NetworkMiner -----------------------------------------------------------
# Unpacks to /opt/NetworkMiner_<version>; renamed to /opt/NetworkMiner.
# AssembledFiles/ and Captures/ (its output folders) become links to /data.
RUN set -eux; \
    curl -fsSL -o /tmp/nm.zip "${NM_URL}"; \
    echo "NetworkMiner zip sha256: $(sha256sum /tmp/nm.zip | cut -d' ' -f1)"; \
    if [ -n "${NM_SHA256}" ]; then echo "${NM_SHA256}  /tmp/nm.zip" | sha256sum -c -; fi; \
    unzip -q /tmp/nm.zip -d /opt/; \
    rm /tmp/nm.zip; \
    mv /opt/NetworkMiner_* /opt/NetworkMiner; \
    chmod +x /opt/NetworkMiner/NetworkMiner.exe; \
    for d in AssembledFiles Captures; do \
        rm -rf "/opt/NetworkMiner/$d"; \
        ln -s "/data/$d" "/opt/NetworkMiner/$d"; \
    done; \
    mkdir -p /data/AssembledFiles /data/Captures /pcap

# noVNC: land on the client page and auto-connect, scaled to the browser.
# openbox: open application windows maximized (dialogs stay normal).
RUN printf '%s\n' '<!DOCTYPE html><meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=1&resize=scale&reconnect=1">' \
      > /usr/share/novnc/index.html \
 && rule='<application class="*" type="normal"><maximized>yes</maximized></application>' \
 && if grep -q '</applications>' /etc/xdg/openbox/rc.xml; then \
        sed -i "s#</applications>#${rule}</applications>#" /etc/xdg/openbox/rc.xml; \
    else \
        sed -i "s#</openbox_config>#<applications>${rule}</applications></openbox_config>#" /etc/xdg/openbox/rc.xml; \
    fi

COPY novnc-gui/rootfs/ /
COPY networkminer/rootfs/ /
RUN chmod 0755 /usr/local/sbin/gui-entrypoint /usr/local/bin/gui-prestart \
               /usr/local/bin/gui-app /usr/local/bin/gui-sidecar

ENV APP_TITLE=NetworkMiner \
    NOVNC_PORT=6081

EXPOSE 6081
VOLUME ["/data/AssembledFiles", "/data/Captures", "/pcap"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ["sh", "-c", "python3 -c \"import urllib.request,os; urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('NOVNC_PORT','6081')+'/vnc.html', timeout=4)\""]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/sbin/gui-entrypoint"]
