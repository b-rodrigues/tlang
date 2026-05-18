from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def _validate_non_empty_string(value: str, arg: str) -> None:
    """Validate that a value is a non-empty, stripped string.

    Parameters
    ----------
    value : str
        The value to check.
    arg : str
        The name of the argument being checked (used in error messages).

    Raises
    ------
    ValueError
        If `value` is not a string, or if it consists solely of whitespace.
    """
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"`{arg}` must be a non-empty string.")


def _validate_entry(entry: Any, index: int, dag_path: Path) -> tuple[str, list[str]]:
    """Validate a single DAG entry dictionary from the JSON structure.

    Extracts the node name and its dependency list, ensuring all entries are valid.

    Parameters
    ----------
    entry : Any
        The individual entry object from the DAG file, expected to be a dictionary.
    index : int
        The 1-based index of this entry in the DAG file (used in error messages).
    dag_path : Path
        The Path to the DAG file being parsed (used in error messages).

    Returns
    -------
    tuple[str, list[str]]
        A tuple containing:
        - The validated node name (as a non-empty string).
        - A sorted, duplicate-free list of dependency node names (as strings).

    Raises
    ------
    ValueError
        If the entry is not a dictionary, if `node_name` is missing or invalid,
        or if `depends` is not a list of non-empty strings.
    """
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


def pipeline_nodes(pipeline_dir: str | Path = "_pipeline", dag_file: str = "dag.json") -> dict[str, list[str]]:
    """Get pipeline nodes and their dependencies from the DAG configuration.

    Reads and validates the DAG definition from a JSON file (typically `_pipeline/dag.json`)
    and returns a mapping of node names to their lists of dependencies.

    Parameters
    ----------
    pipeline_dir : str | Path, optional
        The path to the pipeline directory where the DAG file is located.
        Defaults to "_pipeline".
    dag_file : str, optional
        The filename of the DAG configuration. Defaults to "dag.json".

    Returns
    -------
    dict[str, list[str]]
        A dictionary mapping each node name (str) to the list of node names
        it depends on (list of str), sorted alphabetically.

    Raises
    ------
    ValueError
        If `pipeline_dir` or `dag_file` is invalid/empty, if the JSON structure is
        malformed, contains duplicate node names, or references unknown dependencies.
    FileNotFoundError
        If the pipeline directory or the DAG file does not exist.
    OSError
        If the DAG file exists but cannot be read due to an I/O error.
    """
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

    return dict(normalized)
