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
# 1 = models wait in system RAM between stages. With 0 (all models kept on the GPU)
# the 32 GB of an RTX 5090 overflows during the preview render ("CUDA driver error: device not ready").
export TRELLIS_LOW_VRAM=1
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
# Fewer malloc arenas: stops RAM from creeping up with every generation in the web UI
export MALLOC_ARENA_MAX=2
# Optional: while waiting for Meta to approve DINOv3 access, use a mirror instead.
# kryveil/dinov3-vitl16-pretrain-lvd1689m was byte-identical (same SHA-256) to the
# official repo on 2026-10-09. Verify before use, and remove once you have access.
# export DINOV3_MODEL=kryveil/dinov3-vitl16-pretrain-lvd1689m

# Everything printed is also saved to logs/, so errors survive a closed terminal or crash
mkdir -p logs
LOG="logs/run_$(date +%Y-%m-%d_%H%M%S).log"
echo "Log file: $(pwd)/$LOG"

# Run in its own memory group with a hard cap. If TRELLIS runs out of memory, only TRELLIS
# is killed - WSL, the terminal and everything else keep running.
# (Without this, the out-of-memory kill hits WSL's init.scope and takes the whole WSL down.)
MEM_MAX="${TRELLIS_MEM_MAX:-34G}"
if systemd-run --user --scope --quiet true 2>/dev/null; then
    systemd-run --user --scope --quiet -p MemoryMax="$MEM_MAX" -p MemorySwapMax="${TRELLIS_SWAP_MAX:-12G}" \
        python -u "${1:-app.py}" "${@:2}" 2>&1 | tee "$LOG"
    status=${PIPESTATUS[0]}
else
    echo "Note: systemd user session not available - running without a memory cap."
    python -u "${1:-app.py}" "${@:2}" 2>&1 | tee "$LOG"
    status=${PIPESTATUS[0]}
fi
if [ "$status" = 137 ] || [ "$status" = 9 ]; then
    echo "TRELLIS was stopped because it used more than $MEM_MAX RAM. WSL is fine - just run ./run.sh again." | tee -a "$LOG"
fi
