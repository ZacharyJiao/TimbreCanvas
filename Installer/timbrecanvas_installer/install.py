"""Portable installation primitives with no user-specific defaults."""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
import urllib.request
from argparse import ArgumentParser
from datetime import UTC, datetime
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class AssetManifest:
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

    mlx_port: dict[str, Any]
    models: list[dict[str, Any]]
    converted_model_files: list[dict[str, str]]
    runtime_license_files: list[dict[str, str]]
    voices: list[dict[str, str]]

    @classmethod
    def load(cls, path: Path) -> "AssetManifest":
        payload = json.loads(path.read_text(encoding="utf-8"))
        if payload.get("schemaVersion") != 1:
            raise ValueError("unsupported asset manifest schema")
        return cls(
            mlx_port=payload["mlxPort"],
            models=payload["models"],
            converted_model_files=payload["convertedModelFiles"],
            runtime_license_files=payload["runtimeLicenseFiles"],
            voices=payload["voices"],
        )


@dataclass(frozen=True)
class ExistingRuntime:
    python: Path
    model: Path
    voices: Path
    presets: Path
    cache: Path

    @classmethod
    def from_project(cls, project: Path) -> "ExistingRuntime":
        root = project.expanduser().resolve()
        return cls(
            python=root / ".venv/bin/python",
            model=root / "runtime/models/IndexTTS-2-MLX-8bit",
            voices=root / "runtime/voices",
            presets=root / "runtime/presets",
            cache=root / "runtime/cache",
        )

    @classmethod
    def for_install_root(cls, install_root: Path) -> "ExistingRuntime":
        root = install_root.expanduser().resolve()
        return cls(
            python=root / "Runtime/.venv/bin/python",
            model=root / "Models/IndexTTS-2-MLX-8bit",
            voices=root / "Voices",
            presets=root / "Presets",
            cache=root / "Cache",
        )


def build_app_configuration(runtime: ExistingRuntime) -> dict[str, str | int]:
    return {
        "schemaVersion": 1,
        "pythonPath": str(runtime.python),
        "modelPath": str(runtime.model),
        "voiceRoot": str(runtime.voices),
        "presetRoot": str(runtime.presets),
        "cacheRoot": str(runtime.cache),
    }


def validate_existing_runtime(runtime: ExistingRuntime) -> None:
    if not runtime.python.is_file() or not os.access(runtime.python, os.X_OK):
        raise ValueError(
            f"Python runtime is missing or not executable: {runtime.python}"
        )
    missing = [
        name
        for name in AssetManifest.REQUIRED_V2_FILES
        if not (runtime.model / name).is_file()
    ]
    if missing:
        raise ValueError(
            f"IndexTTS 2 model is incomplete; missing: {', '.join(missing)}"
        )
    legacy = sorted(
        path.name
        for path in runtime.model.rglob("*")
        if "1.5" in path.name.casefold() or "v15" in path.name.casefold()
    )
    if legacy:
        raise ValueError(
            f"IndexTTS 1.5 artifacts are not supported: {', '.join(legacy)}"
        )


def verify_file_hashes(root: Path, entries: list[dict[str, str]]) -> None:
    failures: list[str] = []
    for entry in entries:
        path = root / entry["path"]
        if not path.is_file():
            failures.append(f"{entry['path']} (missing)")
            continue
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != entry["sha256"]:
            failures.append(f"{entry['path']} (SHA-256 mismatch)")
    if failures:
        raise ValueError("asset verification failed: " + ", ".join(failures))


def install_runtime_license_files(
    source_root: Path,
    destination_root: Path,
    entries: list[dict[str, str]],
) -> None:
    source_root = source_root.resolve()
    destination_root = destination_root.resolve()
    verified: list[tuple[Path, bytes]] = []
    for entry in entries:
        source = (source_root / entry["source"]).resolve()
        destination = (destination_root / entry["path"]).resolve()
        source.relative_to(source_root)
        destination.relative_to(destination_root)
        contents = source.read_bytes()
        if hashlib.sha256(contents).hexdigest() != entry["sha256"]:
            raise ValueError(
                f"asset verification failed: {entry['source']} (SHA-256 mismatch)"
            )
        verified.append((destination, contents))

    staged: list[tuple[Path, Path]] = []
    try:
        for destination, contents in verified:
            destination.parent.mkdir(parents=True, exist_ok=True)
            descriptor, temporary_name = tempfile.mkstemp(
                prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent
            )
            temporary = Path(temporary_name)
            staged.append((temporary, destination))
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(contents)
                stream.flush()
                os.fsync(stream.fileno())
        for temporary, destination in staged:
            os.replace(temporary, destination)
    finally:
        for temporary, _ in staged:
            temporary.unlink(missing_ok=True)
    verify_file_hashes(destination_root, entries)


