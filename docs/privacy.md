# Privacy & Usage Data

Quotapus sends no usage analytics, daily activity pings, or crash reports anywhere.
There is no analytics toggle. Diagnostic logs stay on this Mac unless you share them.

## Credentials stored on this Mac

Quotapus primarily reads credentials that provider tools already keep on your Mac. When it writes a
user-supplied API key or saves a refreshed credential, the file is replaced atomically and restricted to
your macOS account (owner read and write only). Antigravity's short-lived refreshed-token cache is tied
to the current Keychain login using a one-way fingerprint; the refresh credential itself is not copied.
The cache is never used after logout, an account change, or while Keychain access is unavailable.

Claude Desktop access is strictly read-only. Quotapus may ask macOS for permission to use the
`Claude Safe Storage` Keychain item so it can decrypt Desktop's current access token. It never uses
Desktop's rotating refresh token and never modifies Desktop's config, cookies, or Keychain data.

## Other network requests

Quotapus calls provider APIs to read usage and refresh supported credentials. It also fetches public [model price lists](pricing.md) from LiteLLM (`raw.githubusercontent.com`) and `models.dev` about once an hour. These public downloads carry no usage, log, or account information. The pricing supplement is bundled with the app. Spend from this Mac's CLI logs is calculated locally; those raw logs are not sent to a server.

If you add a [Remote Device](remote-devices.md), Quotapus sends a bundled parser over your existing SSH connection. That machine returns usage metadata (timestamps, model names, token counts, and deduplication IDs), not conversation text or raw log files. Quotapus keeps only a daily summary of that device on this Mac. The remote machine maintains its own private parsed-event cache; the imported summary stays on this Mac.

To avoid re-reading unchanged Claude, Codex, and pi logs after every relaunch, Quotapus keeps their
parsed usage events in `~/Library/Application Support/Quotapus/log-scan-cache/`. These records contain
the usage metadata needed for local totals, including any per-event cost already recorded by a provider,
but not raw JSONL lines or conversation text. They are private to your macOS account and are never sent
to an external service. Old source-file records are dropped as the scan window advances, and
identity caches that have not been used for 35 days are removed. Quotapus's pricing engine runs after
the cache is read, so its computed aggregates and totals are not persisted in this cache.

## Live activity

The Activity card's speed for this Mac comes from reading new lines added to Claude Code and Codex log files on this Mac — every 2 seconds while the panel is open and every 30 seconds otherwise, reading only lines added since the last check. Nothing from those logs is sent anywhere. Remote devices' speed comes from the history they already send at import.
