#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT_DIR/Installer/runtime-assets.json"
APP_SUPPORT="$HOME/Library/Application Support/TimbreCanvas"
INSTALL_ROOT="$APP_SUPPORT"
APP_DIR="$HOME/Applications"
REUSE_PROJECT=""
ACCEPT_MODEL_LICENSES=0
SKIP_APP=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: ./script/setup.sh [options]

Options:
  --install-root PATH       Store runtime and models at PATH.
  --app-dir PATH            Install TimbreCanvas.app in PATH (default: ~/Applications).
  --reuse-runtime PATH      Connect an existing mlx-indextts project instead of downloading.
  --accept-model-licenses   Accept the external model licenses non-interactively.
  --skip-app                Configure the runtime without building/installing the app.
  --dry-run                 Print the selected layout without changing files.
  -h, --help                Show this help.
EOF
}

while (($#)); do
  case "$1" in
    --install-root)
      INSTALL_ROOT="${2:?missing path after --install-root}"
      shift 2
      ;;
    --app-dir)
      APP_DIR="${2:?missing path after --app-dir}"
      shift 2
      ;;
    --reuse-runtime)
      REUSE_PROJECT="${2:?missing path after --reuse-runtime}"
      shift 2
      ;;
    --accept-model-licenses)
      ACCEPT_MODEL_LICENSES=1
      shift
      ;;
    --skip-app)
      SKIP_APP=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

echo "TimbreCanvas setup"
echo "  App configuration: $APP_SUPPORT"
echo "  Runtime and models: $INSTALL_ROOT"
echo "  App destination:    $APP_DIR/TimbreCanvas.app"
if [[ -n "$REUSE_PROJECT" ]]; then
  echo "  Existing runtime:   $REUSE_PROJECT"
fi

if ((DRY_RUN)); then
  echo "Dry run complete; no files were changed."
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "TimbreCanvas requires macOS on Apple Silicon." >&2
  exit 1
fi

MEMORY_BYTES="$(sysctl -n hw.memsize)"
if ((MEMORY_BYTES < 16 * 1024 * 1024 * 1024)); then
  echo "At least 16 GB unified memory is required; 24 GB or more is recommended." >&2
  exit 1
fi