def _validate_voice_profiles(profiles: list[Any]) -> None:
    string_fields = (
        "id",
        "engineID",
        "name",
        "kind",
        "referencePath",
        "speakerPath",
        "createdAt",
        "note",
    )
    identifiers: set[str] = set()
    for index, profile in enumerate(profiles):
        if not isinstance(profile, dict):
            raise ValueError(f"voice profile {index} must be an object")
        for field in string_fields:
            if not isinstance(profile.get(field), str):
                raise ValueError(f"voice profile {index} has invalid {field}")
        for field in (
            "id",
            "engineID",
            "name",
            "referencePath",
            "speakerPath",
            "createdAt",
        ):
            if not profile[field]:
                raise ValueError(f"voice profile {index} has empty {field}")
        version = profile.get("profileVersion")
        if isinstance(version, bool) or not isinstance(version, int) or version < 1:
            raise ValueError(f"voice profile {index} has invalid profileVersion")
        if profile["kind"] not in {"builtIn", "custom"}:
            raise ValueError(f"voice profile {index} has invalid kind")
        if profile["kind"] == "custom" and profile["id"].startswith("builtin-"):
            raise ValueError(
                f"voice profile {index} uses the reserved built-in id namespace"
            )
        if profile["id"] in identifiers:
            raise ValueError(f"voice manifest contains duplicate id: {profile['id']}")
        identifiers.add(profile["id"])


