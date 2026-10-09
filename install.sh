#!/usr/bin/env bash
# Install Microsoft TRELLIS.2 on NVIDIA Blackwell GPUs (RTX 50-series, sm_120) under WSL2 / Ubuntu.
#
# Usage:  ./install.sh [install-dir]        (default: ~/TRELLIS.2)
#
# Differences from the upstream setup.sh:
#   - PyTorch 2.14 + CUDA 13.0 wheels (upstream pins torch 2.6 / cu124, which has no sm_120 kernels)
#   - xformers instead of flash-attn (prebuilt Blackwell wheels; flash-attn must be compiled for hours)
#   - CUDA extensions compiled for sm_120 with C++20 (required by torch >= 2.10)
#   - Links against the WSL driver library in /usr/lib/wsl/lib
#   - opencv-python-headless < 5 (OpenCV 5 cannot read the example .exr HDRIs)
#   - Small source patch for transformers >= 5 and an optional DINOv3 mirror override
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(realpath -m "${1:-$HOME/TRELLIS.2}")"
EXT_DIR="$INSTALL_DIR/extensions"

# Versions verified on RTX 5090, driver 616.92, CUDA toolkit 13.1, Ubuntu 24.04 (WSL2)
TRELLIS2_COMMIT=75fbf0183001ed9876c8dbb35de6b68552ee08bd
NVDIFFRAST_COMMIT=253ac4fcea7de5f396371124af597e6cc957bfae   # tag v0.4.0
NVDIFFREC_COMMIT=b296927cc7fd01c2ac1087c8065c4d7248f72da4    # branch renderutils
CUMESH_COMMIT=12289e1062f0603f2f0d0771b02e1395d247f26f
FLEXGEMM_COMMIT=6dd94a859c26ee8246888502eada3dd8ad85532e
TORCH_INDEX=https://download.pytorch.org/whl/cu130
TORCH_PKGS="torch==2.14.1 torchvision==0.29.1 xformers==0.0.35"

