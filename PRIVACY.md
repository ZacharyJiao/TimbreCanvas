# Privacy

TimbreCanvas is local-first.

- No account is required.
- The App contains no analytics, telemetry, advertising SDK or crash-report upload.
- Text, imported audio, cloned voice profiles, presets and generated audio are processed and stored locally.
- Network access is used by the setup script to download declared runtime and model assets. Normal inference is configured for offline Hugging Face operation.
- The local configuration contains file-system paths selected by the user and is written with owner-only permissions.
- Model files, audio, voice profiles, presets, outputs and local configuration are excluded from Git.

Users must obtain permission before cloning or synthesizing another person's voice. Do not use TimbreCanvas for impersonation, fraud, harassment, surveillance or unlawful content.

When reporting a bug, remove personal paths, text, audio, voice profiles, logs and model files before attaching diagnostics.
