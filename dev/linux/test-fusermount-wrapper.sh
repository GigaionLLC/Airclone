#!/usr/bin/env bash
# Tests the Flatpak fusermount wrapper against a fake flatpak-spawn.
#
# The wrapper decides three things that are invisible until a mount fails on
# someone's machine: whether it has permission to reach the host, which host
# helper to run (fuse3 or fuse2), and exactly which file descriptors to forward
# so rclone receives /dev/fuse back. A wrong descriptor mounts the drive on the
# host and leaves rclone waiting forever for a descriptor that never arrives.
#
# The fake records every call. It is configured per case by two variables:
#   FAKE_HOST_OK=1|0        whether `flatpak-spawn --host true` succeeds
#   FAKE_HOST_HELPERS="…"   which helper names exist on the "host"
#
# Usage: dev/linux/test-fusermount-wrapper.sh
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$REPO/app/linux/packaging/fusermount-wrapper.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/app"

bash -n "$WRAPPER"

# The wrapper is installed under two names and behaves by the name it was run as.
cp "$WRAPPER" "$T/app/fusermount3"
cp "$WRAPPER" "$T/app/fusermount"
chmod +x "$T/app/fusermount3" "$T/app/fusermount"

cat > "$T/bin/flatpak-spawn" <<'FAKE'
#!/usr/bin/env bash
# Records the call, then behaves like the host the test described.
printf '%s\n' "$*" >> "$FAKE_LOG"
[ "${1:-}" = "--host" ] || exit 2
shift
# Permission probe.
if [ "${1:-}" = "true" ]; then
  [ "${FAKE_HOST_OK:-1}" = "1" ]
  exit $?
fi
# Helper probe: sh -c 'command -v "$1"' sh <candidate>
if [ "${1:-}" = "sh" ] && [ "${2:-}" = "-c" ]; then
  candidate="${5:-}"
  case " $FAKE_HOST_HELPERS " in
    *" $candidate "*) exit 0 ;;
    *) exit 1 ;;
  esac
fi
# The real run: print what would have been exec'd on the host.
echo "EXEC $*"
FAKE
chmod +x "$T/bin/flatpak-spawn"

pass=0
fail=0
run_case() {
  local name="$1" invoke="$2" host_ok="$3" helpers="$4" commfd="$5"
  shift 5
  local expect_rc="$1" expect_out="$2"
  shift 2
  : > "$T/log"
  set +e
  out="$(env -i PATH="$T/bin:/usr/bin:/bin" HOME=/tmp FAKE_LOG="$T/log" \
    FAKE_HOST_OK="$host_ok" FAKE_HOST_HELPERS="$helpers" \
    ${commfd:+_FUSE_COMMFD=$commfd} \
    "$T/app/$invoke" "$@" 2>&1)"
  rc=$?
  set -e
  if [ "$rc" = "$expect_rc" ] && printf '%s' "$out" | grep -qF -- "$expect_out"; then
    echo "PASS  $name"
    pass=$((pass + 1))
  else
    echo "FAIL  $name"
    echo "      wanted rc=$expect_rc and output containing: $expect_out"
    echo "      got    rc=$rc: $out"
    fail=$((fail + 1))
  fi
}

# rclone's real call shape: _FUSE_COMMFD set, options, then the mount point.
run_case "fuse3 host: forwards the comm socket and runs fusermount3" \
  fusermount3 1 "fusermount3 fusermount" 5 \
  0 "EXEC --env=_FUSE_COMMFD=5 --forward-fd=5 fusermount3 -o rw,nosuid /home/u/Airclone/drive" \
  -o rw,nosuid /home/u/Airclone/drive

run_case "a /dev/fd/N argument is forwarded as well" \
  fusermount3 1 "fusermount3" 4 \
  0 "--forward-fd=4 --forward-fd=7 fusermount3 /dev/fd/7" \
  /dev/fd/7

run_case "fuse2-only host: falls back to fusermount rather than failing" \
  fusermount3 1 "fusermount" 5 \
  0 "EXEC --env=_FUSE_COMMFD=5 --forward-fd=5 fusermount /home/u/mnt" \
  /home/u/mnt

run_case "unmount (-u) passes straight through, no descriptors" \
  fusermount3 1 "fusermount3" "" \
  0 "EXEC fusermount3 -u /home/u/Airclone/drive" \
  -u /home/u/Airclone/drive

run_case "NO PERMISSION: says so and names the command, instead of 'no FUSE'" \
  fusermount3 0 "fusermount3 fusermount" 5 \
  1 "talk-name=org.freedesktop.Flatpak" \
  /home/u/mnt

run_case "no FUSE on the host: says FUSE is missing" \
  fusermount3 1 "" 5 \
  127 "FUSE is not installed" \
  /home/u/mnt

run_case "a non-numeric _FUSE_COMMFD is refused, never forwarded" \
  fusermount3 1 "fusermount3" "5;rm" \
  1 "not a file descriptor number" \
  /home/u/mnt

run_case "a /dev/fd argument that is not a number is not forwarded" \
  fusermount3 1 "fusermount3" "" \
  0 "EXEC fusermount3 /dev/fd/x" \
  /dev/fd/x

# The permission probe must run BEFORE any helper probe, or a sandbox without
# permission reports "FUSE is not installed", which is the wrong fix to suggest.
: > "$T/log"
env -i PATH="$T/bin:/usr/bin:/bin" HOME=/tmp FAKE_LOG="$T/log" FAKE_HOST_OK=0 \
  FAKE_HOST_HELPERS="fusermount3" "$T/app/fusermount3" /home/u/mnt >/dev/null 2>&1 || true
if [ "$(grep -c . "$T/log")" = "1" ] && grep -qx -- "--host true" "$T/log"; then
  echo "PASS  without permission, nothing past the permission probe is attempted"
  pass=$((pass + 1))
else
  echo "FAIL  without permission, the wrapper went on to: $(cat "$T/log")"
  fail=$((fail + 1))
fi

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
