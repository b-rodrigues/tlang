from __future__ import annotations

import json
import pickle
import tempfile
import unittest
from pathlib import Path

from tlang import read_node, read_node_tree
from tlang.read_node import _normalize_serializer


def _write_log(pipe: Path, nodes: list[dict], name: str = "build_log_20260101_000000_abc.json") -> None:
    pipe.mkdir(parents=True, exist_ok=True)
    (pipe / name).write_text(json.dumps({"nodes": nodes}))


def _node(name: str, path: Path, serializer: str, deps: list[str]) -> dict:
    return {
        "node": name,
        "path": str(path),
        "serializer": serializer,
        "dependencies": deps,
        "runtime": "T",
        "class": "String",
        "status": "Completed",
    }


def _has_pandas() -> bool:
    try:
        import pandas  # noqa: F401
    except ImportError:
        return False
    return True


class NormalizeTests(unittest.TestCase):
    def test_strips_hat_and_case(self) -> None:
        self.assertEqual(_normalize_serializer("^JSON"), "json")
        self.assertEqual(_normalize_serializer("  ^Csv "), "csv")
        self.assertEqual(_normalize_serializer(None), "default")
        self.assertEqual(_normalize_serializer(""), "default")


class AutoDispatchTests(unittest.TestCase):
    def test_json_text_default(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            payload = tmp_path / "v.json"
            payload.write_text(json.dumps({"a": 1}))
            text = tmp_path / "t.txt"
            text.write_bytes("hello\r\n".encode("utf-8"))
            blob = tmp_path / "m.pkl"
            with blob.open("wb") as handle:
                pickle.dump({"w": 1}, handle)
            _write_log(
                pipe,
                [
                    _node("j", payload, "json", []),
                    _node("t", text, "text", []),
                    _node("m", blob, "default", []),
                ],
            )
            self.assertEqual(
                read_node("j", pipeline_dir=pipe), {"a": 1}
            )
            # Exact bytes decoded as UTF-8: CRLF is preserved.
            self.assertEqual(read_node("t", pipeline_dir=pipe), "hello\r\n")
            self.assertEqual(read_node("m", pipeline_dir=pipe), {"w": 1})

    @unittest.skipUnless(_has_pandas(), "pandas is required for CSV dispatch")
    def test_csv(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            table = tmp_path / "t.csv"
            table.write_text("x,y\n1,2\n")
            _write_log(pipe, [_node("c", table, "^csv", [])])
            frame = read_node("c", pipeline_dir=pipe)
            self.assertEqual(list(frame.columns), ["x", "y"])

    def test_ipc_parquet_dispatch(self) -> None:
        try:
            import pandas as pd  # noqa: F401
            import pyarrow  # noqa: F401
        except ImportError:
            self.skipTest("pandas and pyarrow are required for IPC/Parquet dispatch")
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            import pandas as pd
            import pyarrow as pa
            import pyarrow.ipc as ipc
            import pyarrow.parquet as pq

            frame = pd.DataFrame({"x": [1, 2]})
            ipc_path = tmp_path / "t.ipc"
            table = pa.Table.from_pandas(frame)
            with pa.OSFile(str(ipc_path), "wb") as handle:
                with ipc.new_file(handle, table.schema) as writer:
                    writer.write_table(table)
            pq_path = tmp_path / "t.parquet"
            pq.write_table(table, str(pq_path))
            _write_log(
                pipe,
                [
                    _node("i", ipc_path, "ipc", []),
                    _node("p", pq_path, "parquet", []),
                ],
            )
            self.assertEqual(list(read_node("i", pipeline_dir=pipe)["x"]), [1, 2])
            self.assertEqual(list(read_node("p", pipeline_dir=pipe)["x"]), [1, 2])

    def test_deserializer_override_and_return_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art = tmp_path / "a.json"
            art.write_text(json.dumps({"x": 1}))
            _write_log(pipe, [_node("a", art, "json", [])])
            custom = read_node(
                "a", pipeline_dir=pipe, deserializer=lambda p: "custom"
            )
            self.assertEqual(custom, "custom")
            path = read_node("a", pipeline_dir=pipe, return_path=True)
            self.assertTrue(str(path).endswith("a.json"))

    def test_unknown_serializer_raises(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art = tmp_path / "a.bin"
            art.write_text("x")
            _write_log(pipe, [_node("a", art, "weirdfmt", [])])
            with self.assertRaises(RuntimeError) as ctx:
                read_node("a", pipeline_dir=pipe)
            self.assertIn("weirdfmt", str(ctx.exception))
            self.assertIn("return_path=True", str(ctx.exception))

    def test_pmml_onnx_suggest_return_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art = tmp_path / "m.pmml"
            art.write_text("<PMML/>")
            model = tmp_path / "m.onnx"
            model.write_text("onnx")
            _write_log(
                pipe,
                [
                    _node("p", art, "pmml", []),
                    _node("o", model, "onnx", []),
                ],
            )
            with self.assertRaises(RuntimeError) as ctx:
                read_node("p", pipeline_dir=pipe)
            self.assertIn("return_path=True", str(ctx.exception))
            with self.assertRaises(RuntimeError) as ctx2:
                read_node("o", pipeline_dir=pipe)
            self.assertIn("return_path=True", str(ctx2.exception))

    def test_rds_is_not_pickle(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art = tmp_path / "a.rds"
            art.write_text("x")
            _write_log(pipe, [_node("a", art, "rds", [])])
            with self.assertRaises(RuntimeError):
                read_node("a", pipeline_dir=pipe)

    def test_invalid_include(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            art = tmp_path / "a.txt"
            art.write_text("a")
            _write_log(pipe, [_node("a", art, "text", [])])
            with self.assertRaises(ValueError):
                read_node_tree("a", pipeline_dir=pipe, include="sideways")

    def test_csv_missing_pandas_message(self) -> None:
        import sys
        from unittest import mock

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            table = tmp_path / "t.csv"
            table.write_text("x\n1\n")
            _write_log(pipe, [_node("c", table, "csv", [])])
            with mock.patch.dict(sys.modules, {"pandas": None}):
                with self.assertRaises(RuntimeError) as ctx:
                    read_node("c", pipeline_dir=pipe)
            self.assertIn("pandas", str(ctx.exception))
            self.assertIn("tproject.toml", str(ctx.exception))


class TreeTests(unittest.TestCase):
    def _chain(self, tmp_path: Path) -> Path:
        pipe = tmp_path / "_pipeline"
        a = tmp_path / "a.txt"
        b = tmp_path / "b.txt"
        c = tmp_path / "c.txt"
        a.write_text("a")
        b.write_text("b")
        c.write_text("c")
        _write_log(
            pipe,
            [
                _node("a", a, "text", []),
                _node("b", b, "text", ["a"]),
                _node("c", c, "text", ["b"]),
            ],
        )
        return pipe

    def test_children_parents_both(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = self._chain(tmp_path)
            self.assertEqual(
                sorted(read_node_tree("a", pipeline_dir=pipe)), ["a", "b", "c"]
            )
            self.assertEqual(
                sorted(read_node_tree("c", pipeline_dir=pipe, include="parents")),
                ["a", "b", "c"],
            )
            both = read_node_tree("b", pipeline_dir=pipe, include="both")
            self.assertEqual(sorted(both), ["a", "b", "c"])
            self.assertEqual(both["b"], "b")

    def test_cycle_terminates(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            a = tmp_path / "a.txt"
            b = tmp_path / "b.txt"
            a.write_text("a")
            b.write_text("b")
            _write_log(
                pipe,
                [_node("a", a, "text", ["b"]), _node("b", b, "text", ["a"])],
            )
            tree = read_node_tree("a", pipeline_dir=pipe, include="both")
            self.assertEqual(sorted(tree), ["a", "b"])

    def test_missing_dependency_errors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            a = tmp_path / "a.txt"
            a.write_text("a")
            _write_log(pipe, [_node("a", a, "text", ["ghost"])])
            with self.assertRaises(ValueError) as ctx:
                read_node_tree("a", pipeline_dir=pipe, include="parents")
            self.assertIn("ghost", str(ctx.exception))

    def test_missing_node_is_value_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            a = tmp_path / "a.txt"
            a.write_text("a")
            _write_log(pipe, [_node("a", a, "text", [])])
            with self.assertRaises(ValueError):
                read_node_tree("nope", pipeline_dir=pipe)

    def test_single_snapshot_race(self) -> None:
        # The race only exists when `which_log` is omitted ("latest"). A newer
        # log written during the first deserialization rewrites node `b` to a
        # different artifact; the in-progress tree must still return the
        # original contents.
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            pipe.mkdir(parents=True)
            a = tmp_path / "a.txt"
            b_orig = tmp_path / "b.txt"
            b_new = tmp_path / "b_new.txt"
            a.write_text("one")
            b_orig.write_text("two")
            b_new.write_text("CHANGED")
            _write_log(
                pipe,
                [_node("a", a, "text", []), _node("b", b_orig, "text", ["a"])],
                name="build_log_20260101_000000_aaa.json",
            )

            def racing_deserializer(path) -> str:
                text = Path(path).read_bytes().decode("utf-8")
                newer = {
                    "nodes": [
                        _node("a", a, "text", []),
                        _node("b", b_new, "text", ["a"]),
                        _node("c", a, "text", ["b"]),
                    ]
                }
                (pipe / "build_log_20260102_000000_zzz.json").write_text(
                    json.dumps(newer)
                )
                return text

            tree = read_node_tree(
                "a",
                pipeline_dir=pipe,
                deserializer=racing_deserializer,
                include="children",
            )
            # The node set is fixed before any read, so "c" can never leak in.
            # The content assertion below is the one guarding the race: the old
            # per-node log resolution would return "CHANGED" for "b".
            self.assertEqual(sorted(tree), ["a", "b"])
            self.assertEqual(tree["b"], "two")
            self.assertNotIn("c", tree)

    def test_on_unreadable(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            pipe = tmp_path / "_pipeline"
            good = tmp_path / "good.txt"
            bad = tmp_path / "bad.pmml"
            good.write_text("ok")
            bad.write_text("<PMML/>")
            _write_log(
                pipe,
                [
                    _node("good", good, "text", []),
                    _node("bad", bad, "pmml", ["good"]),
                ],
            )
            with self.assertRaises(RuntimeError):
                read_node_tree("good", pipeline_dir=pipe, include="children")
            with self.assertWarns(UserWarning) as warned:
                as_path = read_node_tree(
                    "good", pipeline_dir=pipe, include="children", on_unreadable="path"
                )
            self.assertIn("bad", str(warned.warning))
            self.assertEqual(as_path["good"], "ok")
            self.assertTrue(str(as_path["bad"]).endswith("bad.pmml"))
            with self.assertWarns(UserWarning):
                skipped = read_node_tree(
                    "good", pipeline_dir=pipe, include="children", on_unreadable="skip"
                )
            self.assertEqual(sorted(skipped), ["good"])


if __name__ == "__main__":
    unittest.main()
