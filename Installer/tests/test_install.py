import hashlib
import json
from pathlib import Path

import pytest
import timbrecanvas_installer.install as installer

from timbrecanvas_installer.install import (
    AssetManifest,
    ExistingRuntime,
    _write_voice_manifest,
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
    assert len(manifest.runtime_license_files) == 3
    assert all(len(item["sha256"]) == 64 for item in manifest.runtime_license_files)
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
    assert "torch==2.13.0" in overlay
    assert "torchaudio==2.11.0" in overlay


def test_voice_manifest_refresh_preserves_user_profiles_and_aliases(tmp_path):
    runtime = ExistingRuntime.for_install_root(tmp_path / "install")
    built_in = runtime.voices / "builtin"
    built_in.mkdir(parents=True)
    (built_in / "voice_01.wav").touch()
    (built_in / "voice_01.npz").touch()
    custom = runtime.voices / "custom"
    custom.mkdir()
    manifest = runtime.voices / "voices.json"
    manifest.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "profiles": [
                    {
                        "id": "builtin-voice_01",
                        "engineID": "indextts2",
                        "profileVersion": 1,
                        "name": "我的默认旁白",
                        "kind": "builtIn",
                        "referencePath": str(built_in / "voice_01.wav"),
                        "speakerPath": str(built_in / "voice_01.npz"),
                        "createdAt": "2026-01-01T00:00:00Z",
                        "note": "IndexTTS 2 官方示例",
                    },
                    {
                        "id": "custom-narrator",
                        "engineID": "indextts2",
                        "profileVersion": 1,
                        "name": "合成测试音色",
                        "kind": "custom",
                        "referencePath": str(custom / "custom-narrator.wav"),
                        "speakerPath": str(custom / "custom-narrator.npz"),
                        "createdAt": "2026-01-02T00:00:00Z",
                        "note": "synthetic fixture",
                    },
                ],
            }
        ),
        encoding="utf-8",
    )

    _write_voice_manifest(runtime)

    profiles = json.loads(manifest.read_text(encoding="utf-8"))["profiles"]
    assert [profile["id"] for profile in profiles] == [
        "builtin-voice_01",
        "custom-narrator",
    ]
    assert profiles[0]["name"] == "我的默认旁白"
    assert profiles[1]["referencePath"] == str(custom / "custom-narrator.wav")


def test_voice_manifest_refresh_does_not_replace_corrupt_manifest(tmp_path):
    runtime = ExistingRuntime.for_install_root(tmp_path / "install")
    runtime.voices.mkdir(parents=True)
    manifest = runtime.voices / "voices.json"
    original = b"{not valid json\n"
    manifest.write_bytes(original)

    with pytest.raises(json.JSONDecodeError):
        _write_voice_manifest(runtime)

    assert manifest.read_bytes() == original


@pytest.mark.parametrize(
    ("change", "match"),
    [
        ({"kind": "unknown"}, "kind"),
        ({"profileVersion": "1"}, "profileVersion"),
        ({"engineID": None}, "engineID"),
    ],
)
def test_voice_manifest_refresh_rejects_semantically_invalid_profiles(
    tmp_path, change, match
):
    runtime = ExistingRuntime.for_install_root(tmp_path / "install")
    runtime.voices.mkdir(parents=True)
    profile = {
        "id": "custom-fixture",
        "engineID": "indextts2",
        "profileVersion": 1,
        "name": "Synthetic Fixture",
        "kind": "custom",
        "referencePath": "~/synthetic.wav",
        "speakerPath": "~/synthetic.npz",
        "createdAt": "2026-01-01T00:00:00Z",
        "note": "",
    }
    profile.update(change)
    manifest = runtime.voices / "voices.json"
    original = json.dumps({"schemaVersion": 1, "profiles": [profile]}).encode()
    manifest.write_bytes(original)

    with pytest.raises(ValueError, match=match):
        _write_voice_manifest(runtime)

    assert manifest.read_bytes() == original


def test_voice_manifest_refresh_rejects_duplicate_ids_without_replacing_file(tmp_path):
    runtime = ExistingRuntime.for_install_root(tmp_path / "install")
    runtime.voices.mkdir(parents=True)
    profile = {
        "id": "custom-duplicate",
        "engineID": "indextts2",
        "profileVersion": 1,
        "name": "Synthetic Fixture",
        "kind": "custom",
        "referencePath": "~/synthetic.wav",
        "speakerPath": "~/synthetic.npz",
        "createdAt": "2026-01-01T00:00:00Z",
        "note": "",
    }
    manifest = runtime.voices / "voices.json"
    original = json.dumps(
        {"schemaVersion": 1, "profiles": [profile, profile]}
    ).encode()
    manifest.write_bytes(original)

    with pytest.raises(ValueError, match="duplicate"):
        _write_voice_manifest(runtime)

    assert manifest.read_bytes() == original


