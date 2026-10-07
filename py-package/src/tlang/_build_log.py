from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .read_node import _resolve_artifact_path


def _text_or_none(value: Any) -> str | None:
    """Return stripped text or None for missing values."""
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def _verror_from_file(artifact_path: Path) -> dict[str, Any] | None:
    """Parse a VError JSON artifact, or None when it is not one."""
    try:
        with artifact_path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError, UnicodeDecodeError):
        return None
    if not isinstance(payload, dict) or payload.get("type") != "VError":
        return None
    code = payload.get("code")
    message = payload.get("message")
    context = payload.get("context")
    location = payload.get("location")
    return {
        "code": code if isinstance(code, str) and code.strip() else "RuntimeError",
        "message": message if isinstance(message, str) else "Unknown error",
        "context": context if isinstance(context, dict) else None,
        "location": location if isinstance(location, dict) else None,
    }


def _looks_failed(entry: dict[str, Any]) -> bool:
    """Whether the log entry shows failure (or shows nothing at all).

    A `VError`/`Error` class always counts as failed, even when `status`
    says otherwise: T soft errors are values, so a stored error can sit
    beside any status string.
    """
    class_val = entry.get("class")
    if isinstance(class_val, str) and class_val.strip() in {"VError", "Error"}:
        return True
    status = entry.get("status")
    if isinstance(status, str) and status.strip():
        return status.strip() in {"Errored", "SoftFailed"}
    success = entry.get("success")
    if isinstance(success, bool):
        return not success
    if isinstance(success, str) and success.strip():
        return success.strip().lower() != "true"
    return True


def _error_of_entry(
    entry: dict[str, Any], pipeline_path: Path, default_code: str | None = None
) -> dict[str, Any] | None:
    """Build a node error from an already-loaded entry (no log re-read).

    The artifact file is only parsed when the entry shows failure (or shows
    nothing at all); positively successful nodes skip the read, so large
    artifacts are never loaded just to check for errors. ``default_code``
    names the fallback when the entry carries a message but no code.
    """
    if not _looks_failed(entry):
        code = entry.get("error_code")
        message = entry.get("error_message")
        if not (isinstance(code, str) and code.strip()) and not (
            isinstance(message, str) and message.strip()
        ):
            return None
    else:
        try:
            artifact = _resolve_artifact_path(entry.get("path"), pipeline_path)
        except ValueError:
            artifact = None
        if artifact is not None:
            verror = _verror_from_file(artifact)
            if verror is not None:
                return verror
        code = entry.get("error_code")
        message = entry.get("error_message")
    code_text = code if isinstance(code, str) and code.strip() else None
    message_text = message if isinstance(message, str) and message.strip() else None
    if code_text is None and message_text is None:
        return None
    return {
        "code": code_text or default_code or "Error",
        "message": message_text or "",
        "context": None,
        "location": None,
    }


def _warning_rows(
    name: str, entry: dict[str, Any], pipeline_path: Path
) -> list[dict[str, Any]]:
    """Read per-node warning rows from the artifact's `warnings` sidecar.

    The logged path is resolved against ``pipeline_path`` first, so relative
    log paths still find their sidecar.
    """
    warnings_flag = entry.get("warnings")
    if isinstance(warnings_flag, str):
        has_warnings = warnings_flag.strip().lower() == "true"
    else:
        has_warnings = warnings_flag is True
    if not has_warnings:
        return []
    try:
        artifact = _resolve_artifact_path(entry.get("path"), pipeline_path)
    except ValueError:
        return []
    sidecar = artifact.parent / "warnings"
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
