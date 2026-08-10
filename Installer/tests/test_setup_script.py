import subprocess


def test_setup_can_show_pinned_model_license_obligations_without_installing():
    result = subprocess.run(
        ["bash", "script/setup.sh", "--show-model-licenses"],
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0
    assert "Installer/Licenses/IndexTTS-2/LICENSE.txt" in result.stdout
    assert "Derivative Work" in result.stdout
    assert "CC BY-NC 4.0" in result.stdout
    assert "No files were changed" in result.stdout
