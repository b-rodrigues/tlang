from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tlang import build_log_to_frame, collect_exceptions, list_logs


def _write_log(pipe: Path, payload: dict, name: str) -> None:
    pipe.mkdir(parents=True, exist_ok=True)
    (pipe / name).write_text(json.dumps(payload))


class FramesTests(unittest.TestCase):
    def test_list_logs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            _write_log(
                pipe,
                {"pipeline": "demo", "nodes": []},
                "build_log_20260101_000000_aaa.json",
            )
            _write_log(pipe, {"nodes": []}, "build_log_20260102_000000_zzz.json")
            rows = list_logs(pipe)
            self.assertEqual(
                [row["filename"] for row in rows],
                ["build_log_20260102_000000_zzz.json", "build_log_20260101_000000_aaa.json"],
            )
            self.assertEqual(rows[0]["pipeline"], None)
            self.assertEqual(rows[1]["pipeline"], "demo")
            self.assertRegex(rows[0]["modification_time"], r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")
            self.assertGreaterEqual(rows[0]["size_kb"], 0)
            with self.assertRaises(FileNotFoundError):
                list_logs(tmp_path / "nope")

    def test_build_log_to_frame(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            _write_log(
                pipe,
                {
                    "nodes": [
                        {"node": "a", "status": "Completed", "duration": 1.5, "path": "/tmp/a"},
                        {"node": "b", "success": True, "duration": "2", "path": "/tmp/b"},
                        {"node": "c", "success": "false", "path": "/tmp/c"},
                        {"oops": True},
                    ]
                },
                "build_log_20260101_000000_abc.json",
            )
            rows = build_log_to_frame(pipeline_dir=pipe)
            self.assertEqual([row["name"] for row in rows], ["a", "b", "c"])
            self.assertEqual(rows[0]["status"], "Completed")
            self.assertEqual(rows[0]["duration"], 1.5)
            self.assertEqual(rows[1]["duration"], 2.0)
            self.assertIsNone(rows[2]["duration"])
            self.assertEqual(rows[2]["status"], "SoftFailed")

    def test_collect_exceptions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art_dir = tmp_path / "art"
            art_dir.mkdir()
            artifact = art_dir / "artifact"
            artifact.write_text("x")
            (art_dir / "warnings").write_text(
                json.dumps(["late column", {"kind": "NA", "message": "3 NAs"}])
            )
            _write_log(
                pipe,
                {
                    "nodes": [
                        {
                            "node": "bad",
                            "status": "Errored",
                            "error_code": "NixError",
                            "error_message": "line1\nboom",
                            "path": "/tmp/nonexistent",
                            "class": "Error",
                        },
                        {
                            "node": "soft",
                            "status": "SoftFailed",
                            "error_code": "ValueError",
                            "error_message": "bad value",
                            "path": str(artifact),
                            "class": "VError",
                        },
                        {
                            "node": "warned",
                            "status": "Completed",
                            "warnings": True,
                            "path": str(artifact),
                            "class": "DataFrame",
                        },
                        {
                            "node": "ok",
                            "status": "Completed",
                            "path": str(artifact),
                            "class": "DataFrame",
                        },
                    ]
                },
                "build_log_20260101_000000_abc.json",
            )
            rows = collect_exceptions(pipeline_dir=pipe)
            by_node = {row["node"] for row in rows}
            self.assertEqual(by_node, {"bad", "soft", "warned"})
            bad = next(row for row in rows if row["node"] == "bad")
            self.assertEqual((bad["status"], bad["code"], bad["message"]), ("Error", "NixError", "boom"))
            warns = [row for row in rows if row["status"] == "Warning"]
            self.assertEqual(len(warns), 2)
            self.assertEqual(warns[1]["code"], "NA")


if __name__ == "__main__":
    unittest.main()
