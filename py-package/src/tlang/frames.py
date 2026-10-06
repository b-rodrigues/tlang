from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any

from .read_node import (
    _list_build_logs,
    _pipeline_path,
    _read_build_log,
    _select_build_log,
    _validate_non_empty_string,
)


def _clean_message(message: Any) -> str:
    """Keep the last non-empty line, truncated like T (max 100 chars)."""
    if not isinstance(message, str):
        return ""
    lines = [line.strip() for line in message.splitlines()]
    lines = [line for line in lines if line]
    last = lines[-1] if lines else ""
    if len(last) > 100:
        return last[:97] + "..."
    return last


def _status_of(entry: dict[str, Any]) -> str | None:
    """Derive a display status, mirroring the build-log reader."""
    status = entry.get("status")
    if isinstance(status, str) and status.strip():
        return status.strip()
    success = entry.get("success")
    if isinstance(success, bool):
        return "Completed" if success else "SoftFailed"
    if isinstance(success, str) and success.strip():
        return "Completed" if success.strip().lower() == "true" else "SoftFailed"
    return None


def _duration_of(entry: dict[str, Any]) -> float | None:
    """Parse a duration value to float, or None when absent."""
    duration = entry.get("duration")
    if isinstance(duration, bool):
        return None
    if isinstance(duration, (int, float)):
        return float(duration)
    if isinstance(duration, str) and duration.strip():
        try:
            return float(duration.strip())
        except ValueError:
            return None
    return None


def _warning_rows(name: str, entry: dict[str, Any]) -> list[dict[str, Any]]:
    """Read per-node warning rows from the artifact's `warnings` sidecar."""
    warnings_flag = entry.get("warnings")
    if isinstance(warnings_flag, str):
        has_warnings = warnings_flag.strip().lower() == "true"
    else:
        has_warnings = bool(warnings_flag) if isinstance(warnings_flag, bool) else False
    if not has_warnings:
        return []
    path = entry.get("path")
    if not isinstance(path, str) or not path.strip():
        return []
    sidecar = Path(path).parent / "warnings"
    try:
        items = json.loads(sidecar.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeDecodeError):
        return []
    if not isinstance(items, list):
        return []
    rows: list[dict[str, Any]] = []
    for item in items:
        if isinstance(item, str):
            rows.append({"node": name, "status": "Warning", "code": "Generic", "message": item})
        elif isinstance(item, dict):
            kind = item.get("kind")
            rows.append(
                {
                    "node": name,
                    "status": "Warning",
                    "code": kind if isinstance(kind, str) and kind.strip() else "Generic",
                    "message": item.get("message") if isinstance(item.get("message"), str) else "",
                }
            )
    return rows


def list_logs(pipeline_dir: str | Path = "_pipeline") -> list[dict[str, Any]]:
    """List build logs in the pipeline directory, newest first.

    Returns one dict per ``build_log_*.json`` file with ``filename``,
    ``modification_time`` (``%Y-%m-%d %H:%M:%S`` local time), ``size_kb``
    (rounded to 2 decimals), and ``pipeline`` (the log's pipeline name or
    None). Mirrors T's ``list_logs()``.
    """
    pipeline_path = _pipeline_path(pipeline_dir)
    if not pipeline_path.is_dir():
        raise FileNotFoundError(f"Pipeline directory `{pipeline_path}` does not exist.")
    rows: list[dict[str, Any]] = []
    for name in _list_build_logs(pipeline_path):
        full = pipeline_path / name
        try:
            stat = full.stat()
        except OSError:
            continue
        try:
            with full.open("r", encoding="utf-8") as handle:
                logged = json.load(handle)
            pipeline = logged.get("pipeline") if isinstance(logged, dict) else None
        except (OSError, ValueError, UnicodeDecodeError):
            pipeline = None
        rows.append(
            {
                "filename": name,
                "modification_time": datetime.fromtimestamp(stat.st_mtime).strftime(
                    "%Y-%m-%d %H:%M:%S"
                ),
                "size_kb": round(stat.st_size / 1024.0, 2),
                "pipeline": pipeline if isinstance(pipeline, str) else None,
            }
        )
    return rows


def build_log_to_frame(
    which_log: str | None = None,
    pipeline_dir: str | Path = "_pipeline",
) -> list[dict[str, Any]]:
    """Tabulate one build log as per-node rows.

    Each row has ``name``, ``status``, ``duration`` (float or None), and
    ``path`` (the raw logged path). Mirrors T's ``build_log_to_frame()``.
    """
    pipeline_path = _pipeline_path(pipeline_dir)
    if not pipeline_path.is_dir():
        raise FileNotFoundError(f"Pipeline directory `{pipeline_path}` does not exist.")
    logs = _list_build_logs(pipeline_path)
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
        path = entry.get("path")
        rows.append(
            {
                "name": name,
                "status": _status_of(entry),
                "duration": _duration_of(entry),
                "path": path if isinstance(path, str) else None,
            }
        )
    return rows


def collect_exceptions(
    which_log: str | None = None,
    pipeline_dir: str | Path = "_pipeline",
) -> list[dict[str, Any]]:
    """Gather error and warning rows from one build log.

    Each row has ``node``, ``status`` (``Error``/``Warning``), ``code``, and
    ``message``. Error rows come from ``Errored`` nodes (``error_code``/
    ``error_message`` fields) and soft-failed nodes. Warning rows come from
    the per-artifact ``warnings`` sidecar. Mirrors T's
    ``collect_exceptions()``.
    """
    pipeline_path = _pipeline_path(pipeline_dir)
    if not pipeline_path.is_dir():
        raise FileNotFoundError(f"Pipeline directory `{pipeline_path}` does not exist.")
    logs = _list_build_logs(pipeline_path)
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
        status = _status_of(entry)
        class_val = entry.get("class")
        class_val = class_val if isinstance(class_val, str) else ""
        if status == "Errored":
            code = entry.get("error_code")
            rows.append(
                {
                    "node": name,
                    "status": "Error",
                    "code": code if isinstance(code, str) and code.strip() else "NixError",
                    "message": _clean_message(entry.get("error_message"))
                    or "Nix build failed.",
                }
            )
        elif status == "SoftFailed" or class_val in {"VError", "Error"}:
            code = entry.get("error_code")
            message = entry.get("error_message")
            rows.append(
                {
                    "node": name,
                    "status": "Error",
                    "code": (
                        code
                        if isinstance(code, str) and code.strip()
                        else (class_val or "Error")
                    ),
                    "message": _clean_message(message)
                    or "Node failed with a soft error.",
                }
            )
        rows.extend(_warning_rows(name, entry))
    return rows
