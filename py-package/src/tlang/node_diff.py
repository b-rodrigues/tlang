from __future__ import annotations

import difflib
from dataclasses import asdict, is_dataclass
import json
from pathlib import Path
import re
from typing import Any

from .read_node import deserialize, read_node


def _stable_json_value(value: Any) -> Any:
    """Convert Python values to a stable JSON-serializable representation."""
    if value is None or isinstance(value, (str, int, float, bool)):
        return value

    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")

    if isinstance(value, Path):
        return str(value)

    if is_dataclass(value) and not isinstance(value, type):
        return _stable_json_value(asdict(value))

    if isinstance(value, dict):
        return {str(key): _stable_json_value(val) for key, val in value.items()}

    if isinstance(value, (list, tuple)):
        return [_stable_json_value(item) for item in value]

    if isinstance(value, (set, frozenset)):
        return sorted(
            (_stable_json_value(item) for item in value),
            key=lambda item: json.dumps(item, sort_keys=True, default=str),
        )

    item = getattr(value, "item", None)
    if callable(item):
        try:
            return _stable_json_value(item())
        except Exception:  # noqa: BLE001
            pass

    tolist = getattr(value, "tolist", None)
    if callable(tolist):
        try:
            return _stable_json_value(tolist())
        except Exception:  # noqa: BLE001
            pass

    shape = getattr(value, "shape", None)
    if shape is not None:
        try:
            return {
                "type": type(value).__name__,
                "shape": _stable_json_value(list(shape)),
                "repr": repr(value),
            }
        except Exception:  # noqa: BLE001
            pass

    return value


def _json_lines(obj: Any) -> list[str]:
    """Render an object as stable pretty-printed JSON lines."""
    stable = _stable_json_value(obj)
    return json.dumps(stable, indent=2, sort_keys=True, default=repr).splitlines(keepends=True)


