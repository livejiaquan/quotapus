# Releasing

For maintainers: how a release is built, signed, and published.

Pushing a `v*` tag runs [.github/workflows/release.yml](../.github/workflows/release.yml), which builds a universal app, signs it, publishes `Quotapus-<version>.dmg` on GitHub Releases, and updates the Sparkle appcast on this repository's GitHub Pages (`https://livejiaquan.github.io/quotapus/appcast.xml`). A tag with a suffix such as `v1.1.0-beta.1` goes to the Beta Updates channel; a plain tag goes to everyone. Run the workflow by hand with **dry_run** to build and sign a DMG as a run artifact without publishing anything.

It needs these repository secrets (Settings → Secrets and variables → Actions):

| Secret                           | What it is                                                                 |
| -------------------------------- | -------------------------------------------------------------------------- |
| `CODESIGN_CERTIFICATE`           | base64 of the "Quotapus Code Signing" `.p12` (or a Developer ID `.p12`)    |
| `CODESIGN_CERTIFICATE_PASSWORD`  | the password of that `.p12`                                                |
| `SPARKLE_PUBLIC_KEY`             | base64 Ed25519 public key, baked into the build as `SUPublicEDKey`         |
| `SPARKLE_PRIVATE_KEY`            | base64 Ed25519 private key (32-byte seed) that signs each DMG for Sparkle  |
| `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID` | optional; only with a Developer ID certificate, for notarization |

Releases are signed with Quotapus's own self-signed certificate, the same for every release; the first launch needs one **Open Anyway** (see [Install](../README.md#install)), and Claude Desktop users approve **Claude Safe Storage** again after each update (macOS ties that approval to each build of an app without a Developer ID). A Developer ID certificate plus the `APPLE_*` secrets removes both. **Never lose or regenerate the certificate or the Sparkle private key**: installed copies only accept updates signed by the same Sparkle key, and a new certificate would change the app's identity for every user. Keep offline backups of both. GitHub Pages must use **GitHub Actions** as its source, and [.github/workflows/deploy-pages.yml](../.github/workflows/deploy-pages.yml) must be on `main`.
