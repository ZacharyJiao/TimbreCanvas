from timbrecanvas_runtime.output_paths import temporary_output


def test_partial_output_name_depends_only_on_its_request_token(tmp_path):
    allocated = tmp_path / "result-2.wav"
    partial_identifier = "01234567-89ab-cdef-0123-456789abcdef"

    with temporary_output(
        allocated,
        partial_token=partial_identifier,
    ) as partial:
        assert partial.parent == tmp_path
        assert partial.name == f".timbrecanvas.{partial_identifier}.partial.wav"
        partial.write_bytes(b"synthetic partial")

    assert not partial.exists()
