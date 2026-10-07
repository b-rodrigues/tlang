from __future__ import annotations

import json
import pickle
import re
from pathlib import Path
from typing import Any, BinaryIO, Callable


FIXTURE_LOGS = {"build_log_ocaml_mock.json", "build_log_legacy_version.json"}


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


def _pipeline_path(pipeline_dir: str | Path) -> Path:
    """Convert and validate the pipeline directory path.

    Parameters
    ----------
    pipeline_dir : str | Path
        The directory path to convert and validate.

    Returns
    -------
    Path
        The validated Path object.

    Raises
    ------
    ValueError
        If the pipeline directory path is empty or consists solely of whitespace.
    """
    path = Path(pipeline_dir)
    if not str(path).strip():
        raise ValueError("`pipeline_dir` must be a non-empty path.")
    return path


def _should_filter_fixture_logs(pipeline_dir: Path) -> bool:
    """Determine if internal fixture logs should be filtered out.

    Fixture logs should be filtered only when running from a repository checkout,
    which is detected by checking for the existence of `builder_logs.ml`.

    Parameters
    ----------
    pipeline_dir : Path
        The Path to the pipeline directory.

    Returns
    -------
    bool
        True if fixture logs should be filtered, False otherwise.
    """
    repo_root = pipeline_dir.parent
    return (repo_root / "src" / "pipeline" / "builder_logs.ml").is_file()


def _list_build_logs(pipeline_dir: Path) -> list[str]:
    """List build log filenames in the pipeline directory, sorted reverse-alphabetically.

    Applies fixture log filtering if necessary.

    Parameters
    ----------
    pipeline_dir : Path
        The Path to the pipeline directory containing the build logs.

    Returns
    -------
    list[str]
        A sorted list of build log filenames matching `build_log_*.json`.
    """
    logs = sorted(
        [path.name for path in pipeline_dir.glob("build_log_*.json")],
        reverse=True,
    )

    if (
        _should_filter_fixture_logs(pipeline_dir)
        and len(logs) > 1
        and any(log not in FIXTURE_LOGS for log in logs)
    ):
        logs = [log for log in logs if log not in FIXTURE_LOGS]

    return logs


def _select_build_log(logs: list[str], which_log: str | None, pipeline_dir: Path) -> str:
    """Select a build log file based on a regular expression pattern or latest availability.

    Parameters
    ----------
    logs : list[str]
        A list of available build log filenames.
    which_log : str or None
        An optional regex pattern to filter and select a log file. If None,
        the latest (first in the sorted list) log file is selected.
    pipeline_dir : Path
        The Path to the pipeline directory (used in error messages).

    Returns
    -------
    str
        The selected build log filename.

    Raises
    ------
    FileNotFoundError
        If no logs are available or no logs match the provided pattern.
    ValueError
        If the `which_log` regex pattern is invalid.
    """
    if which_log is None:
        if not logs:
            raise FileNotFoundError(
                f"No build logs found in `{pipeline_dir}`. Build the pipeline first."
            )
        return logs[0]

    _validate_non_empty_string(which_log, "which_log")

    try:
        pattern = re.compile(which_log)
    except re.error as err:
        raise ValueError(f"Invalid regular expression for `which_log`: {err}") from err

    matches = [log for log in logs if pattern.search(log)]
    if not matches:
        raise FileNotFoundError(
            f'No build logs found in `{pipeline_dir}` matching "{which_log}".'
        )

    return matches[0]


def _read_build_log(log_path: Path) -> dict[str, Any]:
    """Read and parse a JSON build log file.

    Parameters
    ----------
    log_path : Path
        The path to the build log file.

    Returns
    -------
    dict[str, Any]
        The parsed JSON content as a dictionary.

    Raises
    ------
    OSError
        If the log file cannot be opened or read.
    ValueError
        If the file content is not valid JSON, or if the root structure is not a dictionary.
    """
    try:
        with log_path.open("r", encoding="utf-8") as handle:
            data = json.load(handle)
    except OSError as err:
        raise OSError(f"Failed to read build log `{log_path.name}`: {err}") from err
    except json.JSONDecodeError as err:
        raise ValueError(f"Failed to read build log `{log_path.name}`: {err}") from err

    if not isinstance(data, dict):
        raise ValueError(f"Build log `{log_path.name}` must decode to an object.")

    return data


