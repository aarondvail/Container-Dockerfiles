# syntax=docker/dockerfile:1
# =============================================================================
#  EtherApe — live graphical map of who is talking to whom, in a browser
#  Debian 13 "trixie" + EtherApe + TigerVNC + noVNC
# =============================================================================
#
#  WHAT THIS IS
#  ------------
#  EtherApe draws every host it sees as a node and the traffic between hosts
#  as lines (thicker = more traffic, color = protocol). It is a desktop (GTK)
#  app, so the container runs it on a private X/VNC desktop and serves that
#  desktop to your browser with noVNC. Nothing to install on the client.
#
#  It sniffs passively: give it a NIC cabled to a switch mirror/SPAN port.
#  Without a mirror port it only sees the Docker host's own traffic plus
#  broadcasts.
#
#  BUILD CONTEXT LAYOUT
#  --------------------
#  Built from the repo root (like every image here):
#
#    etherape.dockerfile
#    novnc-gui/rootfs/                 shared with networkminer.dockerfile
#      usr/local/sbin/gui-entrypoint     Xtigervnc + openbox + noVNC, runs gui-app
#    etherape/rootfs/
#      usr/local/bin/gui-prestart        sets CAPTURE_INTERFACE up + promiscuous
#      usr/local/bin/gui-app             launches etherape from the env below
#
#  BUILD
#  -----
#    docker build -f etherape.dockerfile -t aarondvail/etherape .
#
#  RUN
#  ---
#    docker run -d --name EtherApe --restart unless-stopped \
#      --network host --cap-add NET_RAW --cap-add NET_ADMIN \
#      -e CAPTURE_INTERFACE=eth1 -e VNC_PASSWORD=... -e NOVNC_PORT=6080 \
#      -v /opt/port/EtherApe/config:/root/.config \
#      -v /opt/port/EtherApe/pcap:/pcap \
#      aarondvail/etherape
#    then browse to http://<docker-host>:6080/
#
#  Why those flags:
#    --network host       to see the host's NICs (the mirror-port NIC)
#    NET_RAW, NET_ADMIN   packet capture + promiscuous mode, without
#                         --privileged
#
#  RUNTIME ENVIRONMENT
#  -------------------
#    CAPTURE_INTERFACE    NIC to sniff (e.g. eth1). Unset = EtherApe's default.
#    ETHERAPE_MODE=ip     link (MAC-to-MAC) | ip (host-to-host) | tcp (per port)
#    ETHERAPE_FILTER      BPF capture filter, e.g. "not port 53"
#    ETHERAPE_PCAP        replay a saved pcap instead of live capture,
#                         e.g. /pcap/sample.pcap
#    ETHERAPE_ARGS        any other etherape options (space-separated)
#    VNC_PASSWORD         password the noVNC page asks for (first 8 chars count)
#    NOVNC_PORT=6080      web port on the host
#    GEOMETRY=1600x900    desktop size
#  Closing the EtherApe window restarts it.
#
#  BIND MOUNTS
#  -----------
#    /root/.config        EtherApe preferences (colors, node sizes, timeouts)
#    /pcap                pcaps to open with File > Open
#
#  KNOWN CAVEATS
#  -------------
#  - noVNC is plain HTTP. Put it behind SWAG (with auth) for use beyond the LAN.
#  - EtherApe runs as root inside the container (libpcap); the container only
#    gets NET_RAW + NET_ADMIN, not --privileged.
# =============================================================================

FROM debian:trixie-slim

LABEL maintainer="aarondvail" description="EtherApe graphical network monitor via noVNC"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      etherape \
      tigervnc-standalone-server tigervnc-tools \
      novnc python3-websockify \
      openbox fonts-dejavu-core \
      iproute2 procps ca-certificates tini tzdata \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# noVNC: land on the client page and auto-connect, scaled to the browser.
# openbox: open application windows maximized.
RUN printf '%s\n' '<!DOCTYPE html><meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=1&resize=scale&reconnect=1">' \
      > /usr/share/novnc/index.html \
 && rule='<application class="*" type="normal"><maximized>yes</maximized></application>' \
 && if grep -q '</applications>' /etc/xdg/openbox/rc.xml; then \
        sed -i "s#</applications>#${rule}</applications>#" /etc/xdg/openbox/rc.xml; \
    else \
        sed -i "s#</openbox_config>#<applications>${rule}</applications></openbox_config>#" /etc/xdg/openbox/rc.xml; \
    fi

COPY novnc-gui/rootfs/ /
COPY etherape/rootfs/ /
RUN chmod 0755 /usr/local/sbin/gui-entrypoint /usr/local/bin/gui-prestart /usr/local/bin/gui-app \
 && mkdir -p /root/.config /pcap

ENV APP_TITLE=EtherApe \
    NOVNC_PORT=6080 \
    ETHERAPE_MODE=ip

EXPOSE 6080
VOLUME ["/root/.config", "/pcap"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["sh", "-c", "python3 -c \"import urllib.request,os; urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('NOVNC_PORT','6080')+'/vnc.html', timeout=4)\""]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/sbin/gui-entrypoint"]
