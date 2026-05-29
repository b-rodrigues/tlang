from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .read_node import deserialize, read_node


def _load_deepdiff() -> Any:
    """Import DeepDiff lazily so basic package imports still work without it."""
    try:
        from deepdiff import DeepDiff
    except ImportError as err:  # pragma: no cover - exercised in integration environments
        raise RuntimeError(
            "DeepDiff is required for Python object diffs. The `tlang` helper may already be "
            "importable via PYTHONPATH, but your active Python environment must also include "
            "`deepdiff` so `node_diff()` can compare Python artifacts."
        ) from err
    return DeepDiff


def _normalize_json(value: Any) -> Any:
    """Convert DeepDiff output to plain JSON-serializable data."""
    if value is None or isinstance(value, (str, int, float, bool)):
        return value

    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")

    if isinstance(value, Path):
        return str(value)

    if isinstance(value, dict):
        return {str(key): _normalize_json(val) for key, val in value.items()}

    if isinstance(value, (list, tuple)):
        return [_normalize_json(item) for item in value]

    if isinstance(value, (set, frozenset)):
        return sorted(
            (_normalize_json(item) for item in value),
            key=lambda item: json.dumps(item, sort_keys=True, default=str),
        )

    item = getattr(value, "item", None)
    if callable(item):
        try:
            return _normalize_json(item())
        except Exception:  # noqa: BLE001
            pass

    tolist = getattr(value, "tolist", None)
    if callable(tolist):
        try:
            return _normalize_json(tolist())
        except Exception:  # noqa: BLE001
            pass

    shape = getattr(value, "shape", None)
    if shape is not None:
        try:
            return {
                "type": type(value).__name__,
                "shape": _normalize_json(list(shape)),
                "repr": str(value),
            }
        except Exception:  # noqa: BLE001
            pass

    return str(value)


def _count_changes(section: Any) -> int:
    """Count entries in a DeepDiff section."""
    normalized = _normalize_json(section)
    if isinstance(normalized, dict):
        return len(normalized)
    if isinstance(normalized, list):
        return len(normalized)
    return 1


def _shape_info(obj: Any) -> list[int] | None:
    """Return an object's shape as a plain list when available."""
    shape = getattr(obj, "shape", None)
    if shape is None:
        return None
    try:
        return [int(dim) for dim in shape]
    except Exception:  # noqa: BLE001
        normalized = _normalize_json(shape)
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
    del context

    DeepDiff = _load_deepdiff()
    diff = DeepDiff(obj_a, obj_b, verbose_level=2)
    normalized_detail = _normalize_json(diff.to_dict())
    categories = [
        {"kind": key, "count": _count_changes(section)}
        for key, section in normalized_detail.items()
    ]
    total_changes = sum(category["count"] for category in categories)

    summary: dict[str, Any] = {
        "changes": total_changes,
        "categories": categories,
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

    detailed_summary = "Objects are identical."
    if normalized_detail:
        pretty = getattr(diff, "pretty", None)
        detailed_summary = pretty() if callable(pretty) else json.dumps(normalized_detail, indent=2, sort_keys=True)

    return {
        "kind": "python_object_diff",
        "node_a": node_a,
        "node_b": node_b,
        "log_a": log_a,
        "log_b": log_b,
        "value_type": _value_type(obj_a, obj_b, class_a, class_b),
        "identical": not normalized_detail,
        "summary": summary,
        "detail": normalized_detail,
        "detailed_summary": detailed_summary,
        "hunks": [],
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
