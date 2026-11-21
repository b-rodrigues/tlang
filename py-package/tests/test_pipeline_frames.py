from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tlang import pipeline_config_to_frame, pipeline_to_frame


def _write_log(pipe: Path, nodes: list[dict], name: str = "build_log_20260101_000000_abc.json") -> None:
    pipe.mkdir(parents=True, exist_ok=True)
    (pipe / name).write_text(json.dumps({"nodes": nodes}))


class PipelineFramesTests(unittest.TestCase):
    def test_to_frame_rows(self) -> None:
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
                        "source": "[1, 2]",
                    },
                    {
                        "node": "b",
                        "path": str(art),
                        "runtime": "R",
                        "serializer": "json",
                        "dependencies": ["a"],
                        "status": "Completed",
                        "class": "String",
                        "script": "train.R",
                    },
                    {
                        "node": "c",
                        "path": str(art),
                        "runtime": "Python",
                        "serializer": "csv",
                        "dependencies": ["b"],
                        "status": "Completed",
                        "class": "String",
                    },
                ],
            )
            rows = pipeline_to_frame(pipe)
            self.assertEqual([r["name"] for r in rows], ["a", "b", "c"])
            self.assertEqual([r["depth"] for r in rows], [0, 1, 2])
            self.assertEqual([r["command_type"] for r in rows], ["command", "script", None])
            self.assertEqual(rows[1]["deps"], ["a"])
            self.assertEqual(rows[1]["runtime"], "R")
            self.assertEqual(rows[1]["serializer"], "json")
            # Build logs never store these: always None, never faked.
            self.assertIsNone(rows[0]["deserializer"])
            self.assertIsNone(rows[0]["noop"])

    def test_config_frame_counts_and_nones(self) -> None:
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
                        "source": "x",
                    },
                    {
                        "node": "b",
                        "path": str(art),
                        "runtime": "R",
                        "serializer": "json",
                        "dependencies": ["a"],
                        "status": "Completed",
                        "class": "String",
                        "source": "y",
                    },
                ],
            )
            rows = pipeline_config_to_frame(pipe)
            by_name = {r["name"]: r for r in rows}
            self.assertEqual(by_name["b"]["n_deps"], 1)
            self.assertEqual(by_name["a"]["n_deps"], 0)
            self.assertEqual(by_name["a"]["depth"], 0)
            # Unknown provenance stays None (unknown, not zero).
            for key in (
                "prov_serializer",
                "prov_noop",
                "shell",
                "flake",
                "n_funcs",
                "n_deps_global",
            ):
                self.assertIsNone(by_name["a"][key])

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
            rows = pipeline_to_frame(pipe)
            self.assertEqual([r["name"] for r in rows], ["a", "b"])
            self.assertEqual([r["depth"] for r in rows], [0, 1])
            self.assertIsNone(rows[0]["runtime"])
            self.assertIsNone(rows[0]["command_type"])
            cfg = pipeline_config_to_frame(pipe)
            self.assertEqual(cfg[1]["n_deps"], 1)
            self.assertIsNone(cfg[0]["serializer"])

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
                "source": "x",
            }
            _write_log(pipe, [entry], name="build_log_20260101_000000_aaa.json")
            other = dict(entry)
            other["runtime"] = "R"
            _write_log(pipe, [other], name="build_log_20260102_000000_zzz.json")
            self.assertEqual(pipeline_to_frame(pipe)[0]["runtime"], "R")
            self.assertEqual(pipeline_to_frame(pipe, which_log="20260101")[0]["runtime"], "T")


if __name__ == "__main__":
    unittest.main()
