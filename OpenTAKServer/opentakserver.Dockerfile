# OpenTAKServer on Debian - single container running all OTS processes (see run.sh)
# If pip has trouble with Debian stable's newer Python, change this to debian:bookworm-slim.
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        locales ca-certificates curl nano net-tools openssl ffmpeg nginx \
        python3 python3-pip python3-venv python3-dev build-essential libpq-dev postgresql-client && \
    sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen && \
    rm -rf /var/lib/apt/lists/*

# The OTS installer won't run as root and keeps everything under ~/ots; mirror that layout
RUN useradd -m -s /bin/bash ots

## nginx runs as the ots user: no user directive, pid/logs/temp in writable places,
## and no default site (SWAG owns 80/443 on the host network)
#RUN rm -f /etc/nginx/sites-enabled/default && \
#    sed -i -e '/^user /d' \
#           -e 's|^pid .*|pid /tmp/nginx/nginx.pid;|' \
#           -e 's|^\s*error_log .*|error_log stderr;|' \
#           -e 's|^\s*access_log .*|access_log /dev/stdout;|' \
#           /etc/nginx/nginx.conf && \
#    mkdir -p /tmp/nginx /var/www/html/opentakserver && \
#    chown -R ots:ots /tmp/nginx /var/lib/nginx /var/log/nginx /var/www/html/opentakserver

# nginx runs as the ots user with our own minimal main config
COPY nginx.conf /etc/nginx/nginx.conf
RUN mkdir -p /etc/nginx/conf.d /tmp/nginx /var/lib/nginx /var/log/nginx /var/www/html/opentakserver && \
    chown -R ots:ots /tmp/nginx /var/lib/nginx /var/log/nginx /var/www/html/opentakserver

COPY ots-nginx.conf /etc/nginx/conf.d/opentakserver.conf
COPY start-nginx.sh /usr/local/bin/start-nginx.sh
RUN chmod 755 /usr/local/bin/start-nginx.sh

# MediaMTX (video server), same version the OTS installer pins
ARG MEDIAMTX_VERSION=1.13.0
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in amd64) A=amd64 ;; arm64) A=arm64 ;; armhf) A=armv7 ;; *) echo "unsupported arch $ARCH"; exit 1 ;; esac && \
    mkdir -p /opt/mediamtx && \
    curl -fsSL "https://github.com/bluenviron/mediamtx/releases/download/v${MEDIAMTX_VERSION}/mediamtx_v${MEDIAMTX_VERSION}_linux_${A}.tar.gz" \
      | tar -xz -C /opt/mediamtx mediamtx
	  
USER ots
WORKDIR /home/ots

RUN python3 -m venv /home/ots/.opentakserver_venv && \
    /home/ots/.opentakserver_venv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel && \
    /home/ots/.opentakserver_venv/bin/pip install --no-cache-dir opentakserver

ENV PATH="/home/ots/.opentakserver_venv/bin:${PATH}"

COPY --chown=ots:ots entrypoint.sh /home/ots/entrypoint.sh
COPY --chown=ots:ots mediamtx.yml.template /home/ots/mediamtx.yml.template
RUN chmod +x /home/ots/entrypoint.sh && mkdir -p /home/ots/ots/logs

# Local fix for OTS 1.8.0 cot_parser mapper error (federation models not imported).
# Mirrors EudHandler.py's imports. Remove once fixed upstream.
RUN f=$(ls /home/ots/.opentakserver_venv/lib/python3*/site-packages/opentakserver/cot_parser/cot_parser.py) && \
    grep -q 'models.FederationGroups import' "$f" || printf '%s\n' \
      '' \
      '# local fix: federation models (matches EudHandler.py)' \
      'from opentakserver.models.FederationGroups import FederationGroups  # noqa: E402,F401' \
      'from opentakserver.models.FederationConnection import FederationConnection  # noqa: E402,F401' \
      'from opentakserver.models.Federate import Federate  # noqa: E402,F401' \
      'from opentakserver.models.FederateToken import FederateToken  # noqa: E402,F401' \
      >> "$f"

# Local fix: iTAK sends -1 for unknown speed/course/battery; mesh protobuf fields are unsigned.
RUN f=$(ls /home/ots/.opentakserver_venv/lib/python3*/site-packages/opentakserver/cot_parser/cot_parser.py) && \
    sed -i -E 's/int\(p\.(speed|course|battery)\) if p\.\1 else 0/max(0, int(p.\1)) if p.\1 else 0/' "$f"

# Local fix: Meshtastic points need uid = node id so the web map can match them to EUDs.
RUN f=$(ls /home/ots/.opentakserver_venv/lib/python3*/site-packages/opentakserver/controllers/meshtastic_controller.py) && \
    sed -i 's/^\(\s*\)point\.uid = str(uuid\.uuid4())$/\1point.uid = from_id/' "$f"

# Local fix: Correct the colors on the Web Map
COPY patch_mesh_eud.py /tmp/patch_mesh_eud.py
RUN python3 /tmp/patch_mesh_eud.py

# Local fix: Change the Meshtastic Team to Orange
# Local preference: Meshtastic nodes default to the Orange team (team must exist in the teams table).
RUN f=$(ls /home/ots/.opentakserver_venv/lib/python3*/site-packages/opentakserver/controllers/meshtastic_controller.py) && \
    sed -i 's/"team": "Cyan"/"team": "Orange"/g' "$f" && \
    grep -q '"team": "Orange"' "$f"

VOLUME ["/home/ots/ots"]
# 7081 = API backend, 8088 = TCP CoT, 8089 = SSL CoT,
# 8880 = UI (behind SWAG), 8443 = Marti API (client cert), 8446 = cert enrollment
# EXPOSE 7081 8088 8089 8880 8443 8446 # Pre MediaMTX
# MediaMTX: 8554 RTSP, 8322 RTSPS, 8888 HLS, 8889 WebRTC (+8189/udp), 1935 RTMP, 8890/udp SRT, 9997 API
EXPOSE 7081 8088 8089 8880 8443 8446 8554 8322 8888 8889 1935 9997

#ENTRYPOINT ["/home/ots/entrypoint.sh"]
ENTRYPOINT ["/usr/local/bin/start-nginx.sh"]
CMD ["all"]
