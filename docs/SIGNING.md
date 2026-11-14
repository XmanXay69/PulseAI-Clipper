# Signing and notarizing PULSE

Today a new user's first launch of PULSE meets a macOS warning, because the app is not signed with an
Apple Developer ID and not notarized by Apple. They have to go to System Settings → Privacy & Security →
Open Anyway. Signing and notarizing removes that: the app opens on a double-click like any other.

The release workflow can already do all of it. What it needs is an Apple Developer account and five
secrets that only the account's owner can create. This page is how to get them.

**Cost:** the Apple Developer Program is US$99 a year. There is no free way to notarize.

## What you do once

### 1. Join the Apple Developer Program

Go to [developer.apple.com/programs](https://developer.apple.com/programs/) and enrol with your Apple ID.
The Apple ID needs two-factor authentication on. Approval can take from minutes to a couple of days.

### 2. Create a Developer ID Application certificate

On your Mac:

1. Open **Keychain Access**. In the menu bar: **Keychain Access → Certificate Assistant → Request a
   Certificate From a Certificate Authority…**
2. Enter your email and name, choose **Saved to disk**, and save the file. Leave "CA Email" empty.
3. Go to [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates/list),
   press **+**, choose **Developer ID Application**, and upload the file you just saved.
4. Download the certificate (`developerID_application.cer`) and double-click it. It goes into your
   login keychain.

The kind matters. "Apple Development", "Apple Distribution" and "Mac App Distribution" certificates do not
work for an app downloaded from the web; it has to say **Developer ID Application**.

### 3. Export it as a .p12

1. In Keychain Access, pick the **login** keychain and the **My Certificates** tab.
2. Find **Developer ID Application: Your Name (ABCDE12345)**. It must have a private key under it (a
   small arrow opens it). If it is only under "Certificates" with no key, the request in step 2 was made
   on another Mac: export it from that one.
3. Right-click it → **Export…** → format **Personal Information Exchange (.p12)** → save it and choose a
   password. Remember the password: it is one of the five secrets.

The ten characters in brackets at the end of its name are your **Team ID**.

### 4. Make an app-specific password

Go to [account.apple.com](https://account.apple.com) → **Sign-In and Security → App-Specific Passwords**,
make one named "PULSE notarization" and copy it. It looks like `abcd-efgh-ijkl-mnop`. Your normal Apple ID
password does not work for notarization, and should never be put in a secret.

### 5. Add the five secrets to the repository

On GitHub: the repository → **Settings → Secrets and variables → Actions → New repository secret**. Add:

| Name | Value |
|---|---|
| `MACOS_CERT_P12` | The .p12 file as base64. In Terminal: `base64 -i ~/Desktop/DeveloperID.p12 \| pbcopy`, then paste. |
| `MACOS_CERT_PASSWORD` | The password you chose when exporting the .p12. |
| `NOTARY_APPLE_ID` | The Apple ID (email) of the developer account. |
| `NOTARY_PASSWORD` | The app-specific password from step 4. |
| `NOTARY_TEAM_ID` | The ten-character Team ID. |

GitHub stores them encrypted and never shows them again, not to you and not in logs. Do not paste any of
them into a chat, an issue or a commit. If one leaks, revoke it: the certificate at
developer.apple.com/account, the app-specific password at account.apple.com.

### 6. Check it

On GitHub: **Actions → Check signing setup → Run workflow**. It takes about a minute, builds nothing and
publishes nothing. It says in plain words whether:

- all five secrets are there (or which are missing),
- the .p12 opens with the password,
- it is a Developer ID Application certificate, in date, for the same team as the Team ID,
- Apple's notary service accepts the Apple ID, the password and the team.

When it is green, the next release is signed and notarized.

## What happens in a release once the secrets are there

1. **At the very start** the same check runs. A half-finished or wrong setup stops the release in its
   first minute, before the half-hour of building, and says what to fix.
2. The app is signed with the certificate, the hardened runtime and a secure timestamp.
3. The app is sent to Apple, and its ticket is stapled to it. It then opens with no warning after it is
   dragged out of the disk image, on a Mac that is offline too.
4. The disk image is signed, sent to Apple, and stapled as well.
5. Gatekeeper is asked, on the build machine, whether it would open the disk image and the app. If it
   says no, the release stops. A build is never published as notarized on trust.
6. The release notes drop the "First launch only" steps, since they no longer apply. The README's own
   first-launch paragraph should be removed by hand in that release.

If Apple refuses the app, the reasons Apple gives are printed in the log of that step.

With no secrets at all, everything works as it does today: ad-hoc signed, one question on first launch.

## Keeping it working

- The certificate lasts five years. The check warns in its last thirty days. Renewing means steps 2, 3
  and the first two secrets again.
- Apple sometimes asks account holders to accept an updated agreement; until that is done notarization
  is refused. The check says so when that is the reason.
- An app-specific password stops working when the Apple ID's password is changed. Make a new one.

## What has and has not been tried

The checks on the shape of the five values run anywhere and have been tried. Everything that needs the
certificate or Apple's service (opening the .p12, the notary sign-in, notarizing, stapling, the Gatekeeper
checks) has been written from Apple's documented tools and has **not run with real credentials**: there
are none in this repository yet. Expect the first signed release to need a look at its log.
