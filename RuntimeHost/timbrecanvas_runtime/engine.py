"""Model-neutral text-to-speech engine boundary."""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Callable, Mapping
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

ProgressCallback = Callable[[float, str], None]
EngineFactory = Callable[[], "TTSEngine"]


@dataclass(frozen=True)
class EngineCapabilities:
    engine_id: str
    display_name: str
    supports_emotion: bool
    supports_speed: bool
    speaker_profile_version: int

    def to_payload(self) -> dict[str, Any]:
        payload = asdict(self)
        return {
            "engineID": payload["engine_id"],
            "displayName": payload["display_name"],
            "supportsEmotion": payload["supports_emotion"],
            "supportsSpeed": payload["supports_speed"],
            "speakerProfileVersion": payload["speaker_profile_version"],
        }


class TTSEngine(ABC):
    @property
    @abstractmethod
    def capabilities(self) -> EngineCapabilities:
        raise NotImplementedError

    @abstractmethod
    def load(self, model_path: str | Path, memory_limit_gb: float = 24.0) -> None:
        raise NotImplementedError

    @abstractmethod
    def extract_voice(
        self, reference_path: str | Path, output_path: str | Path
    ) -> Mapping[str, Any]:
        raise NotImplementedError

    @abstractmethod
    def generate(self, request: Mapping[str, Any], progress: ProgressCallback) -> Mapping[str, Any]:
        raise NotImplementedError

    @abstractmethod
    def cancel(self) -> None:
        raise NotImplementedError

    @abstractmethod
    def shutdown(self) -> None:
        raise NotImplementedError


class EngineRegistry:
    def __init__(self) -> None:
        self._factories: dict[str, EngineFactory] = {}

    @property
    def engine_ids(self) -> tuple[str, ...]:
        return tuple(self._factories)

    def register(self, engine_id: str, factory: EngineFactory) -> None:
        if engine_id in self._factories:
            raise ValueError(f"TTS engine already registered: {engine_id}")
        self._factories[engine_id] = factory

    def create(self, engine_id: str) -> TTSEngine:
        try:
            return self._factories[engine_id]()
        except KeyError as error:
            raise KeyError(f"unknown TTS engine: {engine_id}") from error

    def capabilities(self) -> tuple[EngineCapabilities, ...]:
        return tuple(self.create(engine_id).capabilities for engine_id in self.engine_ids)
