from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .pipeline_nodes import _validate_entry
from .read_node import (
    _list_build_logs,
    _pipeline_path,
    _read_build_log,
    _select_build_log,
    _validate_non_empty_string,
)
from .read_node_tree import _deps_map

_CONFIG_COLUMNS = [
    "name",
    "runtime",
    "depth",
    "command_type",
    "serializer",
    "deserializer",
    "noop",
    "shell",
    "flake",
    "prov_serializer",
    "prov_deserializer",
    "prov_noop",
    "prov_shell",
    "prov_flake",
    "n_deps",
    "n_deps_global",
    "n_deps_node",
    "n_funcs",
    "n_funcs_global",
    "n_funcs_node",
    "n_incs",
    "n_incs_global",
    "n_incs_node",
    "n_env_vars",
    "n_env_vars_global",
    "n_env_vars_node",
    "n_args",
    "n_args_global",
    "n_args_node",
    "n_shell_args",
    "n_shell_args_global",
    "n_shell_args_node",
]


def _command_type_of(entry: dict[str, Any] | None) -> str | None:
    """Derive command vs script from build-log source fields."""
    if not isinstance(entry, dict):
        return None
    script = entry.get("script")
    if isinstance(script, str) and script.strip():
        return "script"
    source = entry.get("source")
    if isinstance(source, str) and source.strip():
        return "command"
    return None


def _text_or_none(value: Any) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def _load_frame_data(
    pipeline_dir: str | Path, which_log: str | None, dag_file: str
) -> tuple[list[str], dict[str, dict[str, Any]], dict[str, list[str]]]:
    """Load ordered names, entries by name, and deps map.

    Uses the selected build log when logs exist, else the static DAG file.
    """
    _validate_non_empty_string(dag_file, "dag_file")
    pipeline_path = _pipeline_path(pipeline_dir)
    if not pipeline_path.is_dir():
        raise FileNotFoundError(f"Pipeline directory `{pipeline_path}` does not exist.")

    logs = _list_build_logs(pipeline_path)
    if logs:
        log_file = _select_build_log(logs, which_log, pipeline_path)
        build_log = _read_build_log(pipeline_path / log_file)
        nodes = build_log.get("nodes")
        if not isinstance(nodes, list):
            raise ValueError(f"Build log `{log_file}` does not contain a `nodes` array.")
        deps_map = _deps_map(nodes)
        entries: dict[str, dict[str, Any]] = {}
        for entry in nodes:
            if isinstance(entry, dict) and isinstance(entry.get("node"), str):
                entries[entry["node"]] = entry
        return list(deps_map.keys()), entries, deps_map

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
    deps_map = {}
    for idx, entry in enumerate(data):
        name, deps = _validate_entry(entry, idx + 1, dag_path)
        deps_map[name] = deps
    return list(deps_map.keys()), {}, deps_map


def _depths_of(deps_map: dict[str, list[str]]) -> dict[str, int]:
    """Topological depth per node. Roots have depth 0."""
    cache: dict[str, int] = {}

    def depth_of(name: str, seen: frozenset[str] = frozenset()) -> int:
        if name in cache:
            return cache[name]
        if name in seen:
            return 0
        deps = deps_map.get(name, [])
        if not deps:
            cache[name] = 0
            return 0
        d = 1 + max((depth_of(dep, seen | {name}) for dep in deps), default=-1)
        cache[name] = d
        return d

    return {name: depth_of(name) for name in deps_map}


def pipeline_to_frame(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    dag_file: str = "dag.json",
) -> list[dict[str, Any]]:
    """Static per-node config table. Mirrors T ``pipeline_to_frame``.

    One dict per node with ``name``, ``runtime``, ``serializer``,
    ``deserializer``, ``noop``, ``deps``, ``depth``, and ``command_type``.

    File-based limits (explicit, not silent): build logs do not store
    ``deserializer`` or ``noop``, so both are always ``None``. ``runtime``
    and ``serializer`` are ``None`` for unbuilt nodes from ``dag.json``.
    ``command_type`` is ``"script"`` when the log entry has a ``script``
    field, ``"command"`` when it has ``source``, else ``None``. ``deps``
    is a sorted list (T uses a comma-separated string).
    """
    names, entries, deps_map = _load_frame_data(pipeline_dir, which_log, dag_file)
    depths = _depths_of(deps_map)
    rows: list[dict[str, Any]] = []
    for name in names:
        entry = entries.get(name)
        rows.append(
            {
                "name": name,
                "runtime": _text_or_none(entry.get("runtime")) if entry else None,
                "serializer": _text_or_none(entry.get("serializer")) if entry else None,
                "deserializer": None,
                "noop": None,
                "deps": list(deps_map.get(name, [])),
                "depth": depths.get(name, 0),
                "command_type": _command_type_of(entry),
            }
        )
    return rows


def pipeline_config_to_frame(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    dag_file: str = "dag.json",
) -> list[dict[str, Any]]:
    """Per-node config plus provenance counts. Mirrors T ``pipeline_config_to_frame``.

    Returns all T column names. Only ``name``, ``runtime``, ``depth``,
    ``command_type``, ``serializer``, and ``n_deps`` come from files.
    Every provenance column (``prov_*``), ``shell``, ``flake``,
    ``deserializer``, ``noop``, and every count except ``n_deps`` is
    ``None`` because build logs and ``dag.json`` do not store that data.
    ``None`` means unknown, not zero.
    """
    names, entries, deps_map = _load_frame_data(pipeline_dir, which_log, dag_file)
    depths = _depths_of(deps_map)
    rows: list[dict[str, Any]] = []
    for name in names:
        entry = entries.get(name)
        row: dict[str, Any] = {key: None for key in _CONFIG_COLUMNS}
        row["name"] = name
        row["runtime"] = _text_or_none(entry.get("runtime")) if entry else None
        row["depth"] = depths.get(name, 0)
        row["command_type"] = _command_type_of(entry)
        row["serializer"] = _text_or_none(entry.get("serializer")) if entry else None
        row["n_deps"] = len(deps_map.get(name, []))
        rows.append(row)
    return rows
