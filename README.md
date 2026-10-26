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
6. **64 GB of system RAM** and the WSL memory settings below. One TRELLIS.2 process uses 17–35 GB of RAM in WSL.

## WSL memory settings (important)

With the WSL defaults, or with WSL given almost all RAM and no swap, TRELLIS.2 can take **the whole of WSL down**. You're dropped back to PowerShell, and sometimes WSL refuses to start again (`Wsl/Service/E_UNEXPECTED`) until Windows is restarted.

What happens: the TRELLIS.2 process grows to 32–54 GB of RAM. It keeps model copies in RAM between stages, the intermediate meshes can have 5–17 million triangles, and memory creeps up over repeated generations in the web UI. Linux's out-of-memory killer then kills it inside WSL's own `init.scope`, and WSL shuts down about a minute later.

Measured with the fixes below (RTX 5090, three 1536 generations in one process, each with preview render and 4K GLB export, 2026-10-26):

| Step | TRELLIS.2 RAM |
|---|---|
| Models loaded | 16.8 GB |
| After generation 1 | 25.5 GB |
| After generation 2 | 31.6 GB |
| After generation 3 | 31.9 GB (peak 32.4 GB) |

It levels off after the second generation. No swap was used, peak VRAM was about 10 GB, and each generation took about 1 minute. Memory depends mostly on the **image content** (how many voxels it produces), not the resolution setting. For example, a flat 2D drawing produced about 3× more voxels than a painted full-body character, and can still go past the 34 GB cap. Then only TRELLIS.2 is stopped.

Two fixes, both needed:

1. **`C:\Users\<you>\.wslconfig`.** Leave Windows some RAM and turn swap on (values for a 64 GB PC):
   ```ini
   [wsl2]
   memory=40GB
   swap=16GB
   ```
   Then run `wsl --shutdown` in PowerShell and start WSL again.
2. **`run.sh` runs TRELLIS.2 in its own memory group** (`systemd-run --scope`, capped at 34 GB of RAM plus 12 GB of swap). If it goes over, only TRELLIS.2 is stopped, with a message, and WSL keeps running. Change the cap with `TRELLIS_MEM_MAX=30G ./run.sh`.

If WSL still won't start (`E_UNEXPECTED`), try this in an **administrator** PowerShell before restarting the PC:
```powershell
wsl --shutdown
Restart-Service WslService
```

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

Extras added by this repo:

- **Turntable video:** in the web UI, **Extract GLB** also renders an MP4 (one full rotation at eye level, about 5 seconds), with a player and a **Download MP4** button. It adds about 30–60 seconds per export.
- **Logs:** everything printed is saved to `~/TRELLIS.2/logs/run_<date_time>.log`, so error messages survive a closed terminal or a crash.
- **Run one thing at a time.** Two TRELLIS.2 processes at once (for example the web UI plus a script) need more RAM than a 64 GB PC has.

## Web UI settings explained

Microsoft hasn't documented these. This is what they do according to the source code.

TRELLIS.2 builds a model in three stages: **1. Sparse Structure** (a rough voxel sketch of the overall shape), **2. Shape** (detailed geometry) and **3. Material** (color, metal, roughness). Each stage starts from noise and removes it step by step. Each has the same four settings:

| Setting | What it does |
|---|---|
| **Guidance Strength** | How hard the result is pushed toward your image rather than the model's "average guess". Higher follows the image more closely, but too high gives artifacts. **1 switches guidance off.** |
| **Guidance Rescale** | Dampens the side effects of high Guidance Strength (over-contrast, spikes). 0 = none, 1 = full. |
| **Sampling Steps** | Number of denoising steps. More is a little cleaner and slower. Above ~25 rarely helps. |
| **Rescale T** | How the steps are spread out. Higher spends more steps on the coarse shape, lower more on fine detail. |

Material (stage 3) defaults to Guidance Strength **1**, which means guidance is off for colors. In our tests, 3–5 (with Rescale 0.5–0.7) changed the result only slightly.

Other settings:

- **Resolution 512 / 1024 / 1536:** 1536 didn't improve faces in our tests, and memory use was about the same as 1024 (see *WSL memory settings*). 1024 is a good default. 1536 is worth trying for detailed props.
- **Decimation Target:** the maximum triangle count in the exported GLB. TRELLIS.2 first builds 10–20 million triangles and reduces them to this number. For a game character, 30–80k is typical. The slider's minimum is 100k, so reduce further in a 3D tool.
- **Texture Size:** the resolution of the exported textures (1024–4096).
- **Seed:** with the same image and the same settings, the same seed gives the same result. Turn off *Randomize Seed* to keep a result you like.
- **The preview is tilted:** the preview camera looks down from 20° above and is turned 16°. The model itself is upright.

