from dataclasses import dataclass

import pytest

from timbrecanvas_runtime.engine import EngineCapabilities, EngineRegistry, TTSEngine
from timbrecanvas_runtime.indextts2_engine import build_default_registry


@dataclass
class FakeEngine(TTSEngine):
    engine_id: str = "indextts2"

    @property
    def capabilities(self):
        return EngineCapabilities(self.engine_id, "IndexTTS 2", True, True, 1)

    def load(self, model_path, memory_limit_gb=24.0):
        self.loaded = (model_path, memory_limit_gb)

    def extract_voice(self, reference_path, output_path):
        return {"speakerPath": str(output_path)}

    def generate(self, request, progress):
        return {"outputPath": request["outputPath"]}

    def cancel(self):
        return None

    def shutdown(self):
        return None


def test_default_registry_exposes_index_tts_2_through_generic_boundary():
    registry = build_default_registry(FakeEngine)

    assert registry.engine_ids == ("indextts2",)
    assert registry.create("indextts2").capabilities.supports_emotion is True


def test_registry_accepts_an_additional_engine_without_worker_changes():
    registry = EngineRegistry()
    registry.register("another-model", lambda: FakeEngine("another-model"))

    assert registry.create("another-model").capabilities.engine_id == "another-model"


def test_registry_rejects_duplicate_engine_ids():
    registry = EngineRegistry()
    registry.register("indextts2", FakeEngine)

    with pytest.raises(ValueError, match="already registered"):
        registry.register("indextts2", FakeEngine)
