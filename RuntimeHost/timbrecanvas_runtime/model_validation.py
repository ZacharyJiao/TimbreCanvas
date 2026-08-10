"""Validate external IndexTTS 2 assets without importing the model package."""

from dataclasses import dataclass
from pathlib import Path

REQUIRED_V2_FILES = (
    "bigvgan.safetensors",
    "config.json",
    "config.yaml",
    "feat1.pt",
    "feat2.pt",
    "gpt.safetensors",
    "s2mel.safetensors",
    "tokenizer.model",
    "vq2emb.safetensors",
    "wav2vec2bert_stats.pt",
)


@dataclass(frozen=True)
class RuntimeValidationResult:
    valid: bool
    missing: tuple[str, ...]
    forbidden: tuple[str, ...]


def validate_v2_runtime(model_dir: str | Path) -> RuntimeValidationResult:
    directory = Path(model_dir)
    missing = tuple(name for name in REQUIRED_V2_FILES if not (directory / name).is_file())
    forbidden = (
        tuple(
            sorted(
                path.name
                for path in directory.iterdir()
                if "1.5" in path.name.lower() or "v15" in path.name.lower()
            )
        )
        if directory.is_dir()
        else ()
    )
    return RuntimeValidationResult(
        valid=not missing and not forbidden,
        missing=missing,
        forbidden=forbidden,
    )
