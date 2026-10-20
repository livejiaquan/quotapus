# Contributing to Quotapus

Thanks for your interest. Quotapus is a small, focused app: it tracks AI coding subscription usage on this Mac and your other computers, and nothing more.

## Issues

- **Bugs:** open a [bug report](https://github.com/livejiaquan/quotapus/issues/new?template=bug_report.yml) with steps to reproduce, your macOS version, and the relevant lines from `~/Library/Logs/Quotapus/Quotapus.log`.
- **Features and new providers:** open a [feature request](https://github.com/livejiaquan/quotapus/issues/new?template=feature_request.yml) or a [provider request](https://github.com/livejiaquan/quotapus/issues/new?template=new_provider.yml) first, so we can agree on the change before you build it.

## Pull Requests

1. Open or comment on an issue describing the change
2. Fork the repo and create a branch (`feat/my-change`, `fix/some-bug`)
3. Make one focused change, with a regression test when fixing a bug
4. Run `swift build` and `swift test`
5. Update the matching page in `docs/` when user-visible behavior changes
6. Open a PR against `main`; include before/after screenshots for any visual change

By submitting a pull request, you agree that your contribution is licensed under the [MIT License](LICENSE). The Quotapus name and logo are not part of that license (see [TRADEMARK.md](TRADEMARK.md)).

## Adding a Provider

Each provider is a small Swift module under `Sources/OpenUsage/Providers/<Name>/` (the internal module keeps OpenUsage's name so upstream changes merge cleanly): an auth store reads credentials already on the user's machine, a usage client calls the provider's API, and a mapper turns the response into metric lines. See [docs/adding-a-provider.md](docs/adding-a-provider.md) and [docs/architecture.md](docs/architecture.md).

## Code Standards

- Swift 6 with strict concurrency, built with SwiftPM (no Xcode project)
- Follow the existing patterns and design language
- No new dependencies without a clear reason
- Keep files under about 500 lines

## Upstream

Quotapus is built on [OpenUsage](https://github.com/robinebers/openusage) by Robin Ebers. Changes that apply to OpenUsage itself are best contributed there too.
