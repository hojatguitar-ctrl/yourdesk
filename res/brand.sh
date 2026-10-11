#!/usr/bin/env bash
# Branding patch for the YourDesk fork. Run from the repository root (after checkout with submodules).
# Inputs (environment variables):
#   APP_NAME   display name, letters/digits only (e.g. YourDesk)   [required]
#   APP_ID     Android applicationId (e.g. com.hojatguitar.yourdesk) [required]
#   COMPANY_NAME  shown in Windows file properties (default: APP_NAME)
#   RENDEZVOUS_SERVER, RS_PUB_KEY  optional; when both are set, they replace the default servers/key
set -euo pipefail

: "${APP_NAME:?APP_NAME is required}"
: "${APP_ID:?APP_ID is required}"
export COMPANY_NAME="${COMPANY_NAME:-$APP_NAME}"
export APP_NAME APP_ID

if ! [[ "$APP_NAME" =~ ^[A-Za-z0-9]+$ ]]; then
  echo "ERROR: APP_NAME must contain only letters and digits" >&2; exit 1
fi

CFG=libs/hbb_common/src/config.rs
GRADLE=flutter/android/app/build.gradle
MANIFEST=flutter/android/app/src/main/AndroidManifest.xml
RC=flutter/windows/runner/Runner.rc

for f in "$CFG" "$GRADLE" "$MANIFEST" "$RC"; do
  [ -f "$f" ] || { echo "ERROR: missing $f (is the submodule checked out?)" >&2; exit 1; }
done

# 1) APP_NAME in hbb_common config.rs
perl -pi -e 's/(APP_NAME:\s*RwLock<String>\s*=\s*RwLock::new\()"[^"]*"/$1"$ENV{APP_NAME}"/' "$CFG"
grep -q "RwLock::new(\"$APP_NAME\"" "$CFG" || { echo "ERROR: APP_NAME pattern not found in $CFG" >&2; exit 1; }

# 2) Optional server + key override
if [ -n "${RENDEZVOUS_SERVER:-}" ] && [ -n "${RS_PUB_KEY:-}" ]; then
  perl -0pi -e 's/(RENDEZVOUS_SERVERS:\s*&\[&str\]\s*=\s*&\[)[^\]]*(\])/$1 . "\"" . $ENV{RENDEZVOUS_SERVER} . "\"" . $2/se' "$CFG"
  perl -pi -e 's/(RS_PUB_KEY:\s*&str\s*=\s*)"[^"]*"/$1 . "\"" . $ENV{RS_PUB_KEY} . "\""/e' "$CFG"
  grep -qF "\"$RENDEZVOUS_SERVER\"" "$CFG" || { echo "ERROR: server override failed" >&2; exit 1; }
  grep -qF "\"$RS_PUB_KEY\"" "$CFG" || { echo "ERROR: key override failed" >&2; exit 1; }
  echo "Custom server and key applied."
else
  echo "No custom server configured; keeping upstream defaults."
fi

# 3) Android: applicationId (keep namespace untouched) and visible labels
perl -pi -e 's/(applicationId\s+)"[^"]*"/$1"$ENV{APP_ID}"/' "$GRADLE"
grep -q "applicationId \"$APP_ID\"" "$GRADLE" || { echo "ERROR: applicationId patch failed" >&2; exit 1; }
perl -pi -e 's/android:label="RustDesk Input"/android:label="$ENV{APP_NAME} Input"/; s/android:label="RustDesk"/android:label="$ENV{APP_NAME}"/' "$MANIFEST"
grep -q "android:label=\"$APP_NAME\"" "$MANIFEST" || { echo "ERROR: manifest label patch failed" >&2; exit 1; }

# 4) Windows file properties (exe name itself stays rustdesk.exe)
perl -pi -e '
  s/(VALUE "CompanyName", )"[^"]*"/$1"$ENV{COMPANY_NAME}"/;
  s/(VALUE "FileDescription", )"[^"]*"/$1"$ENV{APP_NAME} Remote Desktop"/;
  s/(VALUE "ProductName", )"[^"]*"/$1"$ENV{APP_NAME}"/;
  s/(VALUE "LegalCopyright", )"[^"]*"/$1"Copyright (C) 2026 $ENV{COMPANY_NAME}. Based on RustDesk (AGPL-3.0)."/;
' "$RC"
grep -q "VALUE \"ProductName\", \"$APP_NAME\"" "$RC" || { echo "ERROR: Runner.rc patch failed" >&2; exit 1; }

# 5) Informational: other visible strings you may want to review manually
echo "--- remaining 'RustDesk' mentions in Android resources (review manually) ---"
grep -rn "RustDesk" flutter/android/app/src/main/res/values* 2>/dev/null || true
echo "Branding applied."
