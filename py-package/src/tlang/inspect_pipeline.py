from __future__ import annotations

from pathlib import Path
from typing import Any

from .read_node import (
    _list_build_logs,
    _pipeline_path,
    _read_build_log,
    _resolve_artifact_path,
    _select_build_log,
    _validate_non_empty_string,
)


def _text_or_none(value: Any) -> str | None:
    """Return stripped text or None for missing values."""
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def _status_of(entry: dict[str, Any]) -> str | None:
    """Derive a display status from a build-log node entry.

    Prefers the ``status`` string when present, else maps ``success``
    (bool or "true"/"false" string) to ``Completed``/``SoftFailed``.
    """
    status = entry.get("status")
    if isinstance(status, str) and status.strip():
        return status.strip()
    success = entry.get("success")
    if isinstance(success, bool):
        return "Completed" if success else "SoftFailed"
    if isinstance(success, str) and success.strip():
        return "Completed" if success.strip().lower() == "true" else "SoftFailed"
    return None


def _row_from_entry(entry: dict[str, Any], pipeline_path: Path) -> dict[str, Any]:
    """Build one inspect row from a build-log node entry."""
    name = entry.get("node")
    deps = entry.get("dependencies", [])
    if deps is None:
        deps = []
    clean_deps = sorted({d for d in deps if isinstance(d, str) and d.strip()})
    try:
        path = str(_resolve_artifact_path(entry.get("path"), pipeline_path))
    except ValueError:
        path = None
    return {
        "node": name,
        "runtime": _text_or_none(entry.get("runtime")),
        "serializer": _text_or_none(entry.get("serializer")),
        "dependencies": clean_deps,
        "status": _status_of(entry),
        "class": _text_or_none(entry.get("class")),
        "path": path,
    }


def _rows_from_dag(pipeline_path: Path, dag_file: str) -> list[dict[str, Any]]:
    """Build unbuilt rows from the static DAG file."""
    from .pipeline_nodes import _validate_entry

    dag_path = pipeline_path / dag_file
    if not dag_path.is_file():
        raise FileNotFoundError(f"DAG file `{dag_path}` does not exist.")
    import json

    try:
        with dag_path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except OSError as err:
        raise OSError(f"Failed to read DAG file `{dag_path}`: {err}") from err
    except json.JSONDecodeError as err:
        raise ValueError(f"Failed to read DAG file `{dag_path}`: {err}") from err
    if not isinstance(data, list):
        raise ValueError(f"DAG file `{dag_path}` must decode to an array.")
    rows: list[dict[str, Any]] = []
    for idx, entry in enumerate(data):
        node_name, deps = _validate_entry(entry, idx + 1, dag_path)
        rows.append(
            {
                "node": node_name,
                "runtime": None,
                "serializer": None,
                "dependencies": deps,
                "status": "unbuilt",
                "class": None,
                "path": None,
            }
        )
    return rows


def inspect_pipeline(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    dag_file: str = "dag.json",
) -> list[dict[str, Any]]:
    """Inspect pipeline nodes and their latest build status.

    Reads the selected build log and returns one row per node with its
    runtime, serializer, dependencies, status, class, and resolved artifact
    path. When no build logs exist, falls back to the static DAG file with
    ``status`` set to ``"unbuilt"``.

    Parameters
    ----------
    pipeline_dir : str or Path, optional
        The path to the pipeline directory. Defaults to "_pipeline".
    which_log : str or None, optional
        A regex used to select a specific build log file. Defaults to latest.
    dag_file : str, optional
        The DAG filename used only when no build logs exist.
        Defaults to "dag.json".

    Returns
    -------
    list[dict[str, Any]]
        One dict per node with keys ``node``, ``runtime``, ``serializer``,
        ``dependencies``, ``status``, ``class``, and ``path``.
    """
    _validate_non_empty_string(dag_file, "dag_file")
    pipeline_path = _pipeline_path(pipeline_dir)

    if not pipeline_path.is_dir():
        raise FileNotFoundError(f"Pipeline directory `{pipeline_path}` does not exist.")

    logs = _list_build_logs(pipeline_path)
    if not logs:
        return _rows_from_dag(pipeline_path, dag_file)

    log_file = _select_build_log(logs, which_log, pipeline_path)
    build_log = _read_build_log(pipeline_path / log_file)
    nodes = build_log.get("nodes")
    if not isinstance(nodes, list):
        raise ValueError(f"Build log `{log_file}` does not contain a `nodes` array.")

    rows: list[dict[str, Any]] = []
    for entry in nodes:
        if not isinstance(entry, dict):
            continue
        name = entry.get("node")
        if not isinstance(name, str) or not name.strip():
            continue
        rows.append(_row_from_entry(entry, pipeline_path))
    return rows
