# Updates

Quotapus keeps itself up to date using [Sparkle](https://sparkle-project.org), the standard update
framework for Mac apps. Updates are downloaded from Quotapus's own release feed and verified before
they install, so you always get a genuine, unmodified build.

## How it works

- **Automatic checks.** The app quietly checks for a new version in the background (about once an hour).
  When one is found, an **Update Available** banner appears at the top of the popover instead of a
  window popping up behind your other apps. Click **Install Update** to open the update window (release
  notes, download, install) front and center. The banner's close button snoozes it; it comes back the
  next time the app finds the update.
- **Manual check.** Open **Settings → Updates** and click **Check for Updates…** at any time.
  For both manual checks and banner installs, Quotapus brings itself to the foreground before opening
  Sparkle so the update window doesn't get buried behind another app. Because Quotapus normally lives
  only in the menu bar, it briefly shows a Dock icon for the update session, then hides again.
- **Turn it off.** The **Check Automatically** switch in **Settings → Updates** stops the
  background checks. You can still check manually.

## Beta updates

**Settings → Updates → Beta Updates** opts you into pre-release builds before they ship to
everyone. Turn it off to go back to stable-only; you'll stay on your current version until the next
stable release catches up.

Everyone always receives stable releases — the beta option only *adds* pre-release builds on top.

## Where updates come from

Update builds are published on Quotapus's GitHub releases, and the list of available versions (the
"appcast") is served from `https://livejiaquan.github.io/quotapus/appcast.xml`. Every update is signed
with Quotapus's own update key (EdDSA), and the app refuses any download that doesn't match it. The app
itself is signed with Quotapus's own code-signing certificate, the same one for every release. It isn't
an Apple Developer ID, so the very first launch needs one approval in System Settings (see the README's
Installation); updates after that install from inside the app. If you use Claude Desktop, macOS asks
again after each update before Quotapus can read **Claude Safe Storage** (see
[Claude](providers/claude.md)): macOS ties that approval to each exact build of an app without an Apple
Developer ID. Claude Code's own login is not affected. Local developer builds have no update feed and never check.
