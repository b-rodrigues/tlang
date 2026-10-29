from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ._build_log import _text_or_none
from .frames import _status_of
from .pipeline_nodes import _validate_entry
from .read_node import (
    _list_build_logs,
    _pipeline_path,
    _read_build_log,
    _resolve_artifact_path,
    _select_build_log,
    _validate_non_empty_string,
)


def _row_from_entry(entry: dict[str, Any], pipeline_path: Path) -> dict[str, Any]:
    """Build one inspect row from a build-log node entry."""
    name = entry.get("node")
    deps = entry.get("dependencies", [])
    if not isinstance(deps, list):
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
    dag_path = pipeline_path / dag_file
    if not dag_path.is_file():
        raise FileNotFoundError(f"DAG file `{dag_path}` does not exist.")
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


_ONLY_VALUES = (
    "failed",
    "errored",
    "built",
    "completed",
    "unbuilt",
    "pending",
    "all",
)


def _overview_entries(
    pipeline_dir: str | Path, which_log: str | None
) -> dict[str, dict[str, Any]]:
    """Index the selected build log's entries by node name, or {} if absent."""
    from .node_inspect import _entries_map, _load_log

    pipeline_path = _pipeline_path(pipeline_dir)
    if not _list_build_logs(pipeline_path):
        return {}
    try:
        nodes, _log_file, _deps = _load_log(which_log, pipeline_path)
        return _entries_map(nodes)
    except (OSError, ValueError, KeyError, TypeError):
        return {}


def pipeline_overview(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    only: str | None = None,
) -> list[dict[str, Any]]:
    """Overview table, failed first. Mirrors T pipeline_overview.

    Rows have ``name``, ``runtime``, ``serializer``, ``dependencies``,
    ``status``, ``class``, ``path``, ``error_code``, and ``error_message``.
    Failed nodes carry ``status = "Errored"``; completed nodes carry
    ``"Built"``. Unbuilt or skipped nodes keep their own status instead of
    being reported as built.

    Use ``only="failed"``, ``"built"``, ``"unbuilt"``, or ``"all"`` to
    filter. Any other value raises ``ValueError``.
    """
    key: str | None = None
    if only is not None:
        if not isinstance(only, str):
            raise TypeError("only must be a string.")
        key = only.strip().lower()
        if key not in _ONLY_VALUES:
            raise ValueError(
                f'pipeline_overview: only must be failed, built, unbuilt, or all, but got "{only}".'
            )

    from ._build_log import _error_of_entry

    rows = inspect_pipeline(pipeline_dir=pipeline_dir, which_log=which_log)
    pipeline_path = _pipeline_path(pipeline_dir)
    entries = _overview_entries(pipeline_dir, which_log)
    out: list[dict[str, Any]] = []
    for r in rows:
        name = r.get("node")
        entry = entries.get(name, {}) if isinstance(name, str) else {}
        try:
            err = _error_of_entry(entry, pipeline_path) if entry else None
        except (OSError, ValueError, KeyError, TypeError):
            err = None
        raw_status = r.get("status")
        status_text = raw_status.strip() if isinstance(raw_status, str) else ""
        failed = (
            err is not None
            or status_text in ("Errored", "SoftFailed")
            or r.get("class") == "Error"
        )
        if failed:
            status = "Errored"
        elif status_text in ("Completed", "Built", "Cached"):
            status = "Built"
        elif status_text:
            status = status_text
        else:
            status = "Unbuilt"
        out.append(
            {
                "name": name,
                "runtime": r.get("runtime"),
                "serializer": r.get("serializer"),
                "dependencies": r.get("dependencies", []),
                "status": status,
                "class": "Error" if failed else r.get("class"),
                "path": None if failed else r.get("path"),
                "error_code": err["code"] if isinstance(err, dict) else None,
                "error_message": err["message"] if isinstance(err, dict) else None,
            }
        )
    failed_rows = [x for x in out if x["status"] == "Errored"]
    ok_rows = [x for x in out if x["status"] != "Errored"]
    ordered = failed_rows + ok_rows
    if key is None or key == "all":
        return ordered
    if key in ("failed", "errored"):
        return failed_rows
    if key in ("built", "completed"):
        return [x for x in ordered if x["status"] == "Built"]
    return [
        x
        for x in ordered
        if str(x["status"]).lower() in ("unbuilt", "pending", "skipped", "na")
    ]
