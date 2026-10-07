from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tlang import (
    collect_exceptions,
    error_code,
    error_context,
    error_msg,
    inspect_node,
    lineage,
    read_node,
    warning_msg,
)


def _write_log(pipe: Path, nodes: list[dict], name: str = "build_log_20260101_000000_abc.json") -> None:
    pipe.mkdir(parents=True, exist_ok=True)
    (pipe / name).write_text(json.dumps({"nodes": nodes}))


def _entry(name: str, path: str, **fields) -> dict:
    entry: dict = {
        "node": name,
        "path": path,
        "runtime": "R",
        "serializer": "default",
        "dependencies": [],
        "status": "Completed",
        "class": "DataFrame",
    }
    entry.update(fields)
    return entry


class InspectTests(unittest.TestCase):
    def test_inspect_node(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art = tmp_path / "a.txt"
            art.write_text("a")
            _write_log(
                pipe,
                [
                    _entry("a", str(art)),
                    _entry("b", str(art), dependencies=["a"], serializer="json"),
                ],
            )
            info = inspect_node("b", pipeline_dir=pipe)
            self.assertEqual(info["name"], "b")
            self.assertEqual(info["runtime"], "R")
            self.assertEqual(info["serializer"], "json")
            self.assertEqual(info["dependencies"], ["a"])
            self.assertEqual(info["children"], [])
            self.assertEqual(info["status"], "Completed")
            self.assertIsNone(info["error"])
            self.assertEqual(info["warnings"], [])
            root = inspect_node("a", pipeline_dir=pipe)
            self.assertEqual(root["children"], ["b"])

    def test_lineage(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art = tmp_path / "a.txt"
            art.write_text("a")
            _write_log(
                pipe,
                [
                    _entry("a", str(art)),
                    _entry("b", str(art), dependencies=["a"]),
                    _entry("c", str(art), dependencies=["b"]),
                ],
            )
            self.assertEqual(
                lineage("b", pipeline_dir=pipe), {"parents": ["a"], "children": ["c"]}
            )
            self.assertEqual(
                lineage("c", pipeline_dir=pipe, direction="parents"),
                {"parents": ["b", "a"], "children": []},
            )
            self.assertEqual(
                lineage("a", pipeline_dir=pipe, direction="children"),
                {"parents": [], "children": ["b", "c"]},
            )
            with self.assertRaises(ValueError):
                lineage("a", pipeline_dir=pipe, direction="sideways")

    def test_error_msg_code_context(self) -> None:
        # An R failure is plain VError JSON, so any runtime reads it the same.
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            verror = tmp_path / "err.json"
            verror.write_text(
                json.dumps(
                    {
                        "type": "VError",
                        "code": "RunError",
                        "message": "Error in lm.fit(x, y) : NA/NaN/Inf in 'y'",
                        "na_count": 0,
                        "context": {"runtime": "R"},
                    }
                )
            )
            ok_art = tmp_path / "ok.txt"
            ok_art.write_text("ok")
            _write_log(
                pipe,
                [
                    _entry("bad", str(verror), status="SoftFailed", **{"class": "VError"}),
                    _entry("good", str(ok_art)),
                ],
            )
            self.assertEqual(error_code("bad", pipeline_dir=pipe), "RunError")
            self.assertIn("lm.fit", error_msg("bad", pipeline_dir=pipe))
            self.assertEqual(error_context("bad", pipeline_dir=pipe), {"runtime": "R"})
            with self.assertRaises(TypeError):
                error_msg("good", pipeline_dir=pipe)
            with self.assertRaises(TypeError):
                error_code("good", pipeline_dir=pipe)
            info = inspect_node("bad", pipeline_dir=pipe)
            assert info["error"] is not None
            self.assertIn("lm.fit", info["error"]["message"])

    def test_warning_msg(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            parent_dir = tmp_path / "parent_art"
            parent_dir.mkdir()
            (parent_dir / "artifact").write_text("x")
            (parent_dir / "warnings").write_text(json.dumps(["stale column"]))
            child_dir = tmp_path / "child_art"
            child_dir.mkdir()
            (child_dir / "artifact").write_text("x")
            (child_dir / "warnings").write_text(json.dumps(["late column"]))
            _write_log(
                pipe,
                [
                    _entry("parent", str(parent_dir / "artifact"), warnings=True),
                    _entry(
                        "child",
                        str(child_dir / "artifact"),
                        dependencies=["parent"],
                        warnings=True,
                    ),
                ],
            )
            self.assertEqual(
                warning_msg("child", pipeline_dir=pipe),
                "late column. Furthermore, Ancestor node 'parent' reported following warning: stale column",
            )
            self.assertEqual(warning_msg("parent", pipeline_dir=pipe), "stale column")

    def test_warnings_relative_log_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            data = tmp_path / "data"
            data.mkdir()
            (data / "artifact").write_text("x")
            (data / "warnings").write_text(json.dumps(["late column"]))
            _write_log(
                pipe,
                [_entry("a", "data/artifact", warnings=True)],
            )
            self.assertEqual(warning_msg("a", pipeline_dir=pipe), "late column")
            info = inspect_node("a", pipeline_dir=pipe)
            self.assertEqual(
                info["warnings"], [{"code": "Generic", "message": "late column"}]
            )

    def test_runtime_mismatch_hint(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            rds = tmp_path / "m.rds"
            rds.write_bytes(b"not a pickle")
            _write_log(
                pipe,
                [_entry("m", str(rds), runtime="R", serializer="default")],
            )
            with self.assertRaises(RuntimeError) as ctx:
                read_node("m", pipeline_dir=pipe)
            self.assertIn("built by runtime `R`", str(ctx.exception))

    def test_error_msg_log_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            blob = tmp_path / "m.bin"
            blob.write_bytes(b"\x00\x01")
            _write_log(
                pipe,
                [
                    _entry(
                        "bad",
                        str(blob),
                        status="Errored",
                        error_code="NixError",
                        error_message="build failed\nboom",
                    )
                ],
            )
            # Full message here; collect_exceptions() truncates to one line.
            self.assertEqual(error_code("bad", pipeline_dir=pipe), "NixError")
            self.assertEqual(error_msg("bad", pipeline_dir=pipe), "build failed\nboom")
            self.assertEqual(error_context("bad", pipeline_dir=pipe), {})

    def test_completed_verror_counts_as_failed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            verror = tmp_path / "err.json"
            verror.write_text(
                json.dumps({"type": "VError", "code": "RunError", "message": "boom"})
            )
            _write_log(
                pipe,
                [_entry("a", str(verror), status="Completed", **{"class": "VError"})],
            )
            self.assertEqual(error_code("a", pipeline_dir=pipe), "RunError")
            rows = collect_exceptions(pipeline_dir=pipe)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["code"], "RunError")

    def test_message_only_entry_keeps_class(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art = tmp_path / "a.txt"
            art.write_text("x")
            _write_log(
                pipe,
                [
                    {
                        "node": "a",
                        "path": str(art),
                        "runtime": "T",
                        "serializer": "text",
                        "dependencies": [],
                        "status": "SoftFailed",
                        "class": "VError",
                        "error_message": "just a message",
                    }
                ],
            )
            rows = collect_exceptions(pipeline_dir=pipe)
            self.assertEqual(rows[0]["code"], "VError")

    def test_softfailed_plain_class_reads_artifact(self) -> None:
        # SoftFailed with a non-error class still reads a VError artifact.
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            verror = tmp_path / "err.json"
            verror.write_text(
                json.dumps({"type": "VError", "code": "RunError", "message": "boom"})
            )
            _write_log(
                pipe,
                [_entry("a", str(verror), status="SoftFailed", **{"class": "DataFrame"})],
            )
            self.assertEqual(error_code("a", pipeline_dir=pipe), "RunError")
            rows = collect_exceptions(pipeline_dir=pipe)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["code"], "RunError")

    def test_healthy_verror_file_ignored(self) -> None:
        # A healthy node never opens its artifact, even when the file holds
        # valid VError JSON and the path would otherwise fail.
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            verror = tmp_path / "err.json"
            verror.write_text(
                json.dumps({"type": "VError", "code": "RunError", "message": "boom"})
            )
            _write_log(pipe, [_entry("a", str(verror))])
            with self.assertRaises(TypeError):
                error_msg("a", pipeline_dir=pipe)
            self.assertIsNone(inspect_node("a", pipeline_dir=pipe)["error"])

    def test_healthy_dangling_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            _write_log(pipe, [_entry("a", "/tmp/definitely-missing-artifact")])
            with self.assertRaises(TypeError):
                error_msg("a", pipeline_dir=pipe)
            info = inspect_node("a", pipeline_dir=pipe)
            self.assertIsNone(info["error"])
            self.assertTrue(info["path"].endswith("definitely-missing-artifact"))

    def test_lineage_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art = tmp_path / "a.txt"
            art.write_text("a")
            _write_log(
                pipe,
                [
                    _entry("a", str(art)),
                    _entry("z", str(art), dependencies=["a"]),
                    _entry("m", str(art), dependencies=["a"]),
                    _entry("leaf", str(art), dependencies=["z", "m"]),
                ],
            )
            # Sorted within each level, nearest first in every language.
            self.assertEqual(
                lineage("leaf", pipeline_dir=pipe, direction="parents")["parents"],
                ["m", "z", "a"],
            )
            self.assertEqual(
                lineage("a", pipeline_dir=pipe, direction="children")["children"],
                ["m", "z", "leaf"],
            )

    def test_lineage_byte_order(self) -> None:
        # Byte order (not locale order) in every language: B < _ < a < a1.
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art = tmp_path / "a.txt"
            art.write_text("a")
            _write_log(
                pipe,
                [
                    _entry("root", str(art)),
                    _entry("a1", str(art), dependencies=["root"]),
                    _entry("a", str(art), dependencies=["root"]),
                    _entry("_x", str(art), dependencies=["root"]),
                    _entry("B", str(art), dependencies=["root"]),
                ],
            )
            self.assertEqual(
                lineage("root", pipeline_dir=pipe, direction="children")["children"],
                ["B", "_x", "a", "a1"],
            )


if __name__ == "__main__":
    unittest.main()
