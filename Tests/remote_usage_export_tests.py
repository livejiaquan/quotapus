import contextlib
import datetime as dt
import importlib.util
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "Sources/OpenUsage/Resources/remote_usage_export.py"
SPEC = importlib.util.spec_from_file_location("remote_usage_export", SCRIPT)
exporter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(exporter)


class RemoteUsageExportTests(unittest.TestCase):
    def test_child_replay_and_claude_usage_export_without_conversation(self):
        with tempfile.TemporaryDirectory() as temporary:
            old_home = os.environ.get("HOME")
            old_codex = os.environ.pop("CODEX_HOME", None)
            old_claude = os.environ.pop("CLAUDE_CONFIG_DIR", None)
            os.environ["HOME"] = temporary
            try:
                home = pathlib.Path(temporary)
                codex = home / ".codex/sessions/2026/10/04/rollout.jsonl"
                claude = home / ".claude/projects/example/session.jsonl"
                codex.parent.mkdir(parents=True)
                claude.parent.mkdir(parents=True)
                now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
                when = now.isoformat().replace("+00:00", "Z")
                started = int(now.timestamp())
                lines = [
                    {"timestamp": when, "type": "session_meta", "payload": {"parent_thread_id": "parent"}},
                    {"timestamp": when, "type": "turn_context", "payload": {"model": "gpt-5.2"}},
                    {"timestamp": when, "type": "event_msg", "payload": {"type": "token_count", "info": {
                        "total_token_usage": {"input_tokens": 100, "output_tokens": 20},
                        "last_token_usage": {"input_tokens": 100, "output_tokens": 20}}}},
                    {"timestamp": when, "type": "event_msg", "payload": {"type": "task_started", "started_at": started}},
                    {"timestamp": when, "type": "event_msg", "payload": {"type": "token_count", "info": {
                        "total_token_usage": {"input_tokens": 130, "output_tokens": 25},
                        "last_token_usage": {"input_tokens": 30, "output_tokens": 5}}}},
                ]
                codex.write_text("\n".join(json.dumps(item) for item in lines) + "\n")
                archived = home / ".codex/archived_sessions/2026/10/04/rollout.jsonl"
                archived.parent.mkdir(parents=True)
                archived.write_text(json.dumps({
                    "timestamp": when, "type": "event_msg", "payload": {"type": "token_count", "info": {
                        "last_token_usage": {"input_tokens": 999, "output_tokens": 999}}}
                }) + "\n")
                claude.write_text(json.dumps({
                    "timestamp": when, "sessionId": "session", "requestId": "request",
                    "version": "2.1.0", "prompt": "SECRET_CONVERSATION_TEXT",
                    "message": {"id": "message", "model": "claude-sonnet-4-5", "usage": {
                        "input_tokens": 10, "output_tokens": 3,
                        "cache_creation_input_tokens": 2, "cache_read_input_tokens": 4}}
                }) + "\n")

                first = self.run_export()
                second = self.run_export()  # Exercises the incremental parsed-event cache.
                self.assertEqual(first, second)
                self.assertEqual(len(first["codex"]), 1)
                self.assertEqual(first["codex"][0]["total"], 35)
                self.assertEqual(len(first["claude"]), 1)
                self.assertEqual(first["claude"][0]["tokens"]["cacheRead"], 4)
                self.assertNotIn("SECRET_CONVERSATION_TEXT", json.dumps(first))
                self.assertNotIn("SECRET_CONVERSATION_TEXT", (home / ".cache/quotapus-remote/events-v1.json").read_text())
            finally:
                if old_home is None:
                    os.environ.pop("HOME", None)
                else:
                    os.environ["HOME"] = old_home
                if old_codex is not None:
                    os.environ["CODEX_HOME"] = old_codex
                if old_claude is not None:
                    os.environ["CLAUDE_CONFIG_DIR"] = old_claude

    def test_untouched_old_logs_are_not_parsed_and_unchanged_cache_is_not_rewritten(self):
        with tempfile.TemporaryDirectory() as temporary:
            old_home = os.environ.get("HOME")
            old_codex = os.environ.pop("CODEX_HOME", None)
            old_claude = os.environ.pop("CLAUDE_CONFIG_DIR", None)
            os.environ["HOME"] = temporary
            original_parse = exporter.parse_codex
            parsed = []
            exporter.parse_codex = lambda path: parsed.append(path.name) or original_parse(path)
            try:
                home = pathlib.Path(temporary)
                sessions = home / ".codex/sessions/2026/08/01"
                sessions.mkdir(parents=True)
                stale = sessions / "stale.jsonl"
                stale.write_text(json.dumps({"timestamp": "2026-08-01T00:00:00Z", "type": "event_msg", "payload": {
                    "type": "token_count", "info": {"last_token_usage": {"input_tokens": 5, "output_tokens": 5}}}}) + "\n")
                forty_days_ago = dt.datetime.now().timestamp() - 40 * 86400
                os.utime(stale, (forty_days_ago, forty_days_ago))

                first = self.run_export()
                cache = home / ".cache/quotapus-remote/events-v1.json"
                written = cache.stat().st_mtime_ns
                second = self.run_export()
                self.assertEqual(first, second)
                self.assertEqual(first["codex"], [])
                self.assertEqual(parsed, [], "a log untouched since before the window can't hold events in it")
                self.assertEqual(cache.stat().st_mtime_ns, written, "an unchanged cache is not rewritten")
            finally:
                exporter.parse_codex = original_parse
                if old_home is None:
                    os.environ.pop("HOME", None)
                else:
                    os.environ["HOME"] = old_home
                if old_codex is not None:
                    os.environ["CODEX_HOME"] = old_codex
                if old_claude is not None:
                    os.environ["CLAUDE_CONFIG_DIR"] = old_claude

    def test_timestamps_parse_without_fromisoformat_limits(self):
        expected = dt.datetime(2026, 10, 20, 1, 12, 37, 549000, tzinfo=dt.timezone.utc).timestamp()
        self.assertEqual(exporter.stamp("2026-10-20T01:12:37.549Z"), expected)
        self.assertEqual(exporter.stamp("2026-10-20T09:12:37.549+08:00"), expected)
        self.assertEqual(exporter.stamp("2026-10-19T20:12:37.549-0500"), expected)
        # Older Pythons' fromisoformat rejects fractions other than 3 or 6 digits; these must still count.
        self.assertEqual(exporter.stamp("2026-10-20T01:12:37.549000123Z"), expected)
        self.assertAlmostEqual(exporter.stamp("2026-10-20T01:12:37.5Z"), expected - 0.049, places=6)
        self.assertAlmostEqual(exporter.stamp("2026-10-20T01:12:37Z"), expected - 0.549, places=6)
        self.assertIsNone(exporter.stamp("not a date"))
        self.assertIsNone(exporter.stamp("2026-13-40T01:12:37Z"))
        self.assertIsNone(exporter.stamp(None))

    def test_missing_total_does_not_count_reasoning_twice(self):
        # Codex's output_tokens already includes reasoning_output_tokens.
        usage = exporter.codex_usage({"input_tokens": 100, "output_tokens": 30, "reasoning_output_tokens": 20})
        self.assertEqual(usage["total"], 130)
        reported = exporter.codex_usage({"input_tokens": 100, "output_tokens": 30, "total_tokens": 135})
        self.assertEqual(reported["total"], 135)

    def test_session_moved_during_scan_is_skipped_instead_of_failing_the_device(self):
        with tempfile.TemporaryDirectory() as temporary:
            old_home = os.environ.get("HOME")
            old_codex = os.environ.pop("CODEX_HOME", None)
            old_claude = os.environ.pop("CLAUDE_CONFIG_DIR", None)
            original_discover = exporter.discover
            os.environ["HOME"] = temporary
            try:
                home = pathlib.Path(temporary)
                claude = home / ".claude/projects/example/session.jsonl"
                claude.parent.mkdir(parents=True)
                when = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
                claude.write_text(json.dumps({
                    "timestamp": when, "sessionId": "session", "requestId": "request", "version": "2.1.0",
                    "message": {"id": "message", "model": "claude-sonnet-4-5",
                                "usage": {"input_tokens": 10, "output_tokens": 3}}
                }) + "\n")
                vanished = home / ".codex/sessions/2026/10/04/moved-to-archive.jsonl"

                def discover_with_vanished_file(provider):
                    found = original_discover(provider)
                    return found + [vanished] if provider == "codex" else found

                exporter.discover = discover_with_vanished_file
                result = self.run_export()
                self.assertEqual(result["codex"], [])
                self.assertEqual(len(result["claude"]), 1)
            finally:
                exporter.discover = original_discover
                if old_home is None:
                    os.environ.pop("HOME", None)
                else:
                    os.environ["HOME"] = old_home
                if old_codex is not None:
                    os.environ["CODEX_HOME"] = old_codex
                if old_claude is not None:
                    os.environ["CLAUDE_CONFIG_DIR"] = old_claude

    def test_probe_reports_which_log_folders_hold_logs(self):
        # Run exactly as the connection check does: the script on stdin with the probe flag prepended.
        with tempfile.TemporaryDirectory() as temporary:
            home = pathlib.Path(temporary)
            env = {key: value for key, value in os.environ.items()
                   if key not in ("CODEX_HOME", "CLAUDE_CONFIG_DIR", "XDG_CONFIG_HOME")}
            env["HOME"] = temporary
            script = b"QUOTAPUS_PROBE = True\n" + SCRIPT.read_bytes()

            def probe():
                done = subprocess.run([sys.executable, "-"], input=script, env=env,
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
                return done.stdout.decode().strip().split(" | ")

            platform, _, reported_home, logs = probe()
            self.assertEqual(platform, sys.platform)
            self.assertEqual(reported_home, str(home))
            self.assertEqual(logs, "codex=0 claude=0")
            self.assertFalse((home / ".cache").exists(), "the probe must not write the export cache")
            rollout = home / ".codex/archived_sessions/rollout.jsonl"
            rollout.parent.mkdir(parents=True)
            rollout.write_text("{}\n")
            self.assertEqual(probe()[3], "codex=1 claude=0")

    @staticmethod
    def run_export():
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            exporter.main()
        return json.loads(output.getvalue())


if __name__ == "__main__":
    unittest.main()
