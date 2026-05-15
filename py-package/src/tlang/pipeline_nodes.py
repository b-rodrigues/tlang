from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def _validate_non_empty_string(value: str, arg: str) -> None:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"`{arg}` must be a non-empty string.")


def _validate_entry(entry: Any, index: int, dag_path: Path) -> tuple[str, list[str]]:
    if not isinstance(entry, dict):
        raise ValueError(f"Entry {index} in `{dag_path}` must be an object.")

    node_name = entry.get("node_name")
    depends = entry.get("depends")
    if depends is None:
        depends = []

    if not isinstance(node_name, str) or not node_name.strip():
        raise ValueError(f"Entry {index} in `{dag_path}` has an invalid `node_name`.")

    if not isinstance(depends, list) or any(not isinstance(dep, str) or not dep.strip() for dep in depends):
        raise ValueError(f"Node `{node_name}` in `{dag_path}` has an invalid `depends` list.")

    return node_name, sorted(set(depends))


def _render_tree(node: str, children_map: dict[str, list[str]], prefix: str = "", is_last: bool = True, seen: tuple[str, ...] = (), depth: int = 0) -> list[str]:
    connector = "" if depth == 0 else ("└─ " if is_last else "├─ ")
    line = f"{prefix}{connector}{node}"

    if node in seen:
        cycle_prefix = f"{prefix}{'   ' if is_last else '│  '}"
        return [line, f"{cycle_prefix}↺ cycle detected"]

    children = children_map.get(node, [])
    if not children:
        return [line]

    next_prefix = f"{prefix}{'   ' if is_last else '│  '}"
    lines = [line]
    for idx, child in enumerate(children):
        lines.extend(_render_tree(child, children_map, next_prefix, idx == len(children) - 1, (*seen, node), depth + 1))
    return lines


def pipeline_nodes(pipeline_dir: str | Path = "_pipeline", dag_file: str = "dag.json") -> str:
    """List pipeline nodes from ``_pipeline/dag.json`` in a tree-like view."""
    pipeline_path = Path(pipeline_dir)
    _validate_non_empty_string(str(pipeline_path), "pipeline_dir")
    _validate_non_empty_string(dag_file, "dag_file")

    if not pipeline_path.is_dir():
        raise FileNotFoundError(f"Pipeline directory `{pipeline_path}` does not exist.")

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

    normalized = [_validate_entry(entry, idx + 1, dag_path) for idx, entry in enumerate(data)]
    node_names = [name for name, _ in normalized]

    duplicates = sorted({name for name in node_names if node_names.count(name) > 1})
    if duplicates:
        raise ValueError(
            f"DAG file `{dag_path}` has duplicate node_name values: {', '.join(duplicates)}"
        )

    node_set = set(node_names)
    unknown_deps = sorted({dep for _, deps in normalized for dep in deps if dep not in node_set})
    if unknown_deps:
        raise ValueError(
            f"DAG file `{dag_path}` references unknown dependencies: {', '.join(unknown_deps)}"
        )

    children_map: dict[str, list[str]] = {name: [] for name in node_names}
    incoming_count: dict[str, int] = {name: 0 for name in node_names}

    for name, deps in normalized:
        for parent in deps:
            children_map[parent].append(name)
            incoming_count[name] += 1

    for key in children_map:
        children_map[key] = sorted(children_map[key])

    roots = sorted([name for name, count in incoming_count.items() if count == 0]) or sorted(node_names)

    lines: list[str] = []
    for idx, root in enumerate(roots):
        lines.extend(_render_tree(root, children_map, "", idx == len(roots) - 1))

    return "\n".join(lines)
