#!/usr/bin/env bash
set -euo pipefail

# Builds the dev app under its own bundle id and launches it in demo mode on fresh sample data, for
# README recordings and screenshots. It never reads this Mac's accounts, logs, or SSH devices, and its
# settings live apart from the released app's (com.livejiaquan.quotapus.demo), reset on every run.
# Note: build_and_run.sh quits any running Quotapus first, including the installed one.
#
# usage: script/demo/run_demo.sh            # build, then launch
#        SCRIPT=rec.json script/demo/run_demo.sh  # ...and play a recording script
#        SKIP_BUILD=1 script/demo/run_demo.sh  # relaunch the last demo build with fresh dates
#        APPEARANCE=light script/demo/run_demo.sh  # record in the light theme

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEMO_BUNDLE_ID="com.livejiaquan.quotapus.demo"
FIXTURE="${FIXTURE:-${TMPDIR:-/tmp}/quotapus-demo.json}"

# The footer shows the latest released version, read from the changelog's first heading.
RELEASED_VERSION="$(sed -n 's/^## v\([0-9][0-9.]*\)$/\1/p' "$ROOT_DIR/CHANGELOG.md" | head -1)"

if [ -z "${SKIP_BUILD:-}" ]; then
  BUNDLE_ID="$DEMO_BUNDLE_ID" APP_VERSION="$RELEASED_VERSION" VERSION_SUFFIX="" \
    "$ROOT_DIR/script/build_and_run.sh" build
else
  pkill -x Quotapus >/dev/null 2>&1 || true
fi
python3 "$ROOT_DIR/script/demo/make_fixture.py" "$FIXTURE"
defaults delete "$DEMO_BUNDLE_ID" >/dev/null 2>&1 || true
# APPEARANCE=light|dark records a fixed theme instead of following the system.
if [ -n "${APPEARANCE:-}" ]; then defaults write "$DEMO_BUNDLE_ID" appearance -string "$APPEARANCE"; fi
ENV_ARGS=(--env "QUOTAPUS_DEMO_FIXTURE=$FIXTURE")
# SCRIPT=path/to/script.json plays a hands-free recording script (see DemoDirector.swift).
if [ -n "${SCRIPT:-}" ]; then ENV_ARGS+=(--env "QUOTAPUS_DEMO_SCRIPT=$SCRIPT"); fi
/usr/bin/open -n "${ENV_ARGS[@]}" "$ROOT_DIR/dist/Quotapus.app"
echo "==> demo running on $FIXTURE"
