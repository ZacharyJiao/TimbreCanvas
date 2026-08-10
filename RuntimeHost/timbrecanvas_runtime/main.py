"""Long-lived TimbreCanvas worker speaking JSONL over stdin/stdout."""

from __future__ import annotations

import contextlib
import os
import sys
import traceback
from dataclasses import dataclass
from typing import Any, TextIO

from .engine import EngineRegistry, TTSEngine
from .indextts2_engine import build_default_registry
from .protocol import (
    Command,
    ProtocolError,
    encode_error,
    encode_event,
    encode_result,
    parse_command,
    write_event,
)


@dataclass
class WorkerRuntime:
    registry: EngineRegistry
    engine: TTSEngine | None = None
    engine_id: str | None = None

    def dispatch(self, command: Command, output: TextIO) -> tuple[dict[str, Any], bool]:
        payload = command.payload
        if command.name == "ping":
            return encode_result(command.request_id, status="pong", processID=os.getpid()), False
        if command.name == "list_engines":
            engines = [capability.to_payload() for capability in self.registry.capabilities()]
            return encode_result(command.request_id, engines=engines), False
        if command.name == "load_model":
            engine_id = str(payload.get("engineID", "indextts2"))
            if self.engine is not None:
                self.engine.shutdown()
            self.engine = self.registry.create(engine_id)
            self.engine_id = engine_id
            self.engine.load(
                payload.get("modelPath", ""),
                float(payload.get("memoryLimitGB", 24.0)),
            )
            return encode_event(command.request_id, "ready", engineID=engine_id), False
        if command.name == "extract_voice":
            result = self._require_engine().extract_voice(
                payload.get("referencePath", ""), payload.get("outputPath", "")
            )
            return encode_result(command.request_id, **dict(result)), False
        if command.name == "generate":
            engine = self._require_engine()

            def progress(value: float, stage: str) -> None:
                write_event(
                    output,
                    encode_event(
                        command.request_id,
                        "progress",
                        progress=value,
                        stage=stage,
                    ),
                )

            result = encode_result(
                command.request_id,
                **dict(engine.generate(payload, progress)),
            )
            return result, False
        if command.name == "shutdown":
            if self.engine is not None:
                self.engine.shutdown()
            return encode_result(command.request_id, shutdown=True), True
        raise ProtocolError("unknown_command", f"不支持的命令: {command.name}", command.request_id)

    def _require_engine(self) -> TTSEngine:
        if self.engine is None:
            raise ProtocolError("model_not_loaded", "模型尚未加载")
        return self.engine


def run_worker(
    input_stream: TextIO = sys.stdin,
    output_stream: TextIO = sys.stdout,
    diagnostic_stream: TextIO = sys.stderr,
    registry: EngineRegistry | None = None,
) -> int:
    runtime = WorkerRuntime(registry or build_default_registry())
    for line in input_stream:
        if not line.strip():
            continue
        command: Command | None = None
        try:
            command = parse_command(line)
            with contextlib.redirect_stdout(diagnostic_stream):
                response, should_stop = runtime.dispatch(command, output_stream)
            write_event(output_stream, response)
            if should_stop:
                return 0
        except ProtocolError as error:
            write_event(output_stream, encode_error(error.request_id, error.code, error.message))
        except FileNotFoundError as error:
            write_event(
                output_stream,
                encode_error(
                    command.request_id if command else None,
                    "file_not_found",
                    str(error),
                ),
            )
        except InterruptedError as error:
            write_event(
                output_stream,
                encode_error(
                    command.request_id if command else None,
                    "cancelled",
                    str(error),
                ),
            )
        except Exception as error:
            traceback.print_exc(file=diagnostic_stream)
            write_event(
                output_stream,
                encode_error(
                    command.request_id if command else None,
                    "engine_error",
                    str(error),
                ),
            )
    return 0


def main() -> None:
    raise SystemExit(run_worker())


if __name__ == "__main__":
    main()
