"""Collision-free and atomic WAV output helpers."""

from __future__ import annotations

import os
import re
import unicodedata
import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

_INVALID_FILENAME = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
_PARTIAL_TOKEN = re.compile(
    r"\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z"
)


def sanitize_filename(filename: str, fallback: str = "未命名.wav") -> str:
    normalized = unicodedata.normalize("NFKC", filename).strip()
    normalized = _INVALID_FILENAME.sub("", normalized)
    if normalized.casefold() == ".wav":
        return fallback
    normalized = normalized.lstrip(". ").rstrip(". ")
    stem = Path(normalized).stem.strip(". ")
    return f"{stem}.wav" if stem else fallback


def allocate_output(directory: str | Path, requested_name: str) -> Path:
    output_dir = Path(directory).expanduser().resolve()
    if not output_dir.is_dir():
        raise FileNotFoundError(f"导出目录不存在: {output_dir}")
    candidate = output_dir / sanitize_filename(requested_name)
    if not candidate.exists():
        return candidate
    stem = candidate.stem
    for index in range(2, 100_000):
        candidate = output_dir / f"{stem}-{index}.wav"
        if not candidate.exists():
            return candidate
    raise FileExistsError("导出目录中存在过多同名文件")


@contextmanager
def temporary_output(
    destination: str | Path,
    *,
    partial_token: str | None = None,
) -> Iterator[Path]:
    final_path = Path(destination).expanduser().resolve()
    token = partial_token or str(uuid.uuid4())
    if not _PARTIAL_TOKEN.fullmatch(token):
        raise ValueError("invalid partial output token")
    partial = final_path.parent / f".timbrecanvas.{token}.partial.wav"
    try:
        yield partial
    finally:
        partial.unlink(missing_ok=True)


def finalize_temporary_output(temporary: str | Path, destination: str | Path) -> None:
    source = Path(temporary)
    final_path = Path(destination)
    if not source.is_file():
        raise FileNotFoundError(f"临时音频不存在: {source}")
    os.replace(source, final_path)
