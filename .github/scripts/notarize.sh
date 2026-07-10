#!/usr/bin/env bash
# Bounded, debuggable notarytool submission — adapted from the abcli notarization
# playbook (2026-07). Key rules encoded here:
#   * NEVER a naked `--wait`: every submit is bounded by --timeout, so a stuck
#     Apple submission fails fast instead of hanging until the CI job's SIGKILL.
#   * Capture the submission id (--output-format json) and ALWAYS dump
#     `notarytool log` — makes rejected-vs-stuck-vs-lost diagnosable from CI logs.
#   * Retry ONLY fast failures that never registered a submission (transient
#     5xx/network). Never re-upload after a polling timeout: Apple keeps
#     processing server-side, and a later run can still staple.
#
# Usage: notarize.sh <artifact> <tag>
# Env:   APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID
#        NOTARY_TIMEOUT (default 20m), NOTARY_RETRIES (default 2),
#        NOTARY_RETRY_WINDOW (secs; >= this means "was a timeout, don't re-upload"; default 120)
# Exits 0 only when the submission is Accepted. Stapling is the caller's job.
set -euo pipefail

artifact="$1"; tag="$2"
out="${RUNNER_TEMP:-/tmp}/notary-$tag.json"
err="${RUNNER_TEMP:-/tmp}/notary-$tag.err"
attempt=1 rc=0 status="" subid="" started=0 elapsed=0

while :; do
  rm -f "$out" "$err"; started=$SECONDS
  set +e
  xcrun notarytool submit "$artifact" \
    --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID" \
    --timeout "${NOTARY_TIMEOUT:-20m}" --wait --output-format json >"$out" 2>"$err"
  rc=$?; set -e
  elapsed=$((SECONDS - started))
  subid="$(/usr/bin/plutil -extract id raw -o - "$out" 2>/dev/null || true)"
  [ -n "$subid" ] || subid="$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$out" 2>/dev/null | head -n1)"
  status="$(/usr/bin/plutil -extract status raw -o - "$out" 2>/dev/null || true)"
  [ -n "$status" ] || status="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$out" 2>/dev/null | head -n1)"

  if   [ "$rc" -eq 0 ] && [ "$status" = "Accepted" ]; then break        # success
  elif [ -n "$subid" ]; then break                                      # registered -> report, never re-upload
  elif [ "$elapsed" -ge "${NOTARY_RETRY_WINDOW:-120}" ]; then break     # polling timeout -> never re-upload
  elif [ "$attempt" -ge "$(( ${NOTARY_RETRIES:-2} + 1 ))" ]; then break # exhausted
  fi
  echo "notarize $tag: fast failure without a submission id (attempt $attempt, rc=$rc, ${elapsed}s) — retrying" >&2
  attempt=$((attempt + 1)); sleep $((attempt * 15))
done

if [ -n "$subid" ]; then
  echo "notarize $tag: submission $subid -> ${status:-unknown}" >&2
  xcrun notarytool log "$subid" \
    --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID" >&2 \
    || echo "notarize $tag: could not fetch the notary log" >&2
else
  echo "notarize $tag: no submission id after ${elapsed}s — check \`xcrun notarytool history\` for this team" >&2
  cat "$out" "$err" >&2 2>/dev/null || true
fi

[ "$status" = "Accepted" ] || { echo "notarize $tag: NOT Accepted (status: ${status:-none})" >&2; exit 1; }
