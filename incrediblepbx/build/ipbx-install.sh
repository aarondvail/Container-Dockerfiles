#!/usr/bin/env bash
# Build step 1 of 3 (its own cached layer): unattended Incredible PBX install
# with no systemd. The installer's full output goes to $LOG, not the build
# output: it is several MB, and BuildKit drops a step's output past its log
# limit (2 MiB by default), which would hide any error printed afterwards.
# Progress is printed once a minute; on failure the log tail is printed.
set -uo pipefail   # no -e: the upstream installer tolerates its own failures

: "${IPBX_URL:?}"
ASTERISK_23=${ASTERISK_23:-n}
IPBX_SHA256=${IPBX_SHA256:-}
BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
LOG=/var/log/ipbx-build.log
export DEBIAN_FRONTEND=noninteractive

say(){ echo "[ipbx-install $(date +%T)] $*"; }
die(){
  echo "BUILD FAILED (ipbx-install): $*"
  echo "----- last 120 lines of $LOG -----"
  tail -n 120 "$LOG" 2>/dev/null | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tr -cd '\11\12\40-\176'
  echo "----- end of log -----"
  exit 1
}

# --- non-interactive plumbing (removed again in ipbx-finalize.sh) ----------
install -m 0755 "$BUILD_DIR/systemctl-shim" /usr/local/sbin/systemctl
hash -r
cat > /etc/apt/apt.conf.d/99ipbx-build <<'EOF'
Dpkg::Options { "--force-confdef"; "--force-confold"; };
APT::Get::Assume-Yes "true";
EOF

# MariaDB must be live before the installer touches it
systemctl start mariadb || die "MariaDB would not start"

# --- fetch -----------------------------------------------------------------------
cd /root || die "no /root"
wget -q -O IncrediblePBX2026.sh "$IPBX_URL" || die "download failed: $IPBX_URL"
if [[ -n $IPBX_SHA256 ]]; then
  echo "$IPBX_SHA256  IncrediblePBX2026.sh" | sha256sum -c - || die "installer checksum mismatch"
else
  say "installer sha256 (pin with --build-arg IPBX_SHA256=...): $(sha256sum IncrediblePBX2026.sh | cut -d' ' -f1)"
fi
chmod +x IncrediblePBX2026.sh

# --- run (prompts: "prefer Asterisk 23? (y/n)", then "Press Enter to reboot" gets EOF)
say "running installer (Asterisk 23: $ASTERISK_23); full output -> $LOG"
( printf '%s\n' "$ASTERISK_23" | ./IncrediblePBX2026.sh >"$LOG" 2>&1 ) &
pid=$!
i=0
while kill -0 "$pid" 2>/dev/null; do
  sleep 5
  i=$((i + 1))
  if (( i % 12 == 0 )) && kill -0 "$pid" 2>/dev/null; then
    say "$(tail -n 1 "$LOG" 2>/dev/null | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tr -cd '\40-\176' | cut -c1-140)"
  fi
done
wait "$pid"
say "installer finished (exit $?), $(wc -l < "$LOG") log lines"

# --- verify ------------------------------------------------------------------
systemctl start mariadb
[[ -f /etc/freepbx.conf ]]          || die "/etc/freepbx.conf missing"
command -v asterisk >/dev/null      || die "asterisk not installed"
command -v fwconsole >/dev/null     || die "fwconsole not installed"
mariadb -u root -ppassw0rd -e 'SELECT 1 FROM asterisk.freepbx_settings LIMIT 1' >/dev/null 2>&1 \
  || mariadb -e 'SELECT 1 FROM asterisk.freepbx_settings LIMIT 1' >/dev/null 2>&1 \
  || die "asterisk database not populated"
say "=== Install verified ==="

# --- stop everything cleanly so the layer holds a consistent MariaDB -------
fwconsole stop >/dev/null 2>&1 || true
systemctl stop asterisk
systemctl stop mariadb
kill -TERM -1 2>/dev/null; sleep 5; kill -KILL -1 2>/dev/null   # pm2/node, redis, etc.
say "=== services stopped, install layer complete ==="
