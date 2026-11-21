from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tlang import inspect_pipeline, pipeline_overview


def _write_log(pipe: Path, nodes: list[dict], name: str = "build_log_20260101_000000_abc.json") -> None:
    pipe.mkdir(parents=True, exist_ok=True)
    (pipe / name).write_text(json.dumps({"nodes": nodes}))


class InspectPipelineTests(unittest.TestCase):
    def test_build_status_rows(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art = tmp_path / "a.txt"
            art.write_text("a")
            _write_log(
                pipe,
                [
                    {
                        "node": "a",
                        "path": str(art),
                        "runtime": "T",
                        "serializer": "text",
                        "dependencies": [],
                        "status": "Completed",
                        "class": "String",
                    },
                    {
                        "node": "b",
                        "path": str(art),
                        "runtime": "R",
                        "serializer": "json",
                        "dependencies": ["a"],
                        "success": True,
                        "class": "VDict",
                    },
                    {
                        "node": "c",
                        "path": str(art),
                        "runtime": "Python",
                        "serializer": "csv",
                        "dependencies": ["b"],
                        "success": "false",
                        "class": "DataFrame",
                    },
                    {
                        "node": "d",
                        "path": str(art),
                        "runtime": "Julia",
                        "serializer": "default",
                        "dependencies": [],
                        "class": "String",
                    },
                ],
            )
            rows = inspect_pipeline(pipe)
            by_node = {row["node"]: row for row in rows}
            self.assertEqual([row["node"] for row in rows], ["a", "b", "c", "d"])
            self.assertEqual(by_node["a"]["status"], "Completed")
            self.assertEqual(by_node["b"]["status"], "Completed")
            self.assertEqual(by_node["c"]["status"], "SoftFailed")
            self.assertIsNone(by_node["d"]["status"])
            self.assertEqual(by_node["b"]["dependencies"], ["a"])
            self.assertEqual(by_node["a"]["runtime"], "T")
            self.assertEqual(by_node["a"]["serializer"], "text")
            self.assertTrue(by_node["a"]["path"].endswith("a.txt"))

    def test_which_log_selection(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art = tmp_path / "a.txt"
            art.write_text("a")
            entry = {
                "node": "a",
                "path": str(art),
                "runtime": "T",
                "serializer": "text",
                "dependencies": [],
                "status": "Completed",
                "class": "String",
            }
            _write_log(pipe, [entry], name="build_log_20260101_000000_aaa.json")
            other = dict(entry)
            other["runtime"] = "R"
            _write_log(pipe, [other], name="build_log_20260102_000000_zzz.json")
            latest = inspect_pipeline(pipe)
            self.assertEqual(latest[0]["runtime"], "R")
            older = inspect_pipeline(pipe, which_log="20260101")
            self.assertEqual(older[0]["runtime"], "T")

    def test_dag_fallback_when_unbuilt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            pipe.mkdir(parents=True)
            (pipe / "dag.json").write_text(
                json.dumps(
                    [
                        {"node_name": "a", "depends": []},
                        {"node_name": "b", "depends": ["a"]},
                    ]
                )
            )
            rows = inspect_pipeline(pipe)
            self.assertEqual([row["node"] for row in rows], ["a", "b"])
            self.assertEqual(rows[0]["status"], "unbuilt")
            self.assertIsNone(rows[0]["runtime"])
            self.assertEqual(rows[1]["dependencies"], ["a"])

    def test_missing_dir_and_bad_nodes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            with self.assertRaises(FileNotFoundError):
                inspect_pipeline(tmp_path / "nope")
            pipe = tmp_path / "_pipeline"
            _write_log(pipe, [{"oops": True}])
            rows = inspect_pipeline(pipe)
            self.assertEqual(rows, [])
            _write_log(
                pipe,
                {"nodes": "nope"},  # type: ignore[dict-item]
                name="build_log_20260102_000000_zzz.json",
            )
            with self.assertRaises(ValueError):
                inspect_pipeline(pipe, which_log="20260102")


class PipelineOverviewTests(unittest.TestCase):
    def test_overview_rows_and_filters(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art = tmp_path / "a.txt"
            art.write_text("a")
            err_art = tmp_path / "err.json"
            err_art.write_text(
                json.dumps({"type": "VError", "code": "RuntimeError", "message": "boom"})
            )
            _write_log(
                pipe,
                [
                    {
                        "node": "ok",
                        "path": str(art),
                        "runtime": "T",
                        "serializer": "text",
                        "dependencies": [],
                        "status": "Completed",
                        "class": "String",
                    },
                    {
                        "node": "bad",
                        "path": str(err_art),
                        "runtime": "T",
                        "serializer": "text",
                        "dependencies": [],
                        "status": "Completed",
                        "class": "VError",
                    },
                    {
                        "node": "skip",
                        "path": str(art),
                        "runtime": "R",
                        "serializer": "json",
                        "dependencies": [],
                        "status": "Skipped",
                        "class": "String",
                    },
                    {
                        "node": "soft",
                        "path": str(art),
                        "runtime": "Python",
                        "serializer": "csv",
                        "dependencies": [],
                        "status": "SoftFailed",
                        "class": "String",
                        "error_code": "ValueError",
                        "error_message": "bad value",
                    },
                ],
                name="build_log_20260103_000000_ovw.json",
            )
            rows = pipeline_overview(pipe)
            self.assertEqual([r["name"] for r in rows], ["bad", "soft", "ok", "skip"])
            self.assertEqual(
                [r["status"] for r in rows], ["Errored", "Errored", "Built", "Skipped"]
            )
            self.assertEqual(
                [r["class"] for r in rows], ["Error", "Error", "String", "String"]
            )
            self.assertEqual(
                [r["error_code"] for r in rows],
                ["RuntimeError", "ValueError", None, None],
            )
            self.assertEqual(
                [r["error_message"] for r in rows], ["boom", "bad value", None, None]
            )
            self.assertIsNone(rows[0]["path"])
            self.assertEqual(
                [r["name"] for r in pipeline_overview(pipe, only="failed")],
                ["bad", "soft"],
            )
            self.assertEqual(
                [r["name"] for r in pipeline_overview(pipe, only="built")], ["ok"]
            )
            self.assertEqual(
                [r["name"] for r in pipeline_overview(pipe, only="unbuilt")], ["skip"]
            )
            self.assertEqual(len(pipeline_overview(pipe, only="all")), 4)
            with self.assertRaises(ValueError):
                pipeline_overview(pipe, only="bad")
            with self.assertRaises(TypeError):
                pipeline_overview(pipe, only=1)


if __name__ == "__main__":
    unittest.main()
