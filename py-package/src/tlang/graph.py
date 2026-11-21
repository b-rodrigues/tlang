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


def _load_deps_map(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    dag_file: str = "dag.json",
) -> dict[str, list[str]]:
    """Load node -> dependencies map from build log or DAG file.

    Uses the latest build log when logs exist, else the static DAG file.
    Preserves node order from the source file. Dependency lists are sorted
    for deterministic output across languages.
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
        return _deps_map(nodes)

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
    out: dict[str, list[str]] = {}
    for idx, entry in enumerate(data):
        name, deps = _validate_entry(entry, idx + 1, dag_path)
        out[name] = deps
    return out


def pipeline_edges(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    dag_file: str = "dag.json",
) -> list[list[str]]:
    """Return dependency edges as [dependency, dependent] pairs.

    Mirrors T ``pipeline_edges``. Order follows node order in the source
    file, with dependencies sorted alphabetically per node.
    """
    deps_map = _load_deps_map(pipeline_dir, which_log, dag_file)
    edges: list[list[str]] = []
    for name, deps in deps_map.items():
        for dep in deps:
            edges.append([dep, name])
    return edges


def pipeline_roots(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    dag_file: str = "dag.json",
) -> list[str]:
    """Return names of root nodes (no dependencies). Mirrors T ``pipeline_roots``."""
    deps_map = _load_deps_map(pipeline_dir, which_log, dag_file)
    return [name for name, deps in deps_map.items() if not deps]


def pipeline_leaves(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    dag_file: str = "dag.json",
) -> list[str]:
    """Return names of leaf nodes (no dependents). Mirrors T ``pipeline_leaves``."""
    deps_map = _load_deps_map(pipeline_dir, which_log, dag_file)
    all_deps = {d for deps in deps_map.values() for d in deps}
    return [name for name in deps_map if name not in all_deps]


def pipeline_node_depths(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    dag_file: str = "dag.json",
) -> dict[str, int]:
    """Return topological depth per node. Roots have depth 0."""
    deps_map = _load_deps_map(pipeline_dir, which_log, dag_file)
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


def pipeline_depth(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    dag_file: str = "dag.json",
) -> int:
    """Return maximum topological depth. Mirrors T ``pipeline_depth``."""
    depths = pipeline_node_depths(pipeline_dir, which_log, dag_file)
    return max(depths.values(), default=0)


def pipeline_cycles(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    dag_file: str = "dag.json",
) -> list[str]:
    """Return names of nodes in dependency cycles. Empty means valid DAG."""
    deps_map = _load_deps_map(pipeline_dir, which_log, dag_file)
    color: dict[str, int] = {name: 0 for name in deps_map}
    cycle_nodes: list[str] = []

    def visit(name: str) -> None:
        c = color.get(name, 0)
        if c == 1:
            if name not in cycle_nodes:
                cycle_nodes.append(name)
            return
        if c != 0:
            return
        color[name] = 1
        for dep in deps_map.get(name, []):
            if dep in color:
                visit(dep)
        color[name] = 2

    for name in deps_map:
        visit(name)
    return cycle_nodes


def pipeline_validate(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    dag_file: str = "dag.json",
) -> list[str]:
    """Return structural error messages. Empty list means valid.

    Checks unknown dependencies and cycles. Mirrors the structural subset
    of T ``pipeline_validate`` that clients can verify from files.
    """
    deps_map = _load_deps_map(pipeline_dir, which_log, dag_file)
    errors: list[str] = []
    for name, deps in deps_map.items():
        for dep in deps:
            if dep not in deps_map:
                errors.append(
                    f"Node `{name}` depends on `{dep}` which does not exist in the pipeline."
                )
    cycles = pipeline_cycles(pipeline_dir, which_log, dag_file)
    if cycles:
        errors.append(
            "Pipeline has dependency cycle(s) involving: " + ", ".join(cycles) + "."
        )
    return errors


def _dot_escape(name: str) -> str:
    return name.replace("\\", "\\\\").replace('"', '\\"')


def pipeline_to_dot(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    dag_file: str = "dag.json",
    title: str | None = None,
) -> str:
    """Return Graphviz DOT string of the pipeline graph."""
    deps_map = _load_deps_map(pipeline_dir, which_log, dag_file)
    lines = ["digraph pipeline {"]
    if title:
        lines.append(f'  label="{_dot_escape(title)}";')
    lines.append("  rankdir=LR;")
    lines.append("  node [shape=box];")
    for name in deps_map:
        lines.append(f'  "{_dot_escape(name)}";')
    for name, deps in deps_map.items():
        for dep in deps:
            lines.append(f'  "{_dot_escape(dep)}" -> "{_dot_escape(name)}";')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _mermaid_id(name: str, index: int) -> str:
    safe = "".join(c if (c.isalnum() or c == "_") else "_" for c in name)
    if not safe or safe[0].isdigit():
        safe = f"n_{safe}"
    return f"{safe}__{index}"


def pipeline_to_mermaid(
    pipeline_dir: str | Path = "_pipeline",
    which_log: str | None = None,
    dag_file: str = "dag.json",
    title: str | None = None,
) -> str:
    """Return Mermaid flowchart string of the pipeline graph."""
    deps_map = _load_deps_map(pipeline_dir, which_log, dag_file)
    ids = {name: _mermaid_id(name, i) for i, name in enumerate(deps_map)}
    lines = []
    if title:
        lines.append("---")
        lines.append(f"tlang-title: {title}")
        lines.append("---")
    lines.append("graph LR")
    for name in deps_map:
        lines.append(f'  {ids[name]}["{name}"];')
    for name, deps in deps_map.items():
        for dep in deps:
            if dep in ids:
                lines.append(f"  {ids[dep]} --> {ids[name]};")
    return "\n".join(lines) + "\n"