step() { echo; echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------- checks
step "Checking prerequisites"
command -v nvidia-smi >/dev/null || die "nvidia-smi not found. Install the latest NVIDIA Windows driver (WSL uses the Windows driver)."
nvidia-smi --query-gpu=name --format=csv,noheader

if [ -z "${CUDA_HOME:-}" ]; then
    CUDA_HOME=$(ls -d /usr/local/cuda-13* 2>/dev/null | sort -V | tail -1 || true)
fi
[ -n "$CUDA_HOME" ] && [ -x "$CUDA_HOME/bin/nvcc" ] || die "CUDA Toolkit 13.x not found in /usr/local. Install it with the 'WSL-Ubuntu' installer from https://developer.nvidia.com/cuda-downloads (do NOT install a Linux GPU driver inside WSL), or set CUDA_HOME."
"$CUDA_HOME/bin/nvcc" --version | tail -1

for c in git python3 g++; do command -v $c >/dev/null || die "$c not found. Run: sudo apt install -y git python3-venv python3-dev build-essential"; done
python3 -c "import ensurepip" 2>/dev/null || die "python3-venv missing. Run: sudo apt install -y python3-venv python3-dev"
[ -f /usr/lib/wsl/lib/libcuda.so ] || echo "Note: /usr/lib/wsl/lib/libcuda.so not found - not running under WSL? Continuing."

export CUDA_HOME
export PATH="$CUDA_HOME/bin:$PATH"
export TORCH_CUDA_ARCH_LIST="12.0"
export LIBRARY_PATH="/usr/lib/wsl/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
export MAX_JOBS="${MAX_JOBS:-$(( $(nproc) > 16 ? 16 : $(nproc) ))}"

# ---------------------------------------------------------------- source
step "Getting TRELLIS.2 into $INSTALL_DIR"
if [ ! -d "$INSTALL_DIR/.git" ]; then
    git clone https://github.com/microsoft/TRELLIS.2.git "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
git fetch -q origin
git checkout -q "$TRELLIS2_COMMIT"
git submodule update --init --recursive -q
if git apply --check "$REPO_DIR/patches/trellis2-blackwell.patch" 2>/dev/null; then
    git apply "$REPO_DIR/patches/trellis2-blackwell.patch"
    echo "Patch applied."
elif git apply --reverse --check "$REPO_DIR/patches/trellis2-blackwell.patch" 2>/dev/null; then
    echo "Patch already applied."
else
    die "Patch does not apply cleanly. Is $INSTALL_DIR modified?"
fi
cp "$REPO_DIR/run.sh" "$INSTALL_DIR/run.sh"
cp "$REPO_DIR/tools/fix_materials.py" "$INSTALL_DIR/fix_materials.py"
chmod +x "$INSTALL_DIR/run.sh"

# ---------------------------------------------------------------- python env
step "Creating Python virtual environment (.venv)"
[ -d .venv ] || python3 -m venv .venv
source .venv/bin/activate
pip install -q -U pip wheel setuptools

step "Installing PyTorch + xformers for CUDA 13 (Blackwell)"
pip install $TORCH_PKGS --index-url "$TORCH_INDEX"
python -c "import torch; assert 'sm_120' in torch.cuda.get_arch_list(), 'torch build lacks sm_120'; print('torch', torch.__version__, 'OK on', torch.cuda.get_device_name(0))"

step "Installing Python dependencies"
pip install imageio imageio-ffmpeg tqdm easydict "opencv-python-headless<5" ninja trimesh \
    transformers gradio==6.0.1 tensorboard pandas lpips zstandard kornia timm \
    "git+https://github.com/EasternJournalist/utils3d.git@9a4eb15e4021b67b12c460c7057d642626897ec8"

# ---------------------------------------------------------------- CUDA extensions
build_ext() {  # name url commit
    local name=$1 url=$2 commit=$3
    step "Building $name for sm_120"
    [ -d "$EXT_DIR/$name/.git" ] || git clone -q "$url" "$EXT_DIR/$name"
    git -C "$EXT_DIR/$name" fetch -q origin
    git -C "$EXT_DIR/$name" checkout -q -f "$commit"
    git -C "$EXT_DIR/$name" submodule update --init --recursive -q
    cxx20 "$EXT_DIR/$name"
    pip install "$EXT_DIR/$name" --no-build-isolation
}
cxx20() { [ -f "$1/setup.py" ] && sed -i 's/c++17/c++20/g' "$1/setup.py" || true; }

mkdir -p "$EXT_DIR"
build_ext nvdiffrast https://github.com/NVlabs/nvdiffrast.git      "$NVDIFFRAST_COMMIT"
build_ext nvdiffrec  https://github.com/JeffreyXiang/nvdiffrec.git "$NVDIFFREC_COMMIT"
build_ext CuMesh     https://github.com/JeffreyXiang/CuMesh.git    "$CUMESH_COMMIT"
build_ext FlexGEMM   https://github.com/JeffreyXiang/FlexGEMM.git  "$FLEXGEMM_COMMIT"

step "Building o-voxel for sm_120"
rm -rf "$EXT_DIR/o-voxel"
cp -r "$INSTALL_DIR/o-voxel" "$EXT_DIR/o-voxel"
cxx20 "$EXT_DIR/o-voxel"
pip install "$EXT_DIR/o-voxel" --no-build-isolation

# ---------------------------------------------------------------- verify
step "Verifying imports"
ATTN_BACKEND=xformers python -c "
import torch, xformers, nvdiffrast.torch, nvdiffrec_render, cumesh, flex_gemm, o_voxel
from trellis2.pipelines import Trellis2ImageTo3DPipeline
print('All modules import OK')" 2>&1 | grep -v -i warning

cat <<EOF

Installation complete.

Next steps:
  1. Request access to the gated models on huggingface.co (log in, open each page, accept):
       https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m
       https://huggingface.co/briaai/RMBG-2.0
  2. Log in from WSL:   $INSTALL_DIR/.venv/bin/hf auth login
  3. Test:              $INSTALL_DIR/run.sh example.py      (first run downloads ~22 GB)
     Web UI:            $INSTALL_DIR/run.sh                 then open http://localhost:7860
EOF
