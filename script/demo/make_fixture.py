#!/usr/bin/env python3
"""Writes demo mode's sample data (see Sources/OpenUsage/Support/DemoMode.swift).

Every number, device, and host here is made up. Dates are relative to now, so regenerate right
before each recording: python3 script/demo/make_fixture.py /tmp/quotapus-demo.json
"""
import json
import math
import random
import sys
from datetime import datetime, timedelta, timezone

NOW = datetime.now(timezone.utc).replace(microsecond=0)
TODAY = datetime.now().date()  # history days are local calendar days, like the app's
DAYS = 30


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def progress(label, used, resets_in, period_hours):
    return {
        "type": "progress", "label": label, "used": used, "limit": 100,
        "format": {"kind": "percent"}, "resetsAt": iso(NOW + resets_in),
        "periodDurationMs": period_hours * 3600 * 1000,
    }


def resets_available(count, expires_in):
    return {
        "type": "values", "label": "Rate Limit Resets",
        "values": [{"number": count, "kind": "count", "label": "available", "estimated": False}],
        "expiriesAt": [iso(NOW + expires_in)],
    }


def history(seed, models, daily_tokens, active=0.9):
    """30 days of usage. `models`: (name, share of tokens, USD per million tokens)."""
    rng = random.Random(seed)
    daily, by_model = [], []
    for back in range(DAYS):
        day = TODAY - timedelta(days=back)
        weekday_dip = 0.55 if day.weekday() >= 5 else 1.0
        if back > 0 and rng.random() > active:
            continue
        # Today is still in progress, so it reads lower than a full day.
        part_of_day = 0.62 if back == 0 else 1.0
        wave = 1 + 0.35 * math.sin(back / 3.1 + seed)
        total = int(daily_tokens * weekday_dip * wave * rng.uniform(0.7, 1.3) * part_of_day)
        models_today, cost = [], 0.0
        for name, share, per_million in models:
            tokens = int(total * share * rng.uniform(0.8, 1.2))
            usd = round(tokens / 1e6 * per_million, 2)
            if tokens:
                models_today.append({"model": name, "totalTokens": tokens, "costUSD": usd})
                cost += usd
        tokens_sum = sum(m["totalTokens"] for m in models_today)
        daily.append({"date": day.isoformat(), "totalTokens": tokens_sum, "costUSD": round(cost, 6)})
        by_model.append({"date": day.isoformat(), "models": models_today})
    return {"series": {"daily": daily}, "modelUsage": {"daily": by_model}, "unknownModelsByDay": {}}


CLAUDE_MODELS = [("claude-opus-5-5", 0.86, 0.32), ("claude-fable-5-1", 0.11, 1.13), ("claude-sonnet-5-5", 0.03, 1.2)]
CODEX_MODELS = [("gpt-6-astra", 0.25, 1.88), ("gpt-6.1-sol", 0.6, 0.25), ("gpt-6-sol", 0.15, 0.27)]
ANTIGRAVITY_MODELS = [("gemini-3.1-pro", 0.5, 0.44), ("gemini-3.8-flash", 0.3, 0.2), ("claude-opus-4-6", 0.2, 1.06)]

snapshots = [
    {
        "providerID": "claude", "displayName": "Claude", "plan": "Max 5x", "refreshedAt": iso(NOW),
        "lines": [
            progress("Session", 62, timedelta(hours=1, minutes=48), 5),
            progress("Weekly", 41, timedelta(days=3, hours=4), 168),
            progress("Fable", 27, timedelta(days=3, hours=4), 168),
            {"type": "progress", "label": "Extra usage spent", "used": 12.4, "limit": 50,
             "format": {"kind": "dollars"}},
            resets_available(1, timedelta(days=2, hours=6)),
        ],
        "usageHistory": history(1, CLAUDE_MODELS, 260e6),
    },
    {
        "providerID": "codex", "displayName": "Codex", "plan": "Pro", "refreshedAt": iso(NOW),
        "lines": [
            progress("Weekly", 36, timedelta(days=4, hours=11), 168),
            resets_available(1, timedelta(days=12)),
        ],
        "usageHistory": history(2, CODEX_MODELS, 70e6, active=0.8),
    },
    {
        "providerID": "antigravity", "displayName": "Antigravity", "plan": "Pro", "refreshedAt": iso(NOW),
        "lines": [
            progress("Session", 18, timedelta(hours=3, minutes=12), 5),
            progress("Weekly", 9, timedelta(days=5, hours=2), 168),
            progress("Claude", 4, timedelta(hours=3, minutes=12), 5),
            progress("Claude Weekly", 2, timedelta(days=5, hours=2), 168),
        ],
        "usageHistory": history(3, ANTIGRAVITY_MODELS, 9e6, active=0.45),
    },
]

devices = [
    {"id": "ssh-demo-devbox", "name": "devbox (WSL)", "host": "devbox", "platform": "Windows WSL", "enabled": True},
    {"id": "ssh-demo-gpu", "name": "gpu-server", "host": "gpu-server", "platform": "Linux", "enabled": True},
    {"id": "ssh-demo-air", "name": "MacBook Air", "host": "macbook-air", "platform": "Mac", "enabled": True},
]


def document(device, providers):
    return {
        "schema": "openusage.history.v1", "deviceID": device["id"], "deviceName": device["name"],
        "updatedAt": iso(NOW), "providers": providers,
    }


documents = [
    document(devices[0], {"claude": history(11, CLAUDE_MODELS, 140e6), "codex": history(12, CODEX_MODELS, 30e6, 0.6)}),
    document(devices[1], {"codex": history(21, CODEX_MODELS, 120e6, 0.85), "claude": history(22, CLAUDE_MODELS, 40e6, 0.5)}),
    document(devices[2], {"claude": history(31, CLAUDE_MODELS, 25e6, 0.5)}),
]

fixture = {
    "snapshots": snapshots,
    "devices": devices,
    "documents": documents,
    "liveRates": {"claude": 640_000, "codex": 120_000},
    "deviceLiveRates": {
        "ssh-demo-devbox": {"claude": 410_000, "codex": 60_000},
        "ssh-demo-gpu": {"codex": 280_000},
        "ssh-demo-air": {"claude": 95_000},
    },
}

out = sys.argv[1] if len(sys.argv) > 1 else "quotapus-demo.json"
with open(out, "w") as f:
    json.dump(fixture, f, indent=1)
print(f"wrote {out}")
