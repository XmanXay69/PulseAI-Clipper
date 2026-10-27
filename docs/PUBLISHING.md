# Publishing to YouTube from PULSE

Roadmap #482. An export can go straight to your channel — private, unlisted, public or scheduled — from the
export queue's **YouTube…** button. PULSE talks to YouTube's own Data API with an OAuth client you own, so no
third party sits in between and nothing is uploaded until you press Upload.

## One-time setup (about five minutes)
1. Open <https://console.cloud.google.com/>, make a project (any name).
2. **APIs & Services → Library**: enable **YouTube Data API v3**.
3. **APIs & Services → OAuth consent screen**: External, add your Google account as a test user (a personal
   client stays in "testing", which is fine for your own channel).
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**, type **Desktop app**. Copy the
   client id (and the secret if one is shown).
5. In PULSE: **Settings → Publishing**, paste the client id (and secret), press **Sign in with Google**, finish
   in the browser. Tokens are kept in the macOS Keychain; PULSE asks only for the `youtube.upload` scope.

## Publishing
- Deliver → export queue → a finished job → **YouTube…**. The title, description (the share-ready copy) and
  tags come from the edit; pick the visibility, or tick **Go live at** for a schedule (YouTube keeps a
  scheduled video private until then).
- The upload runs as a job with progress; the link lands in a toast, the activity log and the clipboard.
- Quota: Google gives a project 10,000 units a day; an upload costs about 1,600, so six or so a day.

## TikTok
TikTok's Content Posting API only works for apps TikTok has reviewed, so PULSE doesn't upload there. The
share-ready copy (title, caption, hashtags) and the exported file are one drag away from TikTok's upload page.
