"""Stable JSONL protocol primitives shared by worker commands."""

from __future__ import annotations

import json
from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any


class ProtocolError(ValueError):
    def __init__(self, code: str, message: str, request_id: str | None = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.request_id = request_id


@dataclass(frozen=True)
class Command:
    name: str
    request_id: str
    payload: dict[str, Any]


def parse_command(line: str) -> Command:
    try:
        raw = json.loads(line)
    except (json.JSONDecodeError, TypeError) as error:
        raise ProtocolError("invalid_request", "请求不是有效的 JSON") from error
    if not isinstance(raw, dict):
        raise ProtocolError("invalid_request", "请求必须是 JSON 对象")

    request_id = raw.get("requestID")
    if not isinstance(request_id, str) or not request_id.strip():
        raise ProtocolError("invalid_request", "请求缺少 requestID")
    name = raw.get("command")
    if not isinstance(name, str) or not name.strip():
        raise ProtocolError("invalid_request", "请求缺少 command", request_id)
    payload = raw.get("payload", {})
    if not isinstance(payload, dict):
        raise ProtocolError("invalid_request", "payload 必须是 JSON 对象", request_id)
    return Command(name=name, request_id=request_id, payload=dict(payload))


def encode_event(request_id: str | None, event_type: str, **payload: Any) -> dict[str, Any]:
    event: dict[str, Any] = {"type": event_type, "requestID": request_id}
    event.update(payload)
    return event


def encode_error(request_id: str | None, code: str, message: str) -> dict[str, Any]:
    return encode_event(request_id, "error", code=code, message=message)


def encode_result(request_id: str, **payload: Any) -> dict[str, Any]:
    return encode_event(request_id, "result", **payload)


def write_event(stream, event: Mapping[str, Any]) -> None:
    stream.write(json.dumps(dict(event), ensure_ascii=False, separators=(",", ":")) + "\n")
    stream.flush()
