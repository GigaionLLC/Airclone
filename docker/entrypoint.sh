#!/bin/sh
# Starts the Airclone Web UI as an ordinary user.
#
# As root (the default): give the airclone user the PUID/PGID asked for, make
# sure it owns /config, then drop to it. Files Airclone writes to /data are then
# owned by that user on the host, which is the point of PUID/PGID.
set -eu

if [ "$(id -u)" = 0 ]; then
  PUID="${PUID:-1000}"
  PGID="${PGID:-1000}"
  case "$PUID$PGID" in *[!0-9]*) echo "PUID and PGID must be numbers" >&2; exit 1;; esac
  groupmod -o -g "$PGID" airclone
  usermod -o -u "$PUID" airclone
  mkdir -p /config /var/cache/airclone
  # Only /config and the cache. /data is the user's own folders, and changing
  # who owns those is not ours to do.
  if [ "$(stat -c %u:%g /config)" != "$PUID:$PGID" ]; then
    chown -R "$PUID:$PGID" /config
  fi
  chown -R "$PUID:$PGID" /var/cache/airclone
  exec gosu airclone "$0" "$@"
fi

# The Web UI listens on every interface INSIDE the container, which is only
# reachable through the port you publish. The password comes from
# AIRCLONE_WEBUI_PASSWORD when set; otherwise Airclone generates one on first
# start, prints it here (see `docker logs`), and keeps it in /config.
exec xvfb-run -a -s "-screen 0 1280x800x24 -nolisten tcp" \
  /opt/airclone/airclone --webui --webui-bind all --webui-port 5799 "$@"
