# Security policy

## Supported versions

Until the first stable release, security fixes are applied to the latest `main` branch only.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting / Security Advisory feature for this repository. Do not include private audio, cloned voices, local file paths, access tokens or model weights in a public issue.

## Dependency status

The installer applies a small pinned security overlay after synchronizing the upstream MLX runtime. As of 2026-08-11, the overlay uses PyTorch 2.13.0 with TorchAudio 2.11.0. TorchAudio 2.11 uses PyTorch's stable ABI and supports PyTorch 2.11 and later releases.

The pair was verified on Apple Silicon by importing both packages, exercising TorchAudio resampling, loading the pinned IndexTTS 2 MLX runtime, and generating finite, non-silent 22.05 kHz audio. A `pip-audit` scan of the resulting overlay reported no known vulnerabilities. Re-run the dependency scan and end-to-end inference gate whenever either package changes.

## Release boundary

The source-built App is ad-hoc signed. Public binary distribution requires a separate Apple Developer signing and notarization process; this repository does not claim that local builds are notarized.
