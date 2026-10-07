from __future__ import annotations

from pathlib import Path
from typing import Any

from ._build_log import _error_of_entry, _text_or_none, _warning_rows
from .frames import _status_of
from .read_node import (
    _find_node_entry,
    _list_build_logs,
    _pipeline_path,
    _read_build_log,
    _resolve_artifact_path,
    _select_build_log,
    _validate_non_empty_string,
)
from .read_node_tree import _closure, _deps_map


def _load_log(
    which_log: str | None, pipeline_path: Path
) -> tuple[list[Any], str, dict[str, list[str]]]:
    """Select one build log and return (nodes, log file, deps map)."""
    logs = _list_build_logs(pipeline_path)
    log_file = _select_build_log(logs, which_log, pipeline_path)
    build_log = _read_build_log(pipeline_path / log_file)
    nodes = build_log.get("nodes")
    if not isinstance(nodes, list):
        raise ValueError(f"Build log `{log_file}` does not contain a `nodes` array.")
    return nodes, log_file, _deps_map(nodes)


def _load_entry(
    name: str,
    which_log: str | None,
    pipeline_path: Path,
) -> tuple[dict[str, Any], str, dict[str, list[str]]]:
    """Select the build log and return (node entry, log file, deps map)."""
    nodes, log_file, deps_map = _load_log(which_log, pipeline_path)
    return _find_node_entry(nodes, name, log_file), log_file, deps_map


def _entries_map(nodes: list[Any]) -> dict[str, dict[str, Any]]:
    """Index build-log entries by node name."""
    entries: dict[str, dict[str, Any]] = {}
    for entry in nodes:
        if isinstance(entry, dict) and isinstance(entry.get("node"), str):
            entries[entry["node"]] = entry
    return entries


def _require_error(
    name: str,
    which_log: str | None,
    pipeline_path: Path,
    func: str,
) -> dict[str, Any]:
    """Return the node's error dict, or raise when the node is healthy."""
    entry, _log_file, _deps = _load_entry(name, which_log, pipeline_path)
    verror = _error_of_entry(entry, pipeline_path)
    if verror is None:
        raise TypeError(f"Function `{func}` expects a failed node, but node `{name}` has no error.")
    return verror


def _check_dir(pipeline_dir: str | Path) -> Path:
    """Validate the pipeline directory argument."""
    pipeline_path = _pipeline_path(pipeline_dir)
    if not pipeline_path.is_dir():
        raise FileNotFoundError(f"Pipeline directory `{pipeline_path}` does not exist.")
    return pipeline_path


def show_code(
    name: str,
    which_log: str | None = None,
    pipeline_dir: str | Path = "_pipeline",
) -> str:
    """Return a node's source code for copy-paste tweaking.

    Foreign code comes back verbatim; T expressions come back as normalized
    T source. Nodes built from an exterior ``script =`` file return the
    script path instead (no copy is stored). Older build logs without
    recorded source raise an error telling you to rebuild.
    """
    _validate_non_empty_string(name, "name")
    pipeline_path = _check_dir(pipeline_dir)
    entry, _log_file, _deps = _load_entry(name, which_log, pipeline_path)
    script = entry.get("script")
    if isinstance(script, str) and script.strip():
        return script.strip()
    source = entry.get("source")
    if isinstance(source, str) and source.strip():
        return source
    raise ValueError(
        f"No source recorded for node `{name}`. Rebuild the pipeline to record it."
    )


def error_msg(
    name: str,
    which_log: str | None = None,
    pipeline_dir: str | Path = "_pipeline",
) -> str:
    """Return a failed node's human-readable error message.

    Foreign-runtime failures (R, Python, Julia, shell) are stored as VError
    JSON, so an R error message reads the same from Python and vice versa.
    Mirrors T's ``error_msg()``, including raising ``TypeError`` when the
    node is healthy (Python callers should check ``inspect_node()`` first
    when a healthy node is possible).
    """
    _validate_non_empty_string(name, "name")
    pipeline_path = _check_dir(pipeline_dir)
    return _require_error(name, which_log, pipeline_path, "error_msg")["message"]


def error_code(
    name: str,
    which_log: str | None = None,
    pipeline_dir: str | Path = "_pipeline",
) -> str:
    """Return a failed node's error code (for example ``"ValueError"``).

    Mirrors T's ``error_code()``.
    """
    _validate_non_empty_string(name, "name")
    pipeline_path = _check_dir(pipeline_dir)
    return _require_error(name, which_log, pipeline_path, "error_code")["code"]


