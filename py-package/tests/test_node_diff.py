from __future__ import annotations

from dataclasses import dataclass
import pickle
import tempfile
import unittest
from pathlib import Path

from tlang import diff_artifacts


@dataclass
class ModelSnapshot:
    weights: list[float]
    metadata: dict[str, object]


class NodeDiffTests(unittest.TestCase):
    def _artifact(self, value: object, directory: Path, name: str) -> Path:
        path = directory / name
        with path.open("wb") as handle:
            pickle.dump(value, handle)
        return path

    def test_diff_artifacts_reports_python_object_changes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            artifact_a = self._artifact(
                ModelSnapshot(
                    weights=[0.1, 0.2, 0.3],
                    metadata={"label": "baseline", "active": True},
                ),
                tmp_path,
                "a.pkl",
            )
            artifact_b = self._artifact(
                ModelSnapshot(
                    weights=[0.1, 0.25, 0.3],
                    metadata={"label": "candidate", "active": True},
                ),
                tmp_path,
                "b.pkl",
            )

            diff = diff_artifacts(
                artifact_a,
                artifact_b,
                node_a="weights",
                node_b="weights",
                class_a="ModelSnapshot",
                class_b="ModelSnapshot",
            )

            self.assertEqual(diff["kind"], "python_object_diff")
            self.assertFalse(diff["identical"])
            self.assertEqual(diff["value_type"], "ModelSnapshot")
            self.assertGreater(diff["summary"]["changes"], 0)
            self.assertEqual(diff["detail"]["renderer"], "difflib.unified_diff")
            self.assertIn("@@ ", diff["detailed_summary"])
            self.assertGreater(len(diff["hunks"]), 0)
            self.assertGreater(diff["summary"]["lines_added"], 0)
            self.assertGreater(diff["summary"]["lines_removed"], 0)

    def test_diff_artifacts_reports_identical_objects(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            artifact_a = self._artifact({"a": [1, 2, 3]}, tmp_path, "a.pkl")
            artifact_b = self._artifact({"a": [1, 2, 3]}, tmp_path, "b.pkl")

            diff = diff_artifacts(artifact_a, artifact_b)

            self.assertTrue(diff["identical"])
            self.assertEqual(diff["summary"]["changes"], 0)
            self.assertEqual(diff["detail"], {})
            self.assertEqual(diff["hunks"], [])


if __name__ == "__main__":
    unittest.main()
