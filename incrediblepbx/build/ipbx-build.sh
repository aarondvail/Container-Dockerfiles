#!/usr/bin/env bash
# Runs inside `docker build`: unattended Incredible PBX install with no systemd,
# then stages the persistable directories into /usr/share/ipbx-seed so the
# runtime entrypoint can populate empty bind mounts.
set -uo pipefail   # no -e: the upstream installer tolerates its own failures

: "${IPBX_URL:?}"
ASTERISK_23=${ASTERISK_23:-n}
IPBX_SHA256=${IPBX_SHA256:-}
BUILD_DIR=$(cd "$(dirname "$0")" && pwd)
LOG=/var/log/ipbx-build.log
SEED=/usr/share/ipbx-seed
export DEBIAN_FRONTEND=noninteractive

# Directories exposed for bind mounting (must match ipbx-entrypoint)
PERSIST=(/etc/asterisk /var/lib/asterisk /var/spool/asterisk /var/log/asterisk
         /var/www/html /var/spool/hylafax /var/lib/mysql)

die(){ echo "BUILD FAILED: $*" >&2; tail -n 80 "$LOG" >&2 2>/dev/null; exit 1; }

# --- non-interactive plumbing ------------------------------------------------
install -m 0755 "$BUILD_DIR/systemctl-shim" /usr/local/sbin/systemctl
hash -r
cat > /etc/apt/apt.conf.d/99ipbx-build <<'EOF'
Dpkg::Options { "--force-confdef"; "--force-confold"; };
APT::Get::Assume-Yes "true";
EOF

# MariaDB must be live before the installer touches it
systemctl start mariadb || die "MariaDB would not start"

# --- fetch + run installer -----------------------------------------------------
cd /root || die "no /root"
wget -q -O IncrediblePBX2026.sh "$IPBX_URL" || die "download failed: $IPBX_URL"
if [[ -n $IPBX_SHA256 ]]; then
  echo "$IPBX_SHA256  IncrediblePBX2026.sh" | sha256sum -c - || die "installer checksum mismatch"
else
  echo "Installer sha256 (pin with --build-arg IPBX_SHA256=...): $(sha256sum IncrediblePBX2026.sh | cut -d' ' -f1)"
fi
chmod +x IncrediblePBX2026.sh

# Only prompts: "prefer Asterisk 23? (y/n)" then "Press Enter to reboot" (gets EOF)
echo "=== Running Incredible PBX installer (Asterisk 23: $ASTERISK_23) ==="
printf '%s\n' "$ASTERISK_23" | ./IncrediblePBX2026.sh 2>&1 | tee "$LOG"

# --- verify ------------------------------------------------------------------
systemctl start mariadb
[[ -f /etc/freepbx.conf ]]          || die "/etc/freepbx.conf missing"
command -v asterisk >/dev/null      || die "asterisk not installed"
command -v fwconsole >/dev/null     || die "fwconsole not installed"
mariadb -u root -ppassw0rd -e 'SELECT 1 FROM asterisk.freepbx_settings LIMIT 1' >/dev/null 2>&1 \
  || mariadb -e 'SELECT 1 FROM asterisk.freepbx_settings LIMIT 1' >/dev/null \
  || die "asterisk database not populated"
echo "=== Install verified ==="

# --- HylaFAX+ / IAXmodem -----------------------------------------------------
if [[ ${WITH_HYLAFAX:-1} == 1 ]]; then
  bash "$BUILD_DIR/hylafax-build.sh" || die "HylaFAX+ build failed"
fi

# --- snapshot DB for external-DB mode, then shut everything down -----------
install -d "$SEED"
DUMP=(mariadb-dump -u root -ppassw0rd)
"${DUMP[@]}" -e 'SELECT 1' >/dev/null 2>&1 || DUMP=(mariadb-dump)
"${DUMP[@]}" --single-transaction --routines --triggers --events \
  --databases asterisk asteriskcdrdb > "$SEED/ipbx.sql" || die "DB dump failed"

fwconsole stop >/dev/null 2>&1 || true
systemctl stop asterisk
systemctl stop mariadb
kill -TERM -1 2>/dev/null; sleep 5; kill -KILL -1 2>/dev/null   # pm2/node, redis, etc.

# Keep the as-installed local-DB configs for switching modes at runtime
install -d "$SEED/local"
for f in /etc/freepbx.conf /etc/amportal.conf /etc/odbc.ini; do
  [[ -f $f ]] && cp -a "$f" "$SEED/local/"
done

# Move persistable dirs into the seed (moved, not copied, to keep the image small)
for p in "${PERSIST[@]}"; do
  [[ -d $p ]] || continue
  install -d "$SEED$(dirname "$p")"
  mv "$p" "$SEED$p"
  mkdir -p "$p"
  chown --reference="$SEED$p" "$p"; chmod --reference="$SEED$p" "$p"
done

# --- undo build-only plumbing ------------------------------------------------
chattr -i /etc/rc.local 2>/dev/null || true
rm -f /usr/local/sbin/systemctl /etc/apt/apt.conf.d/99ipbx-build
apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /root/.cache
echo "=== Build stage complete ==="