def write_app_configuration(support_root: Path, runtime: ExistingRuntime) -> Path:
    support_root.mkdir(parents=True, exist_ok=True)
    destination = support_root / "config.json"
    encoded = (
        json.dumps(
            build_app_configuration(runtime),
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".config.", suffix=".tmp", dir=support_root
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)
    return destination


def _download_models(manifest: AssetManifest, runtime: ExistingRuntime) -> Path:
    from huggingface_hub import snapshot_download

    downloads = runtime.cache / "downloads"
    hugging_face_cache = runtime.cache / "huggingface/hub"
    downloads.mkdir(parents=True, exist_ok=True)
    source_model: Path | None = None

    for model in manifest.models:
        local_directory = model.get("localDirectory")
        snapshot = Path(
            snapshot_download(
                repo_id=model["repository"],
                revision=model["revision"],
                allow_patterns=model.get("allowPatterns"),
                cache_dir=hugging_face_cache,
                local_dir=downloads / local_directory if local_directory else None,
            )
        )
        if local_directory:
            source_model = snapshot
        else:
            repository_cache = snapshot.parent.parent
            refs = repository_cache / "refs"
            refs.mkdir(parents=True, exist_ok=True)
            (refs / "main").write_text(model["revision"] + "\n", encoding="utf-8")

    if source_model is None:
        raise ValueError("asset manifest does not define an IndexTTS 2 source model")
    return source_model


def _convert_model(
    manifest: AssetManifest,
    runtime: ExistingRuntime,
    source_model: Path,
) -> None:
    runtime.model.parent.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment.update(
        {
            "HF_HOME": str(runtime.cache / "huggingface"),
            "HF_HUB_CACHE": str(runtime.cache / "huggingface/hub"),
            "HF_HUB_OFFLINE": "1",
            "HF_HUB_DISABLE_XET": "1",
        }
    )
    subprocess.run(
        [
            str(runtime.python),
            "-m",
            "mlx_indextts.cli",
            "convert",
            "--model-dir",
            str(source_model),
            "--output",
            str(runtime.model),
            "--quantize",
            "8",
        ],
        check=True,
        env=environment,
    )
    verify_file_hashes(runtime.model, manifest.converted_model_files)


def _download_builtin_voices(manifest: AssetManifest, runtime: ExistingRuntime) -> None:
    built_in = runtime.voices / "builtin"
    built_in.mkdir(parents=True, exist_ok=True)
    for voice in manifest.voices:
        destination = built_in / voice["name"]
        with tempfile.NamedTemporaryFile(dir=built_in, delete=False) as temporary:
            temporary_path = Path(temporary.name)
        try:
            request = urllib.request.Request(
                voice["url"], headers={"User-Agent": "TimbreCanvas/0.1"}
            )
            with urllib.request.urlopen(request, timeout=180) as response:
                with temporary_path.open("wb") as output:
                    while chunk := response.read(1024 * 1024):
                        output.write(chunk)
            verify_file_hashes(
                built_in,
                [{"path": temporary_path.name, "sha256": voice["sha256"]}],
            )
            os.replace(temporary_path, destination)
        finally:
            temporary_path.unlink(missing_ok=True)


def _precompute_builtin_voices(runtime: ExistingRuntime) -> None:
    from mlx_indextts.generate_v2 import IndexTTSv2

    model = IndexTTSv2(str(runtime.model), memory_limit_gb=24.0)
    for reference in sorted((runtime.voices / "builtin").glob("voice_*.wav")):
        model.save_speaker(str(reference), str(reference.with_suffix(".npz")))


def _write_voice_manifest(runtime: ExistingRuntime) -> None:
    manifest_path = runtime.voices / "voices.json"
    existing_profiles: list[dict[str, Any]] = []
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("schemaVersion") != 1 or not isinstance(
            manifest.get("profiles"), list
        ):
            raise ValueError("unsupported voice manifest schema")
        existing_profiles = manifest["profiles"]
        _validate_voice_profiles(existing_profiles)
    existing_by_id = {
        profile.get("id"): profile
        for profile in existing_profiles
        if isinstance(profile, dict) and isinstance(profile.get("id"), str)
    }
    profiles = []
    for reference in sorted((runtime.voices / "builtin").glob("voice_*.wav")):
        suffix = reference.stem.removeprefix("voice_")
        identifier = f"builtin-{reference.stem}"
        existing = existing_by_id.get(identifier, {})
        profiles.append(
            {
                "id": identifier,
                "engineID": "indextts2",
                "profileVersion": 1,
                "name": existing.get("name", f"官方示例 {suffix}"),
                "kind": "builtIn",
                "referencePath": str(reference),
                "speakerPath": str(reference.with_suffix(".npz")),
                "createdAt": existing.get(
                    "createdAt",
                    datetime.now(UTC)
                    .replace(microsecond=0)
                    .isoformat()
                    .replace("+00:00", "Z"),
                ),
                "note": "IndexTTS 2 官方示例",
            }
        )
    profiles.extend(
        profile
        for profile in existing_profiles
        if isinstance(profile, dict) and profile.get("kind") == "custom"
    )
    _validate_voice_profiles(profiles)
    (runtime.voices / "custom").mkdir(parents=True, exist_ok=True)
    (runtime.presets).mkdir(parents=True, exist_ok=True)
    encoded = (
        json.dumps(
            {"schemaVersion": 1, "profiles": profiles},
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".voices.", suffix=".tmp", dir=runtime.voices
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, manifest_path)
    finally:
        temporary.unlink(missing_ok=True)


def perform_fresh_install(
    manifest_path: Path,
    install_root: Path,
    support_root: Path,
) -> ExistingRuntime:
    manifest = AssetManifest.load(manifest_path)
    runtime = ExistingRuntime.for_install_root(install_root)
    if not runtime.python.is_file():
        raise ValueError(f"Python runtime is missing: {runtime.python}")
    source_model = _download_models(manifest, runtime)
    _convert_model(manifest, runtime, source_model)
    install_runtime_license_files(
        manifest_path.parent,
        runtime.model,
        manifest.runtime_license_files,
    )
    _download_builtin_voices(manifest, runtime)
    _precompute_builtin_voices(runtime)
    _write_voice_manifest(runtime)
    validate_existing_runtime(runtime)
    write_app_configuration(support_root, runtime)
    return runtime


def main() -> int:
    parser = ArgumentParser(description="Configure TimbreCanvas external runtime")
    subparsers = parser.add_subparsers(dest="command", required=True)

    existing = subparsers.add_parser("configure-existing")
    existing.add_argument("--project", type=Path, required=True)
    existing.add_argument("--support-root", type=Path, required=True)
    existing.add_argument("--manifest", type=Path, required=True)

    fresh = subparsers.add_parser("fresh-install")
    fresh.add_argument("--install-root", type=Path, required=True)
    fresh.add_argument("--support-root", type=Path, required=True)
    fresh.add_argument("--manifest", type=Path, required=True)

    arguments = parser.parse_args()
    if arguments.command == "configure-existing":
        manifest = AssetManifest.load(arguments.manifest)
        runtime = ExistingRuntime.from_project(arguments.project)
        validate_existing_runtime(runtime)
        verify_file_hashes(runtime.model, manifest.converted_model_files)
        install_runtime_license_files(
            arguments.manifest.parent,
            runtime.model,
            manifest.runtime_license_files,
        )
        write_app_configuration(arguments.support_root, runtime)
    else:
        perform_fresh_install(
            arguments.manifest,
            arguments.install_root,
            arguments.support_root,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
