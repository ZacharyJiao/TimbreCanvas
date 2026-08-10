# Contributing

Contributions are welcome through GitHub issues and pull requests.

Before opening a pull request:

```bash
swift test --package-path App
PYTHONPATH=RuntimeHost python3 -m pytest RuntimeHost/tests Installer/tests
PYTHONPATH=RuntimeHost python3 -m ruff check RuntimeHost Installer
```

Do not commit:

- model weights or converted checkpoints;
- reference audio, cloned voices or generated outputs;
- local configuration, caches or virtual environments;
- absolute personal paths, tokens, certificates or signing assets.

New model integrations should implement the model-neutral `TTSEngine` boundary, declare capabilities accurately, keep models external and add protocol plus parameter-forwarding tests.