## Getting good results

From many test runs (observations, not official guidance):

- **Input size:** the image is scaled to at most 1024 px and cropped to a square around the object. A larger image adds nothing. The object should fill the frame.
- **Background:** use a plain, dark or grey background with no floor, frame or cast shadow. A **PNG with transparency** is used as is, and background removal is skipped.
- **Lighting:** even and frontal. Strong colored rim light (for example blue or purple) can make dark glossy materials such as leather come out grey and fully metallic.
- **What works well:** creatures, props, sculptures, ornamented or painted figures, and stylized or painterly semi-realistic full-body characters (Pixar/Unreal look).
- **What works poorly:** **photorealistic human faces.** They come out smeared or clay-like at every setting, and the official online demo does the same. Microsoft's model card says outputs reflect the training data, which probably contains few realistic humans. Flat 2D/cel-shaded drawings also come out crude, and they create about 50% more voxels, so they use more memory.
- **Game characters:** use an A-pose with arms away from the body, empty hands, hair tied up or behind the shoulders, and flat feet. Loose hair and anything held in the hands fuse with the body, and stretch badly when the model is rigged (for example in Mixamo).
- **It's a lottery:** results vary a lot between seeds. Generate several and keep the best.

### Rigging in Mixamo

[Mixamo](https://www.mixamo.com) auto-rigs humanoid characters and has a large free animation library. It doesn't accept GLB, so convert first:

```bash
~/TRELLIS.2/run.sh glb_to_mixamo.py character.glb   # writes character_mixamo.zip
```

Upload the zip as is. It contains a textured OBJ with a matte material, so the rigged FBX doesn't come back looking like shiny plastic.

- **Keep the full triangle count** (about 500k worked fine). Reducing the triangle count of a TRELLIS.2 mesh damaged the texture (dark specks all over the body), and Mixamo then refused the marker placement. TRELLIS.2 splits the texture into thousands of small UV islands, which ordinary mesh reduction doesn't handle.
- Mixamo only rigs **two-legged humanoids**. Animals need a pre-rigged model.
- For game animations, tick **In Place** where Mixamo offers it, so your game code moves the character, not the animation. Some animations, such as climbing onto a ledge or getting up, always contain movement.

### Fixing false metal and grey colors

If an export comes out too dark or "metallic", or with washed-out colors:

```bash
~/TRELLIS.2/run.sh fix_materials.py input.glb output.glb --saturation 2.0 --metal 0
```

It sets metallic to 0 and boosts color saturation (in CIELAB, so hue and brightness are kept). It can't bring back colors the model removed completely.

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
| WSL shuts down during generation (dropped to PowerShell) | `.wslconfig` memory/swap and the memory cap in `run.sh` (see *WSL memory settings*) |
| `CUDA driver error: device not ready` / `Failed to create GPU mapping` | keep `TRELLIS_LOW_VRAM=1` (the default in `run.sh`). Keeping all models on the GPU overflows 32 GB of VRAM during the preview |
| RAM grows with every generation in the web UI | `MALLOC_ARENA_MAX=2` in `run.sh` |

All source changes (including the MP4 export and the `TRELLIS_LOW_VRAM` / `DINOV3_MODEL` overrides) are in [`patches/trellis2-blackwell.patch`](patches/trellis2-blackwell.patch). Every dependency is pinned to the commit that was tested.

## Troubleshooting

- **`nvcc` / CUDA 13 not found:** install the WSL-Ubuntu CUDA toolkit (see prerequisites) or `export CUDA_HOME=/usr/local/cuda-13.x`.
- **A single extension fails to build:** the build output is printed. Re-run `./install.sh`, which is safe to repeat.
- **Out of memory on cards with less than 32 GB:** TRELLIS.2 needs ≥ 24 GB of VRAM. Close other GPU apps.
- **Something crashed and the terminal is gone:** read the newest file in `~/TRELLIS.2/logs/`, and `journalctl -b -1 | grep -i "out of memory"` for crashes that took WSL down.

## Credits and licenses

The scripts in this repo are MIT licensed. TRELLIS.2 is © Microsoft (MIT). nvdiffrast and nvdiffrec are under NVIDIA's own licenses. DINOv3 and RMBG-2.0 are under their own licenses, so check them before any commercial use. This repo contains no model weights or third-party code, only an installer, a launcher, a small patch and two helper scripts.
