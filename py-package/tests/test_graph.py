from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from tlang import (
    pipeline_cycles,
    pipeline_depth,
    pipeline_edges,
    pipeline_leaves,
    pipeline_node_depths,
    pipeline_roots,
    pipeline_to_dot,
    pipeline_to_mermaid,
    pipeline_validate,
)


def _write_dag(pipe: Path, entries: list[dict]) -> None:
    pipe.mkdir(parents=True, exist_ok=True)
    (pipe / "dag.json").write_text(json.dumps(entries))


def _dag_entries() -> list[dict]:
    return [
        {"node_name": "a", "depends": []},
        {"node_name": "b", "depends": ["a"]},
        {"node_name": "c", "depends": ["a", "b"]},
        {"node_name": "lonely", "depends": []},
    ]


class GraphTests(unittest.TestCase):
    def test_edges_roots_leaves(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            pipe = Path(tmp) / "_pipeline"
            _write_dag(pipe, _dag_entries())
            self.assertEqual(
                pipeline_edges(pipe),
                [["a", "b"], ["a", "c"], ["b", "c"]],
            )
            self.assertEqual(pipeline_roots(pipe), ["a", "lonely"])
            self.assertEqual(pipeline_leaves(pipe), ["c", "lonely"])

    def test_depth_and_depths(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            pipe = Path(tmp) / "_pipeline"
            _write_dag(pipe, _dag_entries())
            self.assertEqual(pipeline_depth(pipe), 2)
            self.assertEqual(
                pipeline_node_depths(pipe),
                {"a": 0, "b": 1, "c": 2, "lonely": 0},
            )

    def test_cycles_and_validate(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            pipe = Path(tmp) / "_pipeline"
            _write_dag(pipe, _dag_entries())
            self.assertEqual(pipeline_cycles(pipe), [])
            self.assertEqual(pipeline_validate(pipe), [])

    def test_validate_unknown_dep(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            pipe = Path(tmp) / "_pipeline"
            _write_dag(pipe, [{"node_name": "a", "depends": ["missing"]}])
            errors = pipeline_validate(pipe)
            self.assertEqual(len(errors), 1)
            self.assertIn("missing", errors[0])

    def test_dot_and_mermaid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            pipe = Path(tmp) / "_pipeline"
            _write_dag(pipe, _dag_entries())
            dot = pipeline_to_dot(pipe, title="Demo")
            self.assertIn("digraph pipeline", dot)
            self.assertIn('"a" -> "b"', dot)
            mermaid = pipeline_to_mermaid(pipe)
            self.assertIn("graph LR", mermaid)
            self.assertIn("-->", mermaid)


if __name__ == "__main__":
    unittest.main()
