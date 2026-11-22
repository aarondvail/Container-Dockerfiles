#!/usr/bin/env bash
# Build step 3 of 3: snapshot the databases, stage the bind-mountable
# directories into /usr/share/ipbx-seed, and remove build-only plumbing.
# (The Dockerfile then copies the finished filesystem into a single-layer
# image, so the moves here don't store the data twice.)
set -uo pipefail
SEED=/usr/share/ipbx-seed
LOG=/var/log/ipbx-build.log

# Directories exposed for bind mounting (must match ipbx-entrypoint)
PERSIST=(/etc/asterisk /var/lib/asterisk /var/spool/asterisk /var/log/asterisk
         /var/www/html /var/spool/hylafax /var/lib/mysql)

say(){ echo "[ipbx-finalize $(date +%T)] $*"; }
die(){
  echo "BUILD FAILED (ipbx-finalize): $*"
  tail -n 40 /var/log/mariadb-build.log 2>/dev/null | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tr -cd '\11\12\40-\176'
  exit 1
}

# --- snapshot DB for external-DB mode ---------------------------------------
systemctl start mariadb || die "MariaDB would not start"
install -d "$SEED"
DUMP=(mariadb-dump -u root -ppassw0rd)
"${DUMP[@]}" --no-data mysql >/dev/null 2>&1 || DUMP=(mariadb-dump)
"${DUMP[@]}" --single-transaction --routines --triggers --events \
  --databases asterisk asteriskcdrdb > "$SEED/ipbx.sql" || die "DB dump failed"
say "database snapshot: $(du -h "$SEED/ipbx.sql" | cut -f1)"
systemctl stop mariadb
kill -TERM -1 2>/dev/null; sleep 3; kill -KILL -1 2>/dev/null

# Keep the as-installed local-DB configs for switching modes at runtime
install -d "$SEED/local"
for f in /etc/freepbx.conf /etc/amportal.conf /etc/odbc.ini; do
  [[ -f $f ]] && cp -a "$f" "$SEED/local/"
done

# Move persistable dirs into the seed
for p in "${PERSIST[@]}"; do
  [[ -d $p ]] || continue
  install -d "$SEED$(dirname "$p")"
  mv "$p" "$SEED$p"
  mkdir -p "$p"
  chown --reference="$SEED$p" "$p"; chmod --reference="$SEED$p" "$p"
done
say "seeded: ${PERSIST[*]}"

# --- undo build-only plumbing ------------------------------------------------
chattr -i /etc/rc.local 2>/dev/null || true
rm -f /usr/local/sbin/systemctl /etc/apt/apt.conf.d/99ipbx-build
apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /root/.cache
say "=== build complete (logs kept: $LOG, /var/log/hylafax-build.log) ==="
