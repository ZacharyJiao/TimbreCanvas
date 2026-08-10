from timbrecanvas_runtime.model_validation import REQUIRED_V2_FILES, validate_v2_runtime


def test_index_tts_2_validation_requires_every_external_asset(tmp_path):
    for name in REQUIRED_V2_FILES[:-1]:
        (tmp_path / name).touch()

    result = validate_v2_runtime(tmp_path)

    assert result.valid is False
    assert result.missing == (REQUIRED_V2_FILES[-1],)


def test_index_tts_2_validation_rejects_legacy_v15_artifacts(tmp_path):
    for name in REQUIRED_V2_FILES:
        (tmp_path / name).touch()
    (tmp_path / "legacy-v1.5.ckpt").touch()

    result = validate_v2_runtime(tmp_path)

    assert result.valid is False
    assert result.forbidden == ("legacy-v1.5.ckpt",)
