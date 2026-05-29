from __future__ import annotations

import pickle
import tempfile
import unittest
from pathlib import Path

import numpy as np

from tlang import diff_artifacts


class NodeDiffTests(unittest.TestCase):
    def _artifact(self, value: object, directory: Path, name: str) -> Path:
        path = directory / name
        with path.open("wb") as handle:
            pickle.dump(value, handle)
        return path

    def test_diff_artifacts_reports_ndarray_changes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            artifact_a = self._artifact(np.array([[1, 2], [3, 4]]), tmp_path, "a.pkl")
            artifact_b = self._artifact(np.array([[1, 2], [3, 5]]), tmp_path, "b.pkl")

            diff = diff_artifacts(
                artifact_a,
                artifact_b,
                node_a="weights",
                node_b="weights",
                class_a="ndarray",
                class_b="ndarray",
            )

            self.assertEqual(diff["kind"], "python_object_diff")
            self.assertFalse(diff["identical"])
            self.assertEqual(diff["value_type"], "ndarray")
            self.assertEqual(diff["summary"]["shape_a"], [2, 2])
            self.assertEqual(diff["summary"]["shape_b"], [2, 2])
            self.assertGreater(diff["summary"]["changes"], 0)

    def test_diff_artifacts_reports_identical_objects(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            artifact_a = self._artifact({"a": [1, 2, 3]}, tmp_path, "a.pkl")
            artifact_b = self._artifact({"a": [1, 2, 3]}, tmp_path, "b.pkl")

            diff = diff_artifacts(artifact_a, artifact_b)

            self.assertTrue(diff["identical"])
            self.assertEqual(diff["summary"]["changes"], 0)
            self.assertEqual(diff["detail"], {})


if __name__ == "__main__":
    unittest.main()
