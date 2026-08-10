# Security policy

## Supported versions

Until the first stable release, security fixes are applied to the latest `main` branch only.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting / Security Advisory feature for this repository. Do not include private audio, cloned voices, local file paths, access tokens or model weights in a public issue.

## Dependency status

The installer applies a small pinned security overlay after synchronizing the upstream MLX runtime. As of 2026-08-10, a local `pip-audit` scan was reduced from 41 findings in 11 packages to two findings in PyTorch 2.10:

- `PYSEC-2026-139`: no fixed version is published.
- `PYSEC-2025-194`: the published fix requires PyTorch 2.13, while a matching compatible torchaudio build is not currently available to this runtime.

These findings are not silently marked as fixed. Upgrading PyTorch alone would create an unsupported binary pair and can break inference. Track them as accepted upstream risk until a compatible torch/torchaudio pair is available, then remove the exception and re-run end-to-end inference verification.

## Release boundary

The source-built App is ad-hoc signed. Public binary distribution requires a separate Apple Developer signing and notarization process; this repository does not claim that local builds are notarized.
