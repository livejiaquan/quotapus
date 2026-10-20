<p align="center"><img src="assets/QuotapusIcon/icon-1024.png" width="128" alt="Quotapus icon"></p>

# Quotapus

Track your AI coding subscriptions from the macOS menu bar — including the usage on your other computers.

> **Quotapus is an unofficial fork of [OpenUsage](https://github.com/robinebers/openusage) by Robin Ebers.**
> It is not the official OpenUsage app and is not endorsed by its maintainers. Report problems with
> Quotapus [here](https://github.com/livejiaquan/quotapus/issues), not to the OpenUsage project.

Quotapus shows how much of your AI coding plans you've used: session and weekly limits, credits, and spend, all in one popover. Pin your most important metrics straight into the menu bar.

## What Quotapus Adds

- **Live cards.** Activity (live tokens/min, with an estimated cost per hour), Tokens, Spend, and Models — one line each, opened with a click, each with its own Today / Yesterday / 30 Days view.
- **[Remote Devices](docs/remote-devices.md).** Pull Claude Code and Codex history from your Linux servers, other Macs, Windows PCs, and WSL over the SSH keys you already use. If you use Tailscale, Add Device lists your tailnet machines so one click fills the form. The dashboard's **Usage From** menu switches between all devices, this Mac, and each machine. Only daily summaries are stored on this Mac; prompts and replies never leave the remote machine.
- **[Extra local log folders](docs/local-log-roots.md).** Include copied session archives in this Mac's history.

Quotapus started from OpenUsage's code and has since gone its own way in design and features.

## How It Differs From OpenUsage

- **Different app, side by side.** Quotapus has its own bundle ID (`com.livejiaquan.quotapus`), settings, logs (`~/Library/Logs/Quotapus`), config folder (`~/.quotapus`, `~/.config/quotapus`), and local API port (`6741`), so it can be installed next to the official app without either touching the other.
- **No analytics.** Quotapus contains no analytics or crash-reporting code, so it sends no usage statistics anywhere.
- **No iCloud Sync, no command-line helper, no share images.** Remote Devices covers other machines over SSH; the rest was removed to keep the app small.
- **Pricing stays local.** Model prices come from LiteLLM, models.dev, and a price list bundled with the app — nothing is fetched from OpenUsage.
- **Updates come from this repository**, not from OpenUsage's update feed.

## Installation

1. Download the latest `Quotapus-<version>.dmg` from [Releases](https://github.com/livejiaquan/quotapus/releases/latest) and drag **Quotapus** into **Applications**.
2. Open it once. Quotapus is signed with its own certificate rather than an Apple Developer ID, so macOS says it can't verify the developer. Open **System Settings → Privacy & Security**, scroll to the message about Quotapus, and click **Open Anyway**. This is needed only the first time.
3. After that, Quotapus checks this repository for new versions about once an hour and offers to install them (see [Updates](docs/updates.md)).

Requires macOS 15 (Sequoia) or later. You can also build it yourself (see [Building](#building)).

## Supported Providers

- **[Antigravity](docs/providers/antigravity.md)** — shared Gemini and Claude pool quotas, 5-hour and weekly windows
- **[Claude](docs/providers/claude.md)** — session, weekly, model-specific limits, extra usage, local daily spend
- **[Codex](docs/providers/codex.md)** — session, weekly, credits, local daily spend
- **[Copilot](docs/providers/copilot.md)** — AI credits, extra usage, organization billing, chat and completions
- **[Cursor](docs/providers/cursor.md)** — credits, total usage, Grok Bot, Cursor Models, Other Models, requests, on-demand, per-day spend
- **[Devin](docs/providers/devin.md)** — weekly and daily quota, extra usage balance
- **[Grok](docs/providers/grok.md)** — weekly shared pool, pay-as-you-go, local daily spend
- **[Ollama](docs/providers/ollama.md)** — Ollama Cloud monthly credits (or session and weekly limits on legacy plans), purchased credits
- **[OpenCode](docs/providers/opencode.md)** — Go session/weekly/monthly caps, Zen spend, local daily spend
- **[OpenRouter](docs/providers/openrouter.md)** — credit balance, daily/weekly/monthly spend (API key)
- **[Z.ai](docs/providers/zai.md)** — session, weekly, web-search quotas (GLM Coding Plan, API key)

Most providers read the credentials already on your machine (keychain, auth files, app state) — no extra login. OpenRouter and Z.ai are the exceptions: they have no local credential to reuse, so you supply an API key (see [OpenRouter setup](docs/providers/openrouter.md) or [Z.ai setup](docs/providers/zai.md)). Credentials are used only for the corresponding provider requests. See [Privacy & usage data](docs/privacy.md).

## Features

- **Menu bar pins.** Pin metrics to the menu bar (up to 2 per provider); render as compact text or mini bars. The strip hides metrics with no data instead of showing placeholders.
- **Dashboard popover.** Provider-grouped meters with live reset countdowns and pace indicators. Click usage or reset values to flip their display everywhere; right-click a row to hide or star it, refresh its provider, or open Customize.
- **Global shortcut.** Toggle the popover from anywhere — record any combo in Settings.
- **Customize.** Turn providers and metrics on or off, choose which rows stay Always Visible or On Demand, and drag-reorder both.
- **Stale-while-revalidate.** Cached values display instantly at launch; refresh runs every 5 minutes.
- **[Local HTTP API](docs/local-http-api.md).** Other apps can read machine-friendly limits from `127.0.0.1:6741/v1/limits`. It is loopback-only and never serves credentials; note that browser pages can read it too — see the [privacy note](docs/local-http-api.md#cors-and-privacy).
- **[Proxy support](docs/proxy.md).** Route provider requests through SOCKS5 or HTTP(S) via `~/.quotapus/config.json`.
- **Native settings.** Launch at login, global shortcut, icon style, theme, density — see [Settings](docs/settings.md).

## Documentation

Behavior docs live in [docs/](docs/README.md). Developer docs: [architecture](docs/architecture.md), [adding a provider](docs/adding-a-provider.md), and [debugging & capturing logs](docs/debugging.md).

## Building

```sh
swift build                 # debug build
swift test                  # run the test suite
./script/build_and_run.sh   # build and launch dist/Quotapus.app (no install)
```

Internal module and type names keep OpenUsage's spelling on purpose, so changes from upstream merge cleanly. Everything a user sees reads from `Sources/OpenUsage/Support/AppBrand.swift`. The app icon lives in `assets/QuotapusIcon` (see its README).

## Releasing

Pushing a `v*` tag runs [.github/workflows/release.yml](.github/workflows/release.yml), which builds a universal app, signs it, publishes `Quotapus-<version>.dmg` on GitHub Releases, and updates the Sparkle appcast on this repository's GitHub Pages (`https://livejiaquan.github.io/quotapus/appcast.xml`). A tag with a suffix such as `v1.1.0-beta.1` goes to the Beta Updates channel; a plain tag goes to everyone. Run the workflow by hand with **dry_run** to build and sign a DMG as a run artifact without publishing anything.

It needs these repository secrets (Settings → Secrets and variables → Actions):

| Secret                           | What it is                                                                 |
| -------------------------------- | -------------------------------------------------------------------------- |
| `CODESIGN_CERTIFICATE`           | base64 of the "Quotapus Code Signing" `.p12` (or a Developer ID `.p12`)    |
| `CODESIGN_CERTIFICATE_PASSWORD`  | the password of that `.p12`                                                |
| `SPARKLE_PUBLIC_KEY`             | base64 Ed25519 public key, baked into the build as `SUPublicEDKey`         |
| `SPARKLE_PRIVATE_KEY`            | base64 Ed25519 private key (32-byte seed) that signs each DMG for Sparkle  |
| `APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID` | optional; only with a Developer ID certificate, for notarization |

Releases are signed with Quotapus's own self-signed certificate, the same for every release, so users' Keychain approvals survive updates; the first launch needs one **Open Anyway** (see Installation). **Never lose or regenerate the certificate or the Sparkle private key**: installed copies only accept updates signed by the same Sparkle key, and a new certificate would make every user re-approve Keychain access. Keep offline backups of both. GitHub Pages must use **GitHub Actions** as its source, and [.github/workflows/deploy-pages.yml](.github/workflows/deploy-pages.yml) must be on `main`.

## Credits, License, and Trademark

Quotapus is built on [OpenUsage](https://github.com/robinebers/openusage), created by Robin Ebers and maintained with Mert and David. The code is under the [MIT license](LICENSE), which keeps the original copyright notice.

"OpenUsage" and its logo are trademarks of Robin Ebers (see [TRADEMARK.md](TRADEMARK.md)). Per that policy, this fork uses its own name and icon and doesn't claim to be the official project.