def _find_node_entry(nodes: Any, name: str, log_file: str) -> dict[str, Any]:
    """Locate the build log entry for a specific node name.

    Parameters
    ----------
    nodes : Any
        The `nodes` array/list from the build log.
    name : str
        The name of the node to find.
    log_file : str
        The filename of the log (used in error messages).

    Returns
    -------
    dict[str, Any]
        The matching node entry dictionary.

    Raises
    ------
    ValueError
        If the `nodes` parameter is not a list.
    KeyError
        If the node name is not found in the nodes list.
    """
    if not isinstance(nodes, list):
        raise ValueError(f"Build log `{log_file}` does not contain a `nodes` array.")

    for entry in nodes:
        if isinstance(entry, dict) and entry.get("node") == name:
            return entry

    raise KeyError(f"Node `{name}` not found in build log `{log_file}`.")


def _resolve_artifact_path(path_value: Any, pipeline_dir: Path) -> Path:
    """Resolve an artifact path from a build log to an absolute file system path.

    Parameters
    ----------
    path_value : Any
        The raw path value from the build log node entry.
    pipeline_dir : Path
        The Path to the pipeline directory.

    Returns
    -------
    Path
        The resolved absolute path to the artifact.

    Raises
    ------
    ValueError
        If `path_value` is not a valid, non-empty string.
    """
    if not isinstance(path_value, str) or not path_value.strip():
        raise ValueError("Node entry does not contain a valid artifact path.")

    artifact_path = Path(path_value)
    if artifact_path.is_absolute():
        return artifact_path

    return (pipeline_dir.parent / artifact_path).resolve(strict=False)


def deserialize(path: str | Path) -> Any:
    """Deserialize a saved Python object using pickle, dill, or cloudpickle.

    Attempts to load the artifact at the given path, trying multiple serializers
    in order of robustness (pickle -> dill -> cloudpickle) if they are installed.

    Parameters
    ----------
    path : str or Path
        The path to the serialized artifact file.

    Returns
    -------
    Any
        The deserialized Python object.

    Raises
    ------
    RuntimeError
        If all available loaders fail to deserialize the file.
    """
    artifact_path = Path(path)
    loaders: list[tuple[str, Callable[[BinaryIO], Any]]] = [("pickle", pickle.load)]

    try:
        import dill  # type: ignore
    except ImportError:
        pass
    else:
        loaders.append(("dill", dill.load))

    try:
        import cloudpickle  # type: ignore
    except ImportError:
        pass
    else:
        loaders.append(("cloudpickle", cloudpickle.load))

    errors: list[str] = []
    for loader_name, loader in loaders:
        try:
            with artifact_path.open("rb") as handle:
                return loader(handle)
        except Exception as err:  # noqa: BLE001
            errors.append(f"{loader_name}: {type(err).__name__}: {err}")

    raise RuntimeError(
        f"Failed to deserialize `{artifact_path}`. Attempted loaders: "
        + "; ".join(errors)
    )


def _normalize_serializer(value: Any) -> str:
    """Normalize a build-log serializer name for dispatch.

    Strips a leading ``^``, trims whitespace, and lowercases, so ``"^JSON"``
    and ``"json"`` map to ``"json"``. Missing or empty values map to
    ``"default"``.
    """
    if not isinstance(value, str) or not value.strip():
        return "default"
    text = value.strip().lower()
    while text.startswith("^"):
        text = text[1:]
    return text or "default"


