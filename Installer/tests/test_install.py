import json
from pathlib import Path

import pytest

from timbrecanvas_installer.install import (
    AssetManifest,
    ExistingRuntime,
    build_app_configuration,
    validate_existing_runtime,
    verify_file_hashes,
)


def test_manifest_pins_every_network_source_and_converted_model_hash():
    manifest = AssetManifest.load(Path("Installer/runtime-assets.json"))

    assert manifest.mlx_port["revision"] == "1026564f418e633e885df349e42ccf31a0ea9884"
    assert len(manifest.models) == 5
    assert all(len(model["revision"]) == 40 for model in manifest.models)
    assert len(manifest.converted_model_files) == 10
    assert all(len(item["sha256"]) == 64 for item in manifest.converted_model_files)
    assert all("/resolve/" in voice["url"] for voice in manifest.voices)


def test_existing_runtime_configuration_contains_only_selected_paths(tmp_path):
    runtime = ExistingRuntime(
        python=tmp_path / "Runtime/.venv/bin/python",
        model=tmp_path / "Models/IndexTTS-2-MLX-8bit",
        voices=tmp_path / "Voices",
        presets=tmp_path / "Presets",
        cache=tmp_path / "Cache",
    )

    configuration = build_app_configuration(runtime)

    assert configuration == {
        "schemaVersion": 1,
        "pythonPath": str(runtime.python),
        "modelPath": str(runtime.model),
        "voiceRoot": str(runtime.voices),
        "presetRoot": str(runtime.presets),
        "cacheRoot": str(runtime.cache),
    }
    assert str(Path.home()) not in json.dumps(configuration)


def test_existing_runtime_rejects_legacy_index_tts_15_artifacts(tmp_path):
    runtime = ExistingRuntime.from_project(tmp_path)
    runtime.python.parent.mkdir(parents=True)
    runtime.python.touch(mode=0o755)
    runtime.model.mkdir(parents=True)
    for name in AssetManifest.REQUIRED_V2_FILES:
        (runtime.model / name).touch()
    (runtime.model / "legacy-v1.5.ckpt").touch()

    with pytest.raises(ValueError, match="1.5"):
        validate_existing_runtime(runtime)


def test_hash_verification_reports_changed_assets(tmp_path):
    asset = tmp_path / "asset.bin"
    asset.write_bytes(b"expected")

    with pytest.raises(ValueError, match="asset.bin"):
        verify_file_hashes(tmp_path, [{"path": "asset.bin", "sha256": "0" * 64}])


def test_runtime_security_overlay_excludes_test_only_packages():
    overlay = Path("Installer/security-overrides.txt").read_text(encoding="utf-8")

    assert "pytest==" not in overlay
