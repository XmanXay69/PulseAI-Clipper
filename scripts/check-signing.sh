#!/usr/bin/env bash
# Checks the Developer ID signing and notarization setup before a release spends half an hour building.
#
#   ./scripts/check-signing.sh            # check only
#   ./scripts/check-signing.sh --import   # also leave the certificate in a keychain for codesign (CI)
#
# Reads five values from the environment (repository secrets in CI; see docs/SIGNING.md):
#   MACOS_CERT_P12        base64 of a "Developer ID Application" certificate exported as .p12
#   MACOS_CERT_PASSWORD   the password chosen when it was exported
#   NOTARY_APPLE_ID       the Apple ID of the developer account
#   NOTARY_PASSWORD       an app-specific password for that Apple ID
#   NOTARY_TEAM_ID        the ten-character Team ID
#
# Exit 0 when none is set (the release is unsigned, as before) or when everything checks out.
# Exit 1 when the setup is half done or something in it is wrong, saying what to fix.
# It never prints a secret.
set -uo pipefail

IMPORT=0
[ "${1:-}" = "--import" ] && IMPORT=1

problems=0
note()  { echo "$1"; [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$1" >> "$GITHUB_STEP_SUMMARY"; return 0; }
wrong() { problems=$((problems + 1)); echo "::error::$1"; [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "- ✗ $1" >> "$GITHUB_STEP_SUMMARY"; return 0; }
good()  { echo "✓ $1"; [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "- ✓ $1" >> "$GITHUB_STEP_SUMMARY"; return 0; }
result() { [ -n "${GITHUB_ENV:-}" ] && echo "$1" >> "$GITHUB_ENV"; return 0; }

names=(MACOS_CERT_P12 MACOS_CERT_PASSWORD NOTARY_APPLE_ID NOTARY_PASSWORD NOTARY_TEAM_ID)
present=(); missing=()
for name in "${names[@]}"; do
  if [ -n "${!name:-}" ]; then present+=("$name"); else missing+=("$name"); fi
done

if [ ${#present[@]} -eq 0 ]; then
  note "Signing is not set up: none of the five secrets is there. The release will be ad-hoc signed, and macOS will ask once before the first launch. docs/SIGNING.md says how to remove that."
  result "PULSE_NOTARIZE=0"
  exit 0
fi
if [ ${#missing[@]} -gt 0 ]; then
  wrong "Signing is half set up. Missing: ${missing[*]}. Add them (docs/SIGNING.md), or remove ${present[*]} to release unsigned."
  exit 1
fi

# What can be told from the values alone.
if ! printf '%s' "$NOTARY_TEAM_ID" | grep -Eq '^[A-Z0-9]{10}$'; then
  wrong "NOTARY_TEAM_ID is not a Team ID. It is ten capital letters and digits, shown under Membership details at developer.apple.com/account."
else
  good "The Team ID has the right shape"
fi
if ! printf '%s' "$NOTARY_APPLE_ID" | grep -Eq '^[^@ ]+@[^@ ]+\.[^@ ]+$'; then
  wrong "NOTARY_APPLE_ID is not an email address. It is the Apple ID you sign in to developer.apple.com with."
else
  good "The Apple ID is an email address"
fi
if ! printf '%s' "$NOTARY_PASSWORD" | grep -Eq '^[a-z]{4}-[a-z]{4}-[a-z]{4}-[a-z]{4}$'; then
  wrong "NOTARY_PASSWORD is not an app-specific password. Those look like abcd-efgh-ijkl-mnop and are made at account.apple.com → Sign-In and Security → App-Specific Passwords. Your normal Apple ID password does not work here."
else
  good "The notary password has the shape of an app-specific password"
fi
WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pulse-signing-$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT
if ! printf '%s' "$MACOS_CERT_P12" | tr -d ' \n\r' | base64 --decode > "$WORK/cert.p12" 2>/dev/null || [ ! -s "$WORK/cert.p12" ]; then
  wrong "MACOS_CERT_P12 is not base64. Make it with: base64 -i DeveloperID.p12 | pbcopy   and paste the result as the secret."
elif [ "$(od -An -tx1 -N1 "$WORK/cert.p12" | tr -d ' ')" != "30" ]; then
  wrong "MACOS_CERT_P12 decodes, but not to a .p12 file. Export the certificate from Keychain Access as Personal Information Exchange (.p12) and base64 that file."
else
  good "The certificate secret decodes to a .p12 file"
fi
[ $problems -gt 0 ] && exit 1

if [ "$(uname)" != "Darwin" ]; then
  note "The values have the right shape. The certificate itself and the Apple sign-in can only be checked on a Mac."
  exit 0
fi

# The certificate: it opens with the password, it is the right kind, it is in date, it belongs to the team.
KEYCHAIN="${RUNNER_TEMP:-$WORK}/pulse-signing.keychain-db"
security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
security create-keychain -p ci "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p ci "$KEYCHAIN"
if ! security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$MACOS_CERT_PASSWORD" -T /usr/bin/codesign >/dev/null 2>"$WORK/import.log"; then
  wrong "The .p12 did not open with MACOS_CERT_PASSWORD. Use the password you typed when exporting it from Keychain Access."
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  exit 1
fi
security set-key-partition-list -S apple-tool:,apple: -s -k ci "$KEYCHAIN" >/dev/null 2>&1 || true
identities="$(security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null || true)"
IDENTITY="$(printf '%s\n' "$identities" | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)"/\1/')"
if [ -z "$IDENTITY" ]; then
  kinds="$(printf '%s\n' "$identities" | sed -nE 's/.*"([^:"]*):.*/\1/p' | sort -u | tr '\n' ',' | sed 's/,$//')"
  if [ -n "$kinds" ]; then
    wrong "The .p12 holds a “$kinds” certificate. Releases outside the App Store need a “Developer ID Application” one: create it at developer.apple.com/account → Certificates, export that, and replace the secret."
  else
    wrong "The .p12 holds no signing identity. It must be exported together with its private key: in Keychain Access pick the certificate under My Certificates (it has a key under it), not under Certificates."
  fi
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  exit 1
fi
good "The certificate opens and is a Developer ID Application certificate"
if security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" > "$WORK/cert.pem" 2>/dev/null && [ -s "$WORK/cert.pem" ]; then
  ends="$(openssl x509 -in "$WORK/cert.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')"
  if ! openssl x509 -in "$WORK/cert.pem" -noout -checkend 0 >/dev/null 2>&1; then
    wrong "The certificate expired on $ends. Create a new Developer ID Application certificate and replace MACOS_CERT_P12."
  elif ! openssl x509 -in "$WORK/cert.pem" -noout -checkend 2592000 >/dev/null 2>&1; then
    echo "::warning::The signing certificate expires on $ends. Renew it before then."
    good "The certificate is in date, but only until $ends"
  else
    good "The certificate is in date until $ends"
  fi
fi
team="$(printf '%s' "$IDENTITY" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')"
if [ -n "$team" ] && [ "$team" != "$NOTARY_TEAM_ID" ]; then
  wrong "The certificate belongs to another team than NOTARY_TEAM_ID. Use the Team ID of the account the certificate was made in."
elif [ -n "$team" ]; then
  good "The certificate and the Team ID belong together"
fi

# Apple's notary service: do the Apple ID, the app-specific password and the team sign in?
if xcrun notarytool history --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID" >/dev/null 2>"$WORK/notary.log"; then
  good "Apple's notary service accepts the Apple ID, the password and the team"
else
  reason="$(grep -Eio 'invalid credentials|401|403|agreement|not.*member|team' "$WORK/notary.log" | head -1)"
  case "$reason" in
    *greement*) wrong "Apple's notary service refused the sign-in: an agreement is waiting. Sign in at developer.apple.com/account and accept it." ;;
    *) wrong "Apple's notary service refused the sign-in. Check NOTARY_APPLE_ID, make a fresh app-specific password for NOTARY_PASSWORD, and check NOTARY_TEAM_ID is that account's team." ;;
  esac
fi

if [ $problems -gt 0 ]; then
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  exit 1
fi
if [ $IMPORT -eq 1 ]; then
  # codesign looks through the user's keychain list.
  security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
  result "SIGN_IDENTITY=$IDENTITY"
  result "PULSE_NOTARIZE=1"
  note "Signing is ready. This release will be signed, notarized and stapled, and will open with no warning."
else
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  note "Signing is ready. The next release will be signed, notarized and stapled, and will open with no warning."
fi
exit 0