def _auto_deserialize(
    serializer: Any, name: str, artifact_path: Path, runtime: Any = None
) -> Any:
    """Deserialize using the serializer recorded in the build log.

    Picks the Python reader from the ``serializer`` field so callers do not
    need to pass ``deserializer`` by hand. Missing packages raise an error
    that names the package and the function to use.
    """
    raw = serializer if isinstance(serializer, str) and serializer.strip() else "default"
    fmt = _normalize_serializer(raw)

    if fmt in {"default", "tlang", "tobj", "serialize", "pickle", "dill", "cloudpickle"}:
        try:
            return deserialize(artifact_path)
        except Exception as err:  # noqa: BLE001
            hint = ""
            if isinstance(runtime, str) and runtime.strip() and runtime.strip() != "Python":
                hint = (
                    f" Node `{name}` was built by runtime `{runtime.strip()}`; "
                    f"pass a custom `deserializer` or use `return_path=True`."
                )
            raise RuntimeError(
                f"Failed to deserialize node `{name}` (serializer `^{fmt}`) "
                f"from `{artifact_path}`: {err}{hint}"
            ) from err

    if fmt == "json":
        try:
            with artifact_path.open("r", encoding="utf-8") as handle:
                return json.load(handle)
        except Exception as err:  # noqa: BLE001
            raise RuntimeError(
                f"Failed to deserialize node `{name}` (serializer `^json`, "
                f"expected stdlib `json.load`) from `{artifact_path}`: {err}"
            ) from err

    if fmt == "csv":
        try:
            import pandas as pd  # type: ignore
        except ImportError as err:
            raise RuntimeError(
                f"Node `{name}` uses serializer `^csv`. Install/load `pandas` "
                f"first, declare it in `tproject.toml`, run `t update`, and "
                f"re-enter `nix develop`. Or pass "
                f"`deserializer=lambda p: pandas.read_csv(p)`."
            ) from err
        try:
            return pd.read_csv(str(artifact_path))
        except Exception as err:  # noqa: BLE001
            raise RuntimeError(
                f"Failed to deserialize node `{name}` (serializer `^csv`, "
                f"expected `pandas.read_csv`) from `{artifact_path}`: {err}"
            ) from err

    if fmt in {"text", "txt"}:
        try:
            # Exact bytes decoded as UTF-8 (no universal-newline translation),
            # matching Julia `read(path, String)` and R.
            return artifact_path.read_bytes().decode("utf-8")
        except Exception as err:  # noqa: BLE001
            raise RuntimeError(
                f"Failed to deserialize node `{name}` (serializer `^text`) "
                f"from `{artifact_path}`: {err}"
            ) from err

    if fmt in {"ipc", "arrow"}:
        try:
            import pandas as pd  # type: ignore
            import pyarrow.ipc as ipc  # type: ignore
        except ImportError as err:
            raise RuntimeError(
                f"Node `{name}` uses serializer `^ipc`. Install `pandas` and "
                f"`pyarrow` first, declare them in `tproject.toml`, run "
                f"`t update`, and re-enter `nix develop`. Or pass a custom "
                f"`deserializer` using `pyarrow.ipc`."
            ) from err
        try:
            with open(artifact_path, "rb") as handle:
                return ipc.open_file(handle).read_pandas()
        except Exception as err:  # noqa: BLE001
            raise RuntimeError(
                f"Failed to deserialize node `{name}` (serializer `^ipc`, "
                f"expected `pyarrow.ipc`) from `{artifact_path}`: {err}"
            ) from err

    if fmt == "parquet":
        try:
            import pandas as pd  # type: ignore
            import pyarrow.parquet as pq  # type: ignore
        except ImportError as err:
            raise RuntimeError(
                f"Node `{name}` uses serializer `^parquet`. Install `pandas` "
                f"and `pyarrow` first, declare them in `tproject.toml`, run "
                f"`t update`, and re-enter `nix develop`. Or pass a custom "
                f"`deserializer` using `pyarrow.parquet`."
            ) from err
        try:
            return pq.read_table(str(artifact_path)).to_pandas()
        except Exception as err:  # noqa: BLE001
            raise RuntimeError(
                f"Failed to deserialize node `{name}` (serializer `^parquet`, "
                f"expected `pyarrow.parquet`) from `{artifact_path}`: {err}"
            ) from err

    if fmt == "pmml":
        raise RuntimeError(
            f"Node `{name}` uses serializer `^pmml`, which has no built-in "
            f"Python reader here. Use `return_path=True` plus a custom "
            f"`deserializer` to inspect the file."
        )

    if fmt == "onnx":
        raise RuntimeError(
            f"Node `{name}` uses serializer `^onnx`, which has no built-in "
            f"Python reader here. Use `return_path=True` plus a custom "
            f"`deserializer` to inspect the file."
        )

    if fmt == "bin":
        raise RuntimeError(
            f"Node `{name}` uses serializer `^bin` (opaque bytes). Use "
            f"`return_path=True` to get the artifact path or pass a custom "
            f"`deserializer`."
        )

    raise RuntimeError(
        f"Node `{name}` uses unknown serializer `{raw}`. Pass a custom "
        f"`deserializer` function or use `return_path=True` to get the "
        f"artifact path."
    )