def _parse_unified_diff_hunks(lines: list[str]) -> list[dict[str, Any]]:
    """Convert unified diff lines to coarse VDiff hunks."""
    if not lines:
        return []

    header_indexes = [
        index for index, line in enumerate(lines) if line.startswith("@@ ") and line.endswith(" @@")
    ]

    if not header_indexes:
        stripped = [line.removesuffix("\n") for line in lines]
        return [
            {
                "kind": "replace",
                "a_start": 0,
                "a_end": len(stripped),
                "b_start": 0,
                "b_end": len(stripped),
                "lines_a": stripped,
                "lines_b": stripped,
            }
        ]

    hunks: list[dict[str, Any]] = []
    starts = header_indexes
    ends = header_indexes[1:] + [len(lines)]
    for start, end in zip(starts, ends):
        block = lines[start:end]
        header = block[0]
        match = re.match(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", header)
        if match is None:
            continue

        a_start = int(match.group(1)) - 1
        a_len = int(match.group(2) or "1")
        b_start = int(match.group(3)) - 1
        b_len = int(match.group(4) or "1")

        lines_a: list[str] = []
        lines_b: list[str] = []
        has_prev = False
        has_next = False

        for line in block[1:]:
            if line.startswith("--- ") or line.startswith("+++ ") or line.startswith("\\"):
                continue
            stripped = line[1:].removesuffix("\n") if line else ""
            if line.startswith("-"):
                has_prev = True
                lines_a.append(stripped)
            elif line.startswith("+"):
                has_next = True
                lines_b.append(stripped)
            elif line.startswith(" "):
                lines_a.append(stripped)
                lines_b.append(stripped)
            else:
                raw = line.removesuffix("\n")
                lines_a.append(raw)
                lines_b.append(raw)

        if has_prev and has_next:
            kind = "replace"
        elif has_prev:
            kind = "delete"
        elif has_next:
            kind = "insert"
        else:
            kind = "equal"

        hunks.append(
            {
                "kind": kind,
                "a_start": a_start,
                "a_end": a_start + a_len,
                "b_start": b_start,
                "b_end": b_start + b_len,
                "lines_a": lines_a,
                "lines_b": lines_b,
            }
        )

    return hunks


def _render_diff(
    lines_a: list[str],
    lines_b: list[str],
    *,
    fromfile: str,
    tofile: str,
    context: int,
) -> tuple[str, list[str], list[dict[str, Any]]]:
    """Render a git-like unified diff for two Python values."""
    lines = list(
        difflib.unified_diff(
            lines_a,
            lines_b,
            fromfile=fromfile,
            tofile=tofile,
            n=context,
        )
    )
    hunks = _parse_unified_diff_hunks(lines)
    return "".join(lines), [line.removesuffix("\n") for line in lines], hunks


def _diff_line_counts(lines: list[str]) -> tuple[int, int]:
    """Count added and removed unified diff lines."""
    lines_added = sum(1 for line in lines if line.startswith("+") and not line.startswith("+++ "))
    lines_removed = sum(1 for line in lines if line.startswith("-") and not line.startswith("--- "))
    return lines_added, lines_removed


def _shape_info(obj: Any) -> list[int] | None:
    """Return an object's shape as a plain list when available."""
    shape = getattr(obj, "shape", None)
    if shape is None:
        return None
    try:
        return [int(dim) for dim in shape]
    except Exception:  # noqa: BLE001
        normalized = _stable_json_value(shape)
        return normalized if isinstance(normalized, list) else None


def _dtype_info(obj: Any) -> str | None:
    """Return an object's dtype when available."""
    dtype = getattr(obj, "dtype", None)
    return None if dtype is None else str(dtype)


def _value_type(obj_a: Any, obj_b: Any, class_a: str | None, class_b: str | None) -> str:
    """Choose the most informative value type label for the diff envelope."""
    class_a = class_a.strip() if isinstance(class_a, str) else ""
    class_b = class_b.strip() if isinstance(class_b, str) else ""
    if class_a and class_a == class_b:
        return class_a
    if class_a and class_b:
        return f"{class_a} -> {class_b}"

    name_a = type(obj_a).__name__
    name_b = type(obj_b).__name__
    return name_a if name_a == name_b else f"{name_a} -> {name_b}"


def diff_objects(
    obj_a: Any,
    obj_b: Any,
    *,
    node_a: str = "node_a",
    node_b: str = "node_b",
    log_a: str = "latest",
    log_b: str = "latest",
    class_a: str | None = None,
    class_b: str | None = None,
    context: int = 3,
) -> dict[str, Any]:
    """Diff two Python objects and return a T-compatible VDiff envelope."""
    lines_a = _json_lines(obj_a)
    lines_b = _json_lines(obj_b)
    identical_objects = lines_a == lines_b
    detail: dict[str, Any] = {}
    detailed_summary = "Objects are identical."
    hunks: list[dict[str, Any]] = []
    lines_added = 0
    lines_removed = 0

    if not identical_objects:
        detailed_summary, diff_lines, hunks = _render_diff(
            lines_a,
            lines_b,
            fromfile=f"{node_a}:{log_a}",
            tofile=f"{node_b}:{log_b}",
            context=context,
        )
        lines_added, lines_removed = _diff_line_counts(diff_lines)
        detail = {
            "renderer": "difflib.unified_diff",
            "format": "json",
            "fromfile": f"{node_a}:{log_a}",
            "tofile": f"{node_b}:{log_b}",
            "lines": diff_lines,
        }

    summary: dict[str, Any] = {
        "changes": lines_added + lines_removed,
        "lines_added": lines_added,
        "lines_removed": lines_removed,
    }

    shape_a = _shape_info(obj_a)
    shape_b = _shape_info(obj_b)
    if shape_a is not None:
        summary["shape_a"] = shape_a
    if shape_b is not None:
        summary["shape_b"] = shape_b

    dtype_a = _dtype_info(obj_a)
    dtype_b = _dtype_info(obj_b)
    if dtype_a is not None:
        summary["dtype_a"] = dtype_a
    if dtype_b is not None:
        summary["dtype_b"] = dtype_b

    return {
        "kind": "python_object_diff",
        "node_a": node_a,
        "node_b": node_b,
        "log_a": log_a,
        "log_b": log_b,
        "value_type": _value_type(obj_a, obj_b, class_a, class_b),
        "identical": identical_objects,
        "summary": summary,
        "detail": detail,
        "detailed_summary": detailed_summary,
        "hunks": hunks,
    }


def diff_artifacts(
    path_a: str | Path,
    path_b: str | Path,
    *,
    node_a: str = "node_a",
    node_b: str = "node_b",
    log_a: str = "latest",
    log_b: str = "latest",
    class_a: str | None = None,
    class_b: str | None = None,
    context: int = 3,
) -> dict[str, Any]:
    """Deserialize two artifacts and diff the resulting Python objects."""
    obj_a = deserialize(path_a)
    obj_b = deserialize(path_b)
    return diff_objects(
        obj_a,
        obj_b,
        node_a=node_a,
        node_b=node_b,
        log_a=log_a,
        log_b=log_b,
        class_a=class_a,
        class_b=class_b,
        context=context,
    )


def diff_nodes(
    node_a: str,
    node_b: str,
    *,
    which_log_a: str | None = None,
    which_log_b: str | None = None,
    pipeline_dir: str | Path = "_pipeline",
    context: int = 3,
) -> dict[str, Any]:
    """Load two nodes via `read_node()` and diff their deserialized Python objects."""
    path_a = read_node(node_a, which_log=which_log_a, pipeline_dir=pipeline_dir, return_path=True)
    path_b = read_node(node_b, which_log=which_log_b, pipeline_dir=pipeline_dir, return_path=True)
    return diff_artifacts(
        path_a,
        path_b,
        node_a=node_a,
        node_b=node_b,
        log_a=which_log_a or "latest",
        log_b=which_log_b or "latest",
        context=context,
    )
