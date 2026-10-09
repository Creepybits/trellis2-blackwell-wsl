# TRELLIS.2 on Blackwell (RTX 50-series) + WSL2

A one-script installer for [Microsoft TRELLIS.2](https://github.com/microsoft/TRELLIS.2) (image → textured 3D model) on NVIDIA Blackwell GPUs such as the RTX 5090, running in Ubuntu on WSL2.

The official `setup.sh` installs PyTorch 2.6 + CUDA 12.4 and a prebuilt flash-attn. None of these support Blackwell (`sm_120`), so the install either fails or crashes at runtime. This repo installs a working combination and patches the few things that break along the way.

## Tested setup

| | |
|---|---|
| GPU | RTX 5090 (32 GB) |
| Windows driver | 616.92 |
| OS | Windows 11, Ubuntu 24.04 on WSL2 |
| CUDA toolkit (in WSL) | 13.1 |
| PyTorch | 2.14.1 + cu130, xformers 0.0.35 |
| Result | `example.py` runs end to end in ~4.5 min (incl. model loading and a 4K-texture GLB export) |

## Prerequisites

1. **Latest NVIDIA driver on Windows.** WSL uses the Windows driver. Don't install a Linux GPU driver inside WSL.
2. **WSL2 with Ubuntu.** Virtualization must stay **enabled** in the BIOS, because WSL2 needs it.
3. **CUDA Toolkit 13.x inside WSL.** Use the *Linux → x86_64 → WSL-Ubuntu* installer from <https://developer.nvidia.com/cuda-downloads>. It installs only the toolkit, no driver. Check with `ls /usr/local/cuda-13*`.
4. Build tools:
   ```bash
   sudo apt install -y git python3-venv python3-dev build-essential
   ```
5. About 40 GB of free disk space: ~22 GB of model weights plus the Python environment.

## Install

```bash
git clone https://github.com/Creepybits/trellis2-blackwell-wsl.git
cd trellis2-blackwell-wsl
./install.sh            # installs into ~/TRELLIS.2 (or pass another path)
```

The script takes about 10–15 minutes. Most of that is compiling the five CUDA extensions.

## Gated models

TRELLIS.2 downloads two models from Hugging Face that require accepting a license first:

| Model | Used for | Link |
|---|---|---|
| DINOv3 ViT-L/16 (Meta) | image features (**required**) | <https://huggingface.co/facebook/dinov3-vitl16-pretrain-lvd1689m> |
| RMBG-2.0 (BRIA) | background removal | <https://huggingface.co/briaai/RMBG-2.0> |

Log in on huggingface.co, open each link and request access. RMBG is usually approved instantly. Meta may take a while. Then log in from WSL:

```bash
~/TRELLIS.2/.venv/bin/hf auth login
```

**Waiting for DINOv3 approval?** You can uncomment the `DINOV3_MODEL` line in `~/TRELLIS.2/run.sh` to load a community mirror instead. On 2026-10-09 the mirror's files had the same SHA-256 hashes as Meta's. Check this again yourself, because mirrors can change. The DINOv3 license still applies either way.

## Run

```bash
~/TRELLIS.2/run.sh example.py        # test: writes sample.glb and sample.mp4
~/TRELLIS.2/run.sh                   # web UI → open http://localhost:7860 in Windows
~/TRELLIS.2/run.sh app_texturing.py  # texturing web UI
```

The first run downloads ~22 GB of weights into `~/.cache/huggingface`.

## What's different from upstream

| Problem | Fix |
|---|---|
| torch 2.6 / cu124 has no `sm_120` kernels | torch 2.14.1 + cu130 |
| flash-attn has no Blackwell wheels; building it from source takes hours | `ATTN_BACKEND=xformers` (TRELLIS.2 supports it, and xformers ships `sm_120` wheels) |
| Extensions fail: `C++20 or later compatible compiler is required to use PyTorch` | `setup.py` flags changed from `c++17` to `c++20` |
| nvdiffrec link fails: `cannot find -lcuda` | `LIBRARY_PATH=/usr/lib/wsl/lib` (WSL keeps `libcuda.so` there) |
| `cv2.error ... !_src.empty() in function 'cvtColor'` loading `.exr` | `opencv-python-headless<5` |
| `'DINOv3ViTModel' object has no attribute 'layer'` | patch for transformers ≥ 5 (layers moved to `model.model.layer`) |
| Hugging Face downloads stall at 0 bytes | `HF_HUB_DISABLE_XET=1` |
| `GatedRepoError` | request access to the models above |

All source changes are in [`patches/trellis2-blackwell.patch`](patches/trellis2-blackwell.patch). Every dependency is pinned to the commit that was tested.

## Troubleshooting

- **`nvcc` / CUDA 13 not found:** install the WSL-Ubuntu CUDA toolkit (see prerequisites) or `export CUDA_HOME=/usr/local/cuda-13.x`.
- **A single extension fails to build:** the build output is printed. Re-run `./install.sh`, which is safe to repeat.
- **Out of memory on cards with less than 32 GB:** TRELLIS.2 needs ≥ 24 GB of VRAM. Close other GPU apps.

## Credits and licenses

The scripts in this repo are MIT licensed. TRELLIS.2 is © Microsoft (MIT). nvdiffrast and nvdiffrec are under NVIDIA's own licenses. DINOv3 and RMBG-2.0 are under their own licenses, so check them before any commercial use. This repo contains no model weights or third-party code, only an installer and a small patch.