def _read_node_entry(
    node_entry: dict[str, Any],
    name: str,
    pipeline_dir: Path,
    deserializer: Callable[[str | Path], Any] | None,
    return_path: bool,
) -> Any:
    """Deserialize one already-located build-log node entry.

    Shared by ``read_node()`` and ``read_node_tree()`` so a tree read uses
    the single already-selected build log instead of re-resolving
    ``which_log`` per node.
    """
    artifact_path = _resolve_artifact_path(node_entry.get("path"), pipeline_dir)

    if return_path:
        return str(artifact_path)

    if deserializer is None:
        return _auto_deserialize(
            node_entry.get("serializer", "default"),
            name,
            artifact_path,
            node_entry.get("runtime"),
        )

    try:
        return deserializer(artifact_path)
    except Exception as err:  # noqa: BLE001
        raise RuntimeError(
            f"Failed to deserialize node `{name}` from `{artifact_path}`: {err}"
        ) from err


def read_node(
    name: str,
    which_log: str | None = None,
    pipeline_dir: str | Path = "_pipeline",
    deserializer: Callable[[str | Path], Any] | None = None,
    return_path: bool = False,
) -> Any:
    """Read a node artifact from a built T pipeline.

    When ``which_log`` is ``None``, the helper picks the first
    reverse-alphabetically sorted ``build_log_*.json`` file, which matches T's
    timestamped log naming and therefore resolves to the most recent build.

    When ``deserializer`` is ``None`` (the default), the ``serializer`` field
    from the build log picks the reader automatically (pickle for ``default``,
    stdlib ``json`` for ``^json``, ``pandas.read_csv`` for ``^csv``,
    ``pyarrow`` for ``^ipc``/``^parquet``). Pass a callable to override.

    Parameters
    ----------
    name : str
        The name of the node to retrieve.
    which_log : str or None, optional
        A regular expression pattern used to select a specific build log file by name.
        If None, the most recent build log is used.
    pipeline_dir : str or Path, optional
        The path to the pipeline directory. Defaults to "_pipeline".
    deserializer : Callable[[str | Path], Any] or None, optional
        A callable function to deserialize the node artifact from disk.
        When None, the build-log serializer picks the reader automatically.
    return_path : bool, optional
        If True, return the absolute path to the artifact file instead of deserializing it.
        Defaults to False.

    Returns
    -------
    Any
        The deserialized node artifact, or a string representing the absolute path to the
        artifact file if `return_path` is True.

    Raises
    ------
    ValueError
        If the node `name` or `which_log` regex is invalid, or if the build log structure is invalid.
    TypeError
        If `deserializer` is neither None nor callable.
    FileNotFoundError
        If the pipeline directory, the build log, or matching log cannot be found.
    RuntimeError
        If deserialization of the node fails.
    """
    _validate_non_empty_string(name, "name")
    pipeline_path = _pipeline_path(pipeline_dir)

    if not pipeline_path.is_dir():
        raise FileNotFoundError(f"Pipeline directory `{pipeline_path}` does not exist.")

    if deserializer is not None and not callable(deserializer):
        raise TypeError("`deserializer` must be callable or None.")

    logs = _list_build_logs(pipeline_path)
    log_file = _select_build_log(logs, which_log, pipeline_path)
    build_log = _read_build_log(pipeline_path / log_file)
    node_entry = _find_node_entry(build_log.get("nodes"), name, log_file)

    return _read_node_entry(node_entry, name, pipeline_path, deserializer, return_path)
