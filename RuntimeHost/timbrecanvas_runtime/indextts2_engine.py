"""IndexTTS 2 adapter for the resident engine boundary."""

from __future__ import annotations

from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any

from .engine import EngineCapabilities, EngineRegistry, ProgressCallback, TTSEngine
from .model_validation import validate_v2_runtime
from .output_paths import allocate_output, finalize_temporary_output, temporary_output


class IndexTTS2Engine(TTSEngine):
    def __init__(self) -> None:
        self._model: Any | None = None
        self._cancel_requested = False

    @property
    def capabilities(self) -> EngineCapabilities:
        return EngineCapabilities("indextts2", "IndexTTS 2", True, True, 1)

    def load(self, model_path: str | Path, memory_limit_gb: float = 24.0) -> None:
        model_dir = Path(model_path).expanduser().resolve()
        validation = validate_v2_runtime(model_dir)
        if not validation.valid:
            raise ValueError(f"IndexTTS 2 模型目录不完整: {validation}")
        from mlx_indextts.generate_v2 import IndexTTSv2

        self._model = IndexTTSv2(str(model_dir), memory_limit_gb=memory_limit_gb)

    def extract_voice(
        self, reference_path: str | Path, output_path: str | Path
    ) -> Mapping[str, Any]:
        model = self._require_model()
        source = Path(reference_path).expanduser().resolve()
        destination = Path(output_path).expanduser().resolve()
        if not source.is_file():
            raise FileNotFoundError(f"参考音频不存在: {source}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        model.save_speaker(str(source), str(destination))
        return {"speakerPath": str(destination), "profileVersion": 1}

    def generate(self, request: Mapping[str, Any], progress: ProgressCallback) -> Mapping[str, Any]:
        model = self._require_model()
        text = str(request.get("text", "")).strip()
        if not text:
            raise ValueError("请输入要合成的文字")
        speaker = Path(str(request.get("speakerPath", ""))).expanduser().resolve()
        requested = Path(str(request.get("outputPath", ""))).expanduser().resolve()
        if not speaker.is_file():
            raise FileNotFoundError(f"音色文件不存在: {speaker}")
        output = allocate_output(requested.parent, requested.name)

        self._cancel_requested = False
        progress(0.05, "preparing")
        if self._cancel_requested:
            raise InterruptedError("生成已取消")
        seed = request.get("seed")
        with temporary_output(output) as partial:
            model.generate(
                text=text,
                reference_audio=str(speaker),
                output_path=str(partial),
                max_mel_tokens=int(request.get("maxMelTokens", 1500)),
                max_text_tokens_per_segment=int(request.get("maxTextTokensPerSegment", 120)),
                interval_silence=int(request.get("intervalSilenceMS", 200)),
                temperature=float(request.get("temperature", 0.8)),
                top_p=float(request.get("topP", 0.8)),
                top_k=int(request.get("topK", 30)),
                repetition_penalty=float(request.get("repetitionPenalty", 10.0)),
                diffusion_steps=int(request.get("diffusionSteps", 25)),
                cfg_rate=float(request.get("cfgRate", 0.7)),
                emotion=request.get("emotion"),
                emo_alpha=float(request.get("emotionStrength", 0.6)),
                speed=float(request.get("speed", 1.0)),
                seed=int(seed) if seed is not None else None,
                segment_overlap_ms=int(request.get("segmentOverlapMS", 50)),
                verbose=False,
            )
            finalize_temporary_output(partial, output)
        progress(1.0, "complete")
        return {"outputPath": str(output), "sampleRate": 22050}

    def cancel(self) -> None:
        self._cancel_requested = True

    def shutdown(self) -> None:
        self._model = None

    def _require_model(self) -> Any:
        if self._model is None:
            raise RuntimeError("IndexTTS 2 模型尚未加载")
        return self._model


def build_default_registry(
    indextts2_factory: Callable[[], TTSEngine] = IndexTTS2Engine,
) -> EngineRegistry:
    registry = EngineRegistry()
    registry.register("indextts2", indextts2_factory)
    return registry