def test_voice_manifest_refresh_rejects_missing_fields_without_replacing_file(tmp_path):
    runtime = ExistingRuntime.for_install_root(tmp_path / "install")
    runtime.voices.mkdir(parents=True)
    profile = {
        "id": "custom-missing-field",
        "engineID": "indextts2",
        "profileVersion": 1,
        "name": "Synthetic Fixture",
        "kind": "custom",
        "referencePath": "~/synthetic.wav",
        "speakerPath": "~/synthetic.npz",
        "createdAt": "2026-01-01T00:00:00Z",
    }
    manifest = runtime.voices / "voices.json"
    original = json.dumps({"schemaVersion": 1, "profiles": [profile]}).encode()
    manifest.write_bytes(original)

    with pytest.raises(ValueError, match="note"):
        _write_voice_manifest(runtime)

    assert manifest.read_bytes() == original


def test_voice_manifest_rejects_custom_profiles_in_builtin_namespace(tmp_path):
    runtime = ExistingRuntime.for_install_root(tmp_path / "install")
    runtime.voices.mkdir(parents=True)
    profile = {
        "id": "builtin-voice_01",
        "engineID": "indextts2",
        "profileVersion": 1,
        "name": "Synthetic Fixture",
        "kind": "custom",
        "referencePath": "~/synthetic.wav",
        "speakerPath": "~/synthetic.npz",
        "createdAt": "2026-01-01T00:00:00Z",
        "note": "",
    }
    manifest = runtime.voices / "voices.json"
    original = json.dumps({"schemaVersion": 1, "profiles": [profile]}).encode()
    manifest.write_bytes(original)

    with pytest.raises(ValueError, match="reserved"):
        _write_voice_manifest(runtime)

    assert manifest.read_bytes() == original


def test_runtime_license_files_are_verified_and_copied_atomically(tmp_path):
    source_root = tmp_path / "repository"
    source = source_root / "licenses/Model/LICENSE.txt"
    source.parent.mkdir(parents=True)
    contents = b"synthetic model license fixture\n"
    source.write_bytes(contents)
    destination_root = tmp_path / "model"

    installer.install_runtime_license_files(
        source_root,
        destination_root,
        [
            {
                "source": "licenses/Model/LICENSE.txt",
                "path": "Licenses/Model/LICENSE.txt",
                "sha256": hashlib.sha256(contents).hexdigest(),
            }
        ],
    )

    assert (destination_root / "Licenses/Model/LICENSE.txt").read_bytes() == contents
    assert list(destination_root.rglob("*.tmp")) == []


def test_runtime_license_file_hash_mismatch_never_reaches_model_directory(tmp_path):
    source_root = tmp_path / "repository"
    source = source_root / "licenses/Model/LICENSE.txt"
    source.parent.mkdir(parents=True)
    source.write_text("changed license fixture\n", encoding="utf-8")
    destination_root = tmp_path / "model"

    with pytest.raises(ValueError, match="SHA-256 mismatch"):
        installer.install_runtime_license_files(
            source_root,
            destination_root,
            [
                {
                    "source": "licenses/Model/LICENSE.txt",
                    "path": "Licenses/Model/LICENSE.txt",
                    "sha256": "0" * 64,
                }
            ],
        )

    assert not (destination_root / "Licenses/Model/LICENSE.txt").exists()


def test_runtime_license_preflights_every_source_before_installing_any_file(tmp_path):
    source_root = tmp_path / "repository"
    licenses = source_root / "licenses/Model"
    licenses.mkdir(parents=True)
    first = b"first synthetic license\n"
    (licenses / "FIRST.txt").write_bytes(first)
    (licenses / "SECOND.txt").write_bytes(b"changed second license\n")
    destination_root = tmp_path / "model"

    with pytest.raises(ValueError, match="SECOND.txt"):
        installer.install_runtime_license_files(
            source_root,
            destination_root,
            [
                {
                    "source": "licenses/Model/FIRST.txt",
                    "path": "Licenses/Model/FIRST.txt",
                    "sha256": hashlib.sha256(first).hexdigest(),
                },
                {
                    "source": "licenses/Model/SECOND.txt",
                    "path": "Licenses/Model/SECOND.txt",
                    "sha256": "0" * 64,
                },
            ],
        )

    assert not (destination_root / "Licenses/Model/FIRST.txt").exists()


def test_runtime_license_installs_the_exact_bytes_that_were_verified(tmp_path, monkeypatch):
    source_root = tmp_path / "repository"
    source = source_root / "licenses/Model/LICENSE.txt"
    source.parent.mkdir(parents=True)
    contents = b"synthetic immutable license bytes\n"
    source.write_bytes(contents)
    destination_root = tmp_path / "model"
    original_read_bytes = Path.read_bytes
    reads = 0

    def counted_read_bytes(path):
        nonlocal reads
        if path == source:
            reads += 1
        return original_read_bytes(path)

    monkeypatch.setattr(Path, "read_bytes", counted_read_bytes)

    installer.install_runtime_license_files(
        source_root,
        destination_root,
        [
            {
                "source": "licenses/Model/LICENSE.txt",
                "path": "Licenses/Model/LICENSE.txt",
                "sha256": hashlib.sha256(contents).hexdigest(),
            }
        ],
    )

    assert reads == 1
    assert (destination_root / "Licenses/Model/LICENSE.txt").read_bytes() == contents
