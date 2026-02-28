#!/usr/bin/env bash
# Docker post-install setup
# Enables the Docker service and configures nvidia-container-runtime as the default runtime.

set -euo pipefail

echo "==> Setting up Docker..."

# ── 1. Enable and start Docker service ───────────────────────────────────────
echo "  -> Enabling docker.service..."
sudo systemctl enable --now docker

# ── 2. Configure nvidia-container-toolkit if present ─────────────────────────
if command -v nvidia-ctk &>/dev/null; then
    echo "  -> Configuring nvidia-container-toolkit for Docker..."
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
    echo "  -> nvidia runtime configured"
else
    echo "  -> nvidia-ctk not found, skipping GPU runtime config (install nvidia-container-toolkit first)"
fi

echo ""
echo "✓ Docker setup complete."
echo ""
echo "Verify with:"
echo "  docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi"
