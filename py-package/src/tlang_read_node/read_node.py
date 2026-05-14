from __future__ import annotations

import json
import pickle
import re
from pathlib import Path
from typing import Any, BinaryIO, Callable


FIXTURE_LOGS = {"build_log_ocaml_mock.json", "build_log_legacy_version.json"}


def _validate_non_empty_string(value: str, arg: str) -> None:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"`{arg}` must be a non-empty string.")


def _pipeline_path(pipeline_dir: str | Path) -> Path:
    path = Path(pipeline_dir)
    if not str(path).strip():
        raise ValueError("`pipeline_dir` must be a non-empty path.")
    return path


def _should_filter_fixture_logs(pipeline_dir: Path) -> bool:
    repo_root = pipeline_dir.parent
    return (repo_root / "src" / "pipeline" / "builder_logs.ml").is_file()


def _list_build_logs(pipeline_dir: Path) -> list[str]:
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
    if not isinstance(nodes, list):
        raise ValueError(f"Build log `{log_file}` does not contain a `nodes` array.")

    for entry in nodes:
        if isinstance(entry, dict) and entry.get("node") == name:
            return entry

    raise KeyError(f"Node `{name}` not found in build log `{log_file}`.")


def _resolve_artifact_path(path_value: Any, pipeline_dir: Path) -> Path:
    if not isinstance(path_value, str) or not path_value.strip():
        raise ValueError("Node entry does not contain a valid artifact path.")

    artifact_path = Path(path_value)
    if artifact_path.is_absolute():
        return artifact_path

    return (pipeline_dir.parent / artifact_path).resolve(strict=False)


def deserialize(path: str | Path) -> Any:
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


def read_node(
    name: str,
    which_log: str | None = None,
    pipeline_dir: str | Path = "_pipeline",
    deserializer: Callable[[str | Path], Any] = deserialize,
) -> Any:
    """Read a node artifact from a built T pipeline.

    When ``which_log`` is ``None``, the helper picks the first
    reverse-alphabetically sorted ``build_log_*.json`` file, which matches T's
    timestamped log naming and therefore resolves to the most recent build.
    """

    _validate_non_empty_string(name, "name")
    pipeline_path = _pipeline_path(pipeline_dir)

    if not pipeline_path.is_dir():
        raise FileNotFoundError(f"Pipeline directory `{pipeline_path}` does not exist.")

    if not callable(deserializer):
        raise TypeError("`deserializer` must be callable.")

    logs = _list_build_logs(pipeline_path)
    log_file = _select_build_log(logs, which_log, pipeline_path)
    build_log = _read_build_log(pipeline_path / log_file)
    node_entry = _find_node_entry(build_log.get("nodes"), name, log_file)
    artifact_path = _resolve_artifact_path(node_entry.get("path"), pipeline_path)

    try:
        return deserializer(artifact_path)
    except Exception as err:  # noqa: BLE001
        raise RuntimeError(
            f"Failed to deserialize node `{name}` from `{artifact_path}`: {err}"
        ) from err
