#!/usr/bin/env bash
# Sentry dSYM upload — invoked by Xcode "Upload Symbols to Sentry" build phase.
#
# Skips Debug builds (no dSYMs produced). Pulls auth token from macOS Keychain
# so it never lands in git.
#
# One-time setup (per machine):
#   1. Create a Sentry auth token at:
#        https://sentry.io/settings/account/api/auth-tokens/
#      Required scope: Project = Write (covers Debug Files upload).
#      Alternative: Organization Auth Token (Settings → Auth Tokens at org level)
#      auto-includes the right scopes.
#   2. Store it in Keychain:
#        security add-generic-password -s sentry-cli-latergram -a "$USER" -w <token>
#
# Build failures here never block the build — warning + exit 0.

set -uo pipefail

SENTRY_ORG="ininder"
SENTRY_PROJECT="latergram"
KEYCHAIN_SERVICE="sentry-cli-latergram"

if [[ "${CONFIGURATION:-}" == "Debug" ]]; then
  echo "[sentry] Debug build — skipping dSYM upload"
  exit 0
fi

if command -v sentry-cli >/dev/null 2>&1; then
  SENTRY_CLI=$(command -v sentry-cli)
elif [[ -x /opt/homebrew/bin/sentry-cli ]]; then
  SENTRY_CLI=/opt/homebrew/bin/sentry-cli
elif [[ -x /usr/local/bin/sentry-cli ]]; then
  SENTRY_CLI=/usr/local/bin/sentry-cli
else
  echo "warning: sentry-cli not found — install via 'brew install getsentry/tools/sentry-cli'"
  exit 0
fi

SENTRY_AUTH_TOKEN=$(security find-generic-password -s "${KEYCHAIN_SERVICE}" -a "${USER}" -w 2>/dev/null || true)
if [[ -z "${SENTRY_AUTH_TOKEN}" ]]; then
  cat >&2 <<EOF
warning: Sentry auth token not in Keychain — skipping dSYM upload.
Set it once with:
  security add-generic-password -s ${KEYCHAIN_SERVICE} -a "\$USER" -w <token>
Token page: https://sentry.io/settings/account/api/auth-tokens/ (scope: Project = Write)
EOF
  exit 0
fi
export SENTRY_AUTH_TOKEN

DSYM_PATH="${DWARF_DSYM_FOLDER_PATH:-}"
if [[ -z "${DSYM_PATH}" || ! -d "${DSYM_PATH}" ]]; then
  echo "warning: DWARF_DSYM_FOLDER_PATH missing — nothing to upload"
  exit 0
fi

echo "[sentry] uploading dSYMs from ${DSYM_PATH}"
"${SENTRY_CLI}" debug-files upload \
  --org "${SENTRY_ORG}" \
  --project "${SENTRY_PROJECT}" \
  "${DSYM_PATH}" || {
  echo "warning: sentry-cli dSYM upload failed (build continues)"
  exit 0
}