command -v git >/dev/null || { echo "git is required." >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required." >&2; exit 1; }

if [[ -n "$REUSE_PROJECT" ]]; then
  PYTHONPATH="$ROOT_DIR/Installer" python3 -m timbrecanvas_installer.install \
    configure-existing \
    --project "$REUSE_PROJECT" \
    --support-root "$APP_SUPPORT" \
    --manifest "$MANIFEST"
else
  if ((ACCEPT_MODEL_LICENSES == 0)); then
    cat <<'EOF'

The app is MIT-licensed, but the external models are not part of the app.
Before downloading, review and accept their licenses:
  IndexTTS 2: https://huggingface.co/IndexTeam/IndexTTS-2
  BigVGAN:    https://huggingface.co/nvidia/bigvgan_v2_22khz_80band_256x
  MaskGCT:    https://huggingface.co/amphion/MaskGCT
  W2V-BERT:   https://huggingface.co/facebook/w2v-bert-2.0
  CAMPPlus:   https://huggingface.co/funasr/campplus
EOF
    read -r -p "Type I AGREE to continue: " MODEL_LICENSE_RESPONSE
    if [[ "$MODEL_LICENSE_RESPONSE" != "I AGREE" ]]; then
      echo "Setup cancelled; nothing was downloaded."
      exit 1
    fi
  fi

  FREE_KB="$(df -Pk "$HOME" | awk 'NR==2 {print $4}')"
  if ((FREE_KB < 20 * 1024 * 1024)); then
    echo "At least 20 GB of free disk space is required for download and conversion." >&2
    exit 1
  fi

  UV_VERSION="0.12.3"
  UV_SHA256="546f7f8a6c70ff13a3a9d2bc958db3427298cebf3e0cb756f9177133b7068843"
  UV_TOOLS="$INSTALL_ROOT/.tools/uv/$UV_VERSION"
  UV_BIN="$UV_TOOLS/uv"
  if [[ ! -x "$UV_BIN" ]]; then
    TEMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TEMP_DIR"' EXIT
    ARCHIVE="$TEMP_DIR/uv.tar.gz"
    curl --proto '=https' --tlsv1.2 -fsSL \
      "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-aarch64-apple-darwin.tar.gz" \
      -o "$ARCHIVE"
    printf '%s  %s\n' "$UV_SHA256" "$ARCHIVE" | shasum -a 256 -c -
    mkdir -p "$UV_TOOLS"
    tar -xzf "$ARCHIVE" -C "$TEMP_DIR"
    cp "$TEMP_DIR/uv-aarch64-apple-darwin/uv" "$UV_BIN"
    chmod 755 "$UV_BIN"
  fi

  MLX_REVISION="1026564f418e633e885df349e42ccf31a0ea9884"
  SOURCE_DIR="$INSTALL_ROOT/Runtime/source/mlx-indextts"
  if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    mkdir -p "$(dirname "$SOURCE_DIR")"
    git clone --filter=blob:none --no-checkout \
      https://github.com/solar2ain/mlx-indextts.git "$SOURCE_DIR"
  fi
  if [[ "$(git -C "$SOURCE_DIR" remote get-url origin)" != "https://github.com/solar2ain/mlx-indextts.git" ]]; then
    echo "Unexpected mlx-indextts source remote at $SOURCE_DIR" >&2
    exit 1
  fi
  git -C "$SOURCE_DIR" fetch --depth 1 origin "$MLX_REVISION"
  git -C "$SOURCE_DIR" checkout --detach "$MLX_REVISION"
  if [[ "$(git -C "$SOURCE_DIR" rev-parse HEAD)" != "$MLX_REVISION" ]]; then
    echo "Unable to verify the pinned mlx-indextts revision." >&2
    exit 1
  fi

  export UV_PROJECT_ENVIRONMENT="$INSTALL_ROOT/Runtime/.venv"
  export UV_CACHE_DIR="$INSTALL_ROOT/Cache/uv"
  export UV_PYTHON_INSTALL_DIR="$INSTALL_ROOT/Runtime/python"
  "$UV_BIN" python install 3.12.12
  "$UV_BIN" sync \
    --project "$SOURCE_DIR" \
    --python 3.12.12 \
    --locked \
    --no-dev \
    --extra convert \
    --extra v2
  "$UV_BIN" pip install \
    --python "$INSTALL_ROOT/Runtime/.venv/bin/python" \
    --upgrade \
    --no-deps \
    --requirement "$ROOT_DIR/Installer/security-overrides.txt"

  export HF_HUB_DISABLE_XET=1
  PYTHONPATH="$ROOT_DIR/Installer" "$INSTALL_ROOT/Runtime/.venv/bin/python" \
    -m timbrecanvas_installer.install fresh-install \
    --install-root "$INSTALL_ROOT" \
    --support-root "$APP_SUPPORT" \
    --manifest "$MANIFEST"
fi

if ((SKIP_APP == 0)); then
  command -v swift >/dev/null || {
    echo "Swift is required to build the app. Install Xcode Command Line Tools first." >&2
    exit 1
  }
  "$ROOT_DIR/script/package_app.sh"
  mkdir -p "$APP_DIR"
  TARGET_APP="$APP_DIR/TimbreCanvas.app"
  if [[ -e "$TARGET_APP" ]]; then
    BACKUP_APP="$APP_DIR/TimbreCanvas.backup.$(date +%Y%m%d-%H%M%S).app"
    mv "$TARGET_APP" "$BACKUP_APP"
    echo "Previous app preserved at: $BACKUP_APP"
  fi
  ditto "$ROOT_DIR/dist/TimbreCanvas.app" "$TARGET_APP"
  open -R "$TARGET_APP"
fi

echo "TimbreCanvas setup is complete."
