#!/usr/bin/env bash
# Launcher for TRELLIS.2 on NVIDIA Blackwell (RTX 50-series) under WSL2.
# Usage:  ./run.sh                    -> web UI, open http://localhost:7860 in your Windows browser
#         ./run.sh example.py         -> run any script in the TRELLIS.2 folder
#         ./run.sh app_texturing.py   -> texturing web UI
cd "$(dirname "$0")"
source .venv/bin/activate
export ATTN_BACKEND=xformers      # flash-attn is not installed; xformers has Blackwell wheels
export HF_HUB_DISABLE_XET=1       # xet downloads can hang at 0 bytes under WSL
export LIBRARY_PATH=/usr/lib/wsl/lib
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
# Optional: while waiting for Meta to approve DINOv3 access, use a mirror instead.
# kryveil/dinov3-vitl16-pretrain-lvd1689m was byte-identical (same SHA-256) to the
# official repo on 2026-10-09. Verify before use, and remove once you have access.
# export DINOV3_MODEL=kryveil/dinov3-vitl16-pretrain-lvd1689m
exec python "${1:-app.py}" "${@:2}"
