# External runtimes and models

TimbreCanvas does not redistribute model weights. The setup script downloads each asset from its publisher's official repository at a pinned revision and performs the MLX conversion locally. Using the installer means the user, not the TimbreCanvas project, downloads and uses those external components.

| Component | Pinned source | Declared license |
| --- | --- | --- |
| MLX-IndexTTS port | [solar2ain/mlx-indextts](https://github.com/solar2ain/mlx-indextts) | MIT |
| IndexTTS 2 | [IndexTeam/IndexTTS-2](https://huggingface.co/IndexTeam/IndexTTS-2) | bilibili Model Use License Agreement |
| BigVGAN v2 22 kHz | [nvidia/bigvgan_v2_22khz_80band_256x](https://huggingface.co/nvidia/bigvgan_v2_22khz_80band_256x) | MIT |
| MaskGCT semantic codec | [amphion/MaskGCT](https://huggingface.co/amphion/MaskGCT) | CC BY-NC 4.0 |
| W2V-BERT 2.0 | [facebook/w2v-bert-2.0](https://huggingface.co/facebook/w2v-bert-2.0) | MIT |
| CAMPPlus | [funasr/campplus](https://huggingface.co/funasr/campplus) | Apache-2.0 |

Important consequences:

- The repository's MIT License covers only TimbreCanvas-owned source code and assets.
- The locally quantized IndexTTS 2 weights are a derivative work under the IndexTTS 2 model license. They are deliberately excluded from Git and are not distributed with the App.
- MaskGCT is declared CC BY-NC 4.0. Users considering commercial use must determine whether their use complies with that license or obtain appropriate permission.
- IndexTTS 2 has its own restrictions, attribution duties and separate-license thresholds. Read the full English and Chinese license files before use.
- Voice samples, cloned voices and generated outputs may carry additional rights and legal obligations. Users are responsible for consent and lawful use.

Exact revisions and SHA-256 values are recorded in [`Installer/runtime-assets.json`](Installer/runtime-assets.json). Pinned IndexTTS 2 and BigVGAN license snapshots are kept under [`Installer/Licenses`](Installer/Licenses), verified before installation, and copied into the converted model's `Licenses` directory. Other publisher files remain in their pinned local download/cache snapshots.

Run `./script/setup.sh --show-model-licenses` to review the fixed license locations and key obligations without installing or changing files.

This summary is informational and is not legal advice.
