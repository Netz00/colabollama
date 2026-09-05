#!/usr/bin/env bash
set -euo pipefail

# Configuration
LLAMA_DIR="/content/llama.cpp"

GITHUB_REPO="Netz00/colabollama"

MODEL_DIR="/content/models"
MODEL="qwen2.5-coder-14b-instruct-q5_k_m.gguf"
MODEL_REPO="Qwen/Qwen2.5-Coder-14B-Instruct-GGUF"

LLAMA_SERVER="${LLAMA_DIR}/build/bin/llama-server"
LOG_FILE="/content/llama-server.log"

HOST="127.0.0.1"
PORT="8000"

export LD_LIBRARY_PATH="/usr/lib64-nvidia:${LD_LIBRARY_PATH:-}"

# Find latest T4 llama.cpp release
echo "Finding latest llama.cpp T4 release..."

RELEASE_JSON=$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${GITHUB_REPO}/releases/latest")

LLAMA_RELEASE=$(echo "$RELEASE_JSON" | jq -r '.tag_name')

ARTIFACT=$(echo "$RELEASE_JSON" | jq -r '
  .assets[]
  | select(.name | test("cuda12\\.8.*t4.*\\.tar\\.gz$"; "i"))
  | .name
' | head -n 1)

if [[ -z "$ARTIFACT" ]]; then
  echo "ERROR: Could not find CUDA 12.8 T4 artifact in release ${LLAMA_RELEASE}"
  echo
  echo "Available assets:"
  echo "$RELEASE_JSON" | jq -r '.assets[].name'
  exit 1
fi

ARTIFACT_URL=$(echo "$RELEASE_JSON" | jq -r --arg artifact "$ARTIFACT" '
  .assets[]
  | select(.name == $artifact)
  | .browser_download_url
')

echo "Release:  ${LLAMA_RELEASE}"
echo "Artifact: ${ARTIFACT}"

# Download and extract llama.cpp
mkdir -p "$LLAMA_DIR"

echo "Downloading llama.cpp artifact..."

rm -f "/content/${ARTIFACT}"

curl -fL --progress-bar \
  "$ARTIFACT_URL" \
  -o "/content/${ARTIFACT}"

# Verify archive before extracting
tar -tzf "/content/${ARTIFACT}" >/dev/null

tar -xzf "/content/${ARTIFACT}" -C "$LLAMA_DIR"

# Check llama-server
"$LLAMA_SERVER" --version
"$LLAMA_SERVER" --list-devices

# Download model in tmux
mkdir -p "$MODEL_DIR"

DOWNLOAD_DONE="/content/model-download.done"

rm -f "$DOWNLOAD_DONE"

tmux new-session -d -s setup \
  "hf download '$MODEL_REPO' '$MODEL' --local-dir '$MODEL_DIR' && touch '$DOWNLOAD_DONE'; tmux kill-session -t setup"

echo "Downloading model..."

while [[ ! -f "$DOWNLOAD_DONE" ]]; do
  sleep 5
done

echo "Model download complete."

# Start llama-server
nohup "$LLAMA_SERVER" \
  -m "${MODEL_DIR}/${MODEL}" \
  -ngl 99 \
  -c 20480 \
  -fa \
  -ctk q8_0 \
  -ctv q8_0 \
  -t 2 \
  -b 2048 \
  -ub 512 \
  --temp 0.1 \
  --jinja \
  --host "$HOST" \
  --port "$PORT" \
  > "$LOG_FILE" 2>&1 &

# Wait for server
echo "Waiting for llama-server..."

while ! grep -q "llama_server: listening on http://${HOST}:${PORT}" "$LOG_FILE" 2>/dev/null; do
  sleep 10
done

echo "llama-server is ready."

# GPU status
nvidia-smi \
  --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu \
  --format=csv,noheader

exit 0