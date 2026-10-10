#!/usr/bin/env bash
# Starts an Airclone image and proves the Web UI works, the way a user would
# meet it: the login page loads over HTTPS, the password from
# AIRCLONE_WEBUI_PASSWORD signs in, and a wrong one is refused.
#
# Usage: docker/smoke-test.sh <image>
# A green build is not proof (AGENT.md rule 9): this runs the artifact.
set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh <image>}"
NAME="airclone-smoke-$$"
PASS="smoke-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
PORT=15799
CONFIG="$(mktemp -d)"
chmod 777 "$CONFIG"

cleanup() {
  echo "--- container log (tail) ---"
  docker logs "$NAME" 2>&1 | tail -40 | sed "s/$PASS/<redacted>/g" || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --name "$NAME" -p "127.0.0.1:$PORT:5799" \
  -e AIRCLONE_WEBUI_PASSWORD="$PASS" -e PUID="$(id -u)" -e PGID="$(id -g)" \
  -v "$CONFIG:/config" "$IMAGE" >/dev/null

echo "waiting for the Web UI..."
for i in $(seq 1 60); do
  if curl -fsk -o /dev/null "https://127.0.0.1:$PORT/login"; then
    echo "login page answered after ~$((i * 2))s"
    break
  fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" != "true" ]; then
    echo "::error::the container exited"; exit 1
  fi
  sleep 2
  [ "$i" -eq 60 ] && { echo "::error::the Web UI never answered"; exit 1; }
done

login() { # password -> HTTP status
  curl -sk -o /dev/null -w '%{http_code}' -X POST \
    -H 'content-type: application/json' -H 'x-airclone-webui: 1' \
    --data "{\"username\":\"airclone\",\"password\":\"$1\"}" \
    "https://127.0.0.1:$PORT/api/login"
}

code="$(login "$PASS")"
[ "$code" = 200 ] || { echo "::error::the env password did not sign in (HTTP $code)"; exit 1; }
echo "AIRCLONE_WEBUI_PASSWORD signs in"

code="$(login "wrong-$PASS")"
[ "$code" = 401 ] || { echo "::error::a wrong password was not refused (HTTP $code)"; exit 1; }
echo "a wrong password is refused"

# State lands in the /config volume, and a password from the environment is
# never written to disk.
find "$CONFIG" -maxdepth 3 | head -20
[ -n "$(find "$CONFIG" -mindepth 1 -print -quit)" ] \
  || { echo "::error::nothing was written to /config"; exit 1; }
if grep -rqs -- "$PASS" "$CONFIG"; then
  echo "::error::the environment password was written into /config"; exit 1
fi
echo "state is in /config, and the env password is not stored"

health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$NAME")"
echo "health: ${health:-none yet}"
echo "SMOKE TEST PASSED for $IMAGE"
