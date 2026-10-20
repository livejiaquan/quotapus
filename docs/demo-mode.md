# Demo Mode

Demo mode runs the real app on sample data, for README recordings and screenshots. Every number, device, and host in it is made up, and it never reads this Mac's accounts, logs, Keychain, or SSH devices.

## Running It

```sh
script/demo/run_demo.sh
```

This builds the dev app under its own bundle id (`com.livejiaquan.quotapus.demo`), writes fresh sample data, and launches it. The demo's settings are kept apart from the released app's and reset on every run. The footer shows the latest released version from the changelog. Building quits any running Quotapus, including the installed one; reopen it afterwards.

`SKIP_BUILD=1` relaunches the last demo build with fresh dates. Sample data is dated relative to now, so relaunch before each recording.

## What It Shows

- **Providers:** Claude, Codex, and Antigravity, with limits, pace notes, and 30 days of history. The Today / Yesterday / 30 Days rows and charts are drawn from that history the same way real ones are.
- **Remote Devices:** three sample machines (a WSL box, a Linux server, and a MacBook Air). Instead of connecting over SSH, each import returns its sample history.
- **Live speed:** a token rate that drifts around a fixed level on this Mac and on each machine.

Change the numbers in `script/demo/make_fixture.py`.

## Hands-Free Recording

Set `SCRIPT=path/to/script.json` to play a timed script against the panel. Nobody has to touch the mouse, and the panel never takes the keyboard from the app in use. Clicks go straight to the panel; the system pointer doesn't move.

```json
{"screen": "Built-in", "anchorInset": 645, "statusImagePath": "/tmp/strip.png", "logPath": "/tmp/demo-log.json",
 "steps": [
  {"at": 4.0, "action": "open"},
  {"at": 7.0, "action": "click", "x": 265, "y": 161},
  {"at": 9.5, "action": "menu", "x": 256, "y": 26, "item": "devbox (WSL)"},
  {"at": 31.0, "action": "close"}
 ]}
```

- `screen` and `anchorInset`: the panel opens under the menu bar of the display whose name contains `screen`, `anchorInset` points from its right edge.
- `click` and `menu`: `x`, `y` are points from the panel's top-left. `menu` opens a menu there and then picks the item with that title.
- While a script runs, clicking elsewhere doesn't close the panel.
- `statusImagePath` saves the menu-bar strip image when the panel opens. `logPath` records when each step ran and where, in screen coordinates.