def error_context(
    name: str,
    which_log: str | None = None,
    pipeline_dir: str | Path = "_pipeline",
) -> dict[str, Any]:
    """Return a failed node's error context dict (possibly empty).

    Mirrors T's ``error_context()``.
    """
    _validate_non_empty_string(name, "name")
    pipeline_path = _check_dir(pipeline_dir)
    context = _require_error(name, which_log, pipeline_path, "error_context")["context"]
    return context if isinstance(context, dict) else {}


def warning_msg(
    name: str,
    which_log: str | None = None,
    pipeline_dir: str | Path = "_pipeline",
) -> str:
    """Return a node's formatted warnings, or ``""`` when none.

    Upstream warnings are prefixed with the source node name, and multiple
    warnings join with ``". Furthermore, "``. Mirrors T's ``warning_msg()``.
    """
    _validate_non_empty_string(name, "name")
    pipeline_path = _check_dir(pipeline_dir)
    nodes, _log_file, deps_map = _load_log(which_log, pipeline_path)
    _find_node_entry(nodes, name, _log_file)  # validates the name
    entries = _entries_map(nodes)
    messages: list[str] = []
    for row in _warning_rows(name, entries[name], pipeline_path):
        messages.append(row["message"])
    for parent in _closure(deps_map, name, "parents")[1:]:
        for row in _warning_rows(parent, entries[parent], pipeline_path):
            messages.append(f"Ancestor node '{parent}' reported following warning: {row['message']}")
    return ". Furthermore, ".join(messages)


def _direct_children(deps_map: dict[str, list[str]], name: str) -> list[str]:
    """Direct dependents of a node, sorted."""
    return sorted(node for node, deps in deps_map.items() if name in deps)


def inspect_node(
    name: str,
    which_log: str | None = None,
    pipeline_dir: str | Path = "_pipeline",
) -> dict[str, Any]:
    """Inspect one node's metadata, lineage, error, and warnings.

    Parameters
    ----------
    name : str
        The name of the node to inspect.
    which_log : str or None, optional
        A regex used to select a specific build log file. Defaults to latest.
    pipeline_dir : str or Path, optional
        The path to the pipeline directory. Defaults to "_pipeline".

    Returns
    -------
    dict[str, Any]
        Keys ``name``, ``runtime``, ``serializer``, ``dependencies``,
        ``children`` (direct dependents), ``status``, ``class``, ``path``,
        ``error`` (``code``/``message``/``context``/``location`` dict or
        None), and ``warnings`` (list of ``code``/``message`` dicts).
    """
    _validate_non_empty_string(name, "name")
    pipeline_path = _check_dir(pipeline_dir)
    entry, _log_file, deps_map = _load_entry(name, which_log, pipeline_path)
    try:
        path = str(_resolve_artifact_path(entry.get("path"), pipeline_path))
    except ValueError:
        path = None
    warnings = [
        {"code": row["code"], "message": row["message"]}
        for row in _warning_rows(name, entry, pipeline_path)
    ]
    return {
        "name": name,
        "runtime": _text_or_none(entry.get("runtime")),
        "serializer": _text_or_none(entry.get("serializer")),
        "dependencies": sorted(
            {d for d in (entry.get("dependencies") or []) if isinstance(d, str) and d.strip()}
        )
        if isinstance(entry.get("dependencies"), list)
        else [],
        "children": _direct_children(deps_map, name),
        "status": _status_of(entry),
        "class": _text_or_none(entry.get("class")),
        "path": path,
        "error": _error_of_entry(entry, pipeline_path),
        "warnings": warnings,
    }


def lineage(
    name: str,
    which_log: str | None = None,
    pipeline_dir: str | Path = "_pipeline",
    direction: str = "both",
) -> dict[str, list[str]]:
    """List a node's transitive parents and children (names only).

    Parameters
    ----------
    name : str
        The name of the node.
    which_log : str or None, optional
        A regex used to select a specific build log file. Defaults to latest.
    pipeline_dir : str or Path, optional
        The path to the pipeline directory. Defaults to "_pipeline".
    direction : str, optional
        One of "parents", "children", or "both" (default).

    Returns
    -------
    dict[str, list[str]]
        ``parents`` (transitive dependencies, nearest first) and
        ``children`` (transitive dependents, nearest first). Only the
        requested directions are filled; the other is ``[]``.
    """
    _validate_non_empty_string(name, "name")
    if direction not in {"parents", "children", "both"}:
        raise ValueError('`direction` must be one of "parents", "children", "both".')
    pipeline_path = _check_dir(pipeline_dir)
    _entry, _log_file, deps_map = _load_entry(name, which_log, pipeline_path)
    parents: list[str] = []
    children: list[str] = []
    if direction in {"parents", "both"}:
        parents = _closure(deps_map, name, "parents")[1:]
    if direction in {"children", "both"}:
        children = _closure(deps_map, name, "children")[1:]
    return {"parents": parents, "children": children}
