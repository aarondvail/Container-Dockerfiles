#!/bin/bash
# Usage: entrypoint.sh all|web|cot_parser|eud_handler|eud_handler_ssl|mediamtx
#   all (default) = run every OTS process in this one container
set -e

ROLE="${1:-all}"
OTS_DIR=/home/ots/ots
CONFIG="$OTS_DIR/config.yml"
DB_HOST="${DB_HOST:-127.0.0.1}"
RABBITMQ_HOST="${RABBITMQ_HOST:-127.0.0.1}"
PKG_DIR=$(python3 -c "import opentakserver, os; print(os.path.dirname(opentakserver.__file__))")

mkdir -p "$OTS_DIR/logs"

set_key() {  # set_key KEY VALUE  -> replaces "KEY: ..." in config.yml, or appends it
  if grep -q "^$1:" "$CONFIG"; then
    sed -i "s|^$1:.*|$1: $2|" "$CONFIG"
  else
    echo "$1: $2" >> "$CONFIG"
  fi
}

init_ots() {
  until pg_isready -h "$DB_HOST" -U ots -q; do echo "waiting for postgres at $DB_HOST..."; sleep 2; done

  cd "$PKG_DIR"
  if [ ! -f "$CONFIG" ]; then
    echo "Generating config.yml..."
    flask ots generate-config
    sed -i "s|POSTGRESQL_PASSWORD|${POSTGRES_PASSWORD}|g" "$CONFIG"
    sed -i "s|@127.0.0.1|@${DB_HOST}|g; s|@localhost|@${DB_HOST}|g" "$CONFIG"
    set_key OTS_LISTENER_ADDRESS "\"${OTS_LISTENER_ADDRESS:-0.0.0.0}\""
    set_key OTS_RABBITMQ_SERVER_ADDRESS "\"${RABBITMQ_HOST}\""
    [ -n "$OTS_ENABLE_MESHTASTIC" ] && set_key OTS_ENABLE_MESHTASTIC "$OTS_ENABLE_MESHTASTIC"
  fi

  # Applied on every start, so changing these in .env/-e takes effect on restart
  set_key OTS_LISTENER_PORT "${OTS_LISTENER_PORT:-7081}"
  set_key OTS_MEDIAMTX_ENABLE "${OTS_MEDIAMTX_ENABLE:-False}"

  if [ ! -f "$OTS_DIR/ca/ca.pem" ]; then
    echo "Creating certificate authority..."
    mkdir -p "$OTS_DIR/ca"
    flask ots create-ca
  fi

  flask db upgrade
  cd "$OTS_DIR"
}

mediamtx_enabled() {
  case "${OTS_MEDIAMTX_ENABLE:-False}" in [Tt]rue|1|[Yy]es) return 0 ;; *) return 1 ;; esac
}

# Creates $OTS_DIR/mediamtx/mediamtx.yml once (from the installer's config).
# After that it's yours to edit - add cameras under "paths:". Only the port is re-synced.
setup_mediamtx() {
  local MTX_DIR="$OTS_DIR/mediamtx" MTX_CONF="$OTS_DIR/mediamtx/mediamtx.yml"
  local PORT="${OTS_LISTENER_PORT:-7081}"
  mkdir -p "$MTX_DIR/recordings"

  # Webhook token shared by OTS and MediaMTX
  local TOKEN
  TOKEN=$(grep -E '^OTS_MEDIAMTX_TOKEN:' "$CONFIG" | sed -E "s/^OTS_MEDIAMTX_TOKEN: *['\"]?([^'\"]*)['\"]?.*/\1/")
  if [ -z "$TOKEN" ]; then
    TOKEN=$(python3 -c "import secrets; print(secrets.token_urlsafe(30))")
    set_key OTS_MEDIAMTX_TOKEN "\"$TOKEN\""
  fi

  if [ ! -f "$MTX_CONF" ]; then
    echo "Creating $MTX_CONF..."
    sed -e "s|MTX_TOKEN|${TOKEN}|g" \
        -e "s|SERVER_CERT_FILE|${OTS_DIR}/ca/certs/opentakserver/opentakserver.pem|g" \
        -e "s|SERVER_KEY_FILE|${OTS_DIR}/ca/certs/opentakserver/opentakserver.nopass.key|g" \
        -e "s|OTS_FOLDER|${OTS_DIR}|g" \
        /home/ots/mediamtx.yml.template > "$MTX_CONF"
  fi
  # Keep webhook/auth URLs pointed at the current OTS API port
  sed -i -E "s#(localhost|127\.0\.0\.1):[0-9]+/api/#127.0.0.1:${PORT}/api/#g" "$MTX_CONF"
}

wait_for_init() {
  until [ -f "$CONFIG" ] && [ -f "$OTS_DIR/ca/ca.pem" ]; do echo "waiting for config/CA..."; sleep 3; done
  cd "$OTS_DIR"
}

case "$ROLE" in
  all)
    init_ots
    opentakserver &
    sleep 5   # let the main process declare its RabbitMQ exchanges first
    cot_parser &
    eud_handler &
    eud_handler --ssl &
    if mediamtx_enabled; then
      setup_mediamtx
      /opt/mediamtx/mediamtx "$OTS_DIR/mediamtx/mediamtx.yml" &
    fi
    trap 'kill $(jobs -p) 2>/dev/null' TERM INT
    # If any process dies, exit so Docker's restart policy restarts the whole container
    wait -n
    echo "An OTS process exited; stopping container."
    kill $(jobs -p) 2>/dev/null || true
    exit 1
    ;;
  web)             init_ots; exec opentakserver ;;
  cot_parser)      wait_for_init; exec cot_parser ;;
  eud_handler)     wait_for_init; exec eud_handler ;;
  eud_handler_ssl) wait_for_init; exec eud_handler --ssl ;;
  mediamtx)        wait_for_init; setup_mediamtx; exec /opt/mediamtx/mediamtx "$OTS_DIR/mediamtx/mediamtx.yml" ;;
  *) exec "$@" ;;
esac
