from __future__ import annotations

import warnings
from collections import deque
from pathlib import Path
from typing import Any, Callable

from .read_node import (
    _list_build_logs,
    _pipeline_path,
    _read_build_log,
    _read_node_entry,
    _resolve_artifact_path,
    _select_build_log,
    _validate_non_empty_string,
)


def _deps_map(nodes: Any) -> dict[str, list[str]]:
    """Build a node -> dependencies map from a build-log nodes array."""
    if not isinstance(nodes, list):
        raise ValueError("Build log does not contain a `nodes` array.")
    result: dict[str, list[str]] = {}
    for entry in nodes:
        if not isinstance(entry, dict):
            continue
        name = entry.get("node")
        if not isinstance(name, str) or not name.strip():
            continue
        deps = entry.get("dependencies", [])
        if deps is None:
            deps = []
        if not isinstance(deps, list):
            raise ValueError(
                f"Node `{name}` has an invalid `dependencies` list."
            )
        clean = sorted({d for d in deps if isinstance(d, str) and d.strip()})
        result[name] = clean
    return result


def _closure(deps_map: dict[str, list[str]], name: str, include: str) -> list[str]:
    """Compute transitive closure over parents, children, or both."""
    if include not in {"children", "parents", "both"}:
        raise ValueError('`include` must be one of "children", "parents", "both".')
    if name not in deps_map:
        raise ValueError(f"Node `{name}` not found in build log.")

    children_map: dict[str, list[str]] = {}
    for node, deps in deps_map.items():
        for dep in deps:
            children_map.setdefault(dep, []).append(node)

    seen = [name]
    seen_set = {name}
    queue: deque[str] = deque([name])
    while queue:
        current = queue.popleft()
        neighbors: list[str] = []
        if include in {"children", "both"}:
            neighbors.extend(children_map.get(current, []))
        if include in {"parents", "both"}:
            neighbors.extend(deps_map.get(current, []))
        for neighbor in neighbors:
            if neighbor not in seen_set:
                seen_set.add(neighbor)
                seen.append(neighbor)
                queue.append(neighbor)

    missing = sorted(set(seen) - set(deps_map))
    if missing:
        raise ValueError(
            "Build log references unknown dependencies: " + ", ".join(missing) + "."
        )
    return seen


def read_node_tree(
    name: str,
    which_log: str | None = None,
    pipeline_dir: str | Path = "_pipeline",
    deserializer: Callable[[str | Path], Any] | None = None,
    return_path: bool = False,
    include: str = "children",
    on_unreadable: str = "error",
) -> dict[str, Any]:
    """Read a node and all of its related nodes.

    Reads the requested node plus its transitive ``children`` (nodes that
    depend on it), ``parents`` (nodes it depends on), or ``both``. Each node
    uses the serializer recorded in the build log unless ``deserializer`` is
    a callable, in which case that function reads every node. All nodes come
    from the single build log selected up front, so a concurrent build cannot
    mix two snapshots mid-loop.

    A single unreadable node aborts the whole tree by default. Pass
    ``on_unreadable="path"`` to fall back to the artifact path for nodes that
    fail to deserialize (for example ``^pmml`` model artifacts downstream),
    or ``on_unreadable="skip"`` to omit them. Both fallbacks warn naming the
    node and the error. ``return_path=True`` returns
    every path and never triggers the fallback.

    Parameters
    ----------
    name : str
        The name of the root node to retrieve.
    which_log : str or None, optional
        A regex used to select a specific build log file. Defaults to latest.
    pipeline_dir : str or Path, optional
        The path to the pipeline directory. Defaults to "_pipeline".
    deserializer : Callable or None, optional
        When None (the default), each node picks its reader from its own
        build-log ``serializer`` field.
    return_path : bool, optional
        If True, return artifact paths instead of deserialized values.
    include : str, optional
        One of "children" (default), "parents", or "both".
    on_unreadable : str, optional
        One of "error" (default), "path", or "skip".

    Returns
    -------
    dict[str, Any]
        Mapping of node name to deserialized value (or path).
    """
    _validate_non_empty_string(name, "name")
    if include not in {"children", "parents", "both"}:
        raise ValueError('`include` must be one of "children", "parents", "both".')
    if on_unreadable not in {"error", "path", "skip"}:
        raise ValueError('`on_unreadable` must be one of "error", "path", "skip".')
    if deserializer is not None and not callable(deserializer):
        raise TypeError("`deserializer` must be callable or None.")

    pipeline_path = _pipeline_path(pipeline_dir)
    if not pipeline_path.is_dir():
        raise FileNotFoundError(f"Pipeline directory `{pipeline_path}` does not exist.")

    logs = _list_build_logs(pipeline_path)
    log_file = _select_build_log(logs, which_log, pipeline_path)
    build_log = _read_build_log(pipeline_path / log_file)
    nodes = build_log.get("nodes")
    deps = _deps_map(nodes)
    wanted = _closure(deps, name, include)

    entries: dict[str, Any] = {}
    if isinstance(nodes, list):
        for entry in nodes:
            if isinstance(entry, dict) and isinstance(entry.get("node"), str):
                entries[entry["node"]] = entry

    result: dict[str, Any] = {}
    for node_name in wanted:
        if return_path:
            result[node_name] = _read_node_entry(
                entries[node_name], node_name, pipeline_path, deserializer, True
            )
            continue
        try:
            result[node_name] = _read_node_entry(
                entries[node_name], node_name, pipeline_path, deserializer, False
            )
        except Exception as err:
            if on_unreadable == "error":
                raise
            warnings.warn(
                f"Node `{node_name}` could not be deserialized ({err}); "
                + (
                    "returning the artifact path."
                    if on_unreadable == "path"
                    else "skipping it."
                ),
                UserWarning,
                stacklevel=2,
            )
            if on_unreadable == "path":
                result[node_name] = str(
                    _resolve_artifact_path(entries[node_name].get("path"), pipeline_path)
                )
            # "skip": omit the node.
    return result
