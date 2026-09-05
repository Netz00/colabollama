#!/usr/bin/env bash
set -euo pipefail

START_TIME=$(date +%s)

# Configuration
LLAMA_DIR="/content/llama.cpp"

GITHUB_REPO="Netz00/colabollama"

MODEL_DIR="/content/models"
MODEL="zai-org_GLM-4.7-Flash-IQ3_M.gguf"
MODEL_REPO="bartowski/zai-org_GLM-4.7-Flash-GGUF"

LLAMA_SERVER="${LLAMA_DIR}/build/bin/llama-server"
LOG_FILE="/content/llama-server.log"

HOST="127.0.0.1"
PORT="8000"

# Include llama.cpp shared libraries and NVIDIA libraries
export LD_LIBRARY_PATH="${LLAMA_DIR}/build/bin:/usr/lib64-nvidia:${LD_LIBRARY_PATH:-}"

# ------------------------------------------------------------
# Find latest llama.cpp T4 release
# ------------------------------------------------------------

echo "Finding latest llama.cpp T4 release..."

RELEASE_JSON=$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${GITHUB_REPO}/releases/latest")

LLAMA_RELEASE=$(echo "$RELEASE_JSON" | jq -r '.tag_name')

if [[ -z "$LLAMA_RELEASE" || "$LLAMA_RELEASE" == "null" ]]; then
  echo "ERROR: Could not determine latest release."
  exit 1
fi

# Find CUDA 12.8 T4 tar.gz artifact
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

if [[ -z "$ARTIFACT_URL" || "$ARTIFACT_URL" == "null" ]]; then
  echo "ERROR: Could not determine artifact download URL."
  exit 1
fi

echo "Release:  ${LLAMA_RELEASE}"
echo "Artifact: ${ARTIFACT}"

# ------------------------------------------------------------
# Download and extract llama.cpp
# ------------------------------------------------------------

mkdir -p "$LLAMA_DIR"

echo
echo "Downloading llama.cpp artifact..."

rm -f "/content/${ARTIFACT}"

curl -fL \
  --progress-bar \
  "$ARTIFACT_URL" \
  -o "/content/${ARTIFACT}"

# Verify download
if [[ ! -s "/content/${ARTIFACT}" ]]; then
  echo "ERROR: Downloaded artifact is empty."
  exit 1
fi

echo
echo "Downloaded:"
ls -lh "/content/${ARTIFACT}"

# Verify archive before extracting
echo "Checking archive..."

tar -tzf "/content/${ARTIFACT}" >/dev/null

echo "Archive OK."

tar -xzf "/content/${ARTIFACT}" -C "$LLAMA_DIR"

# ------------------------------------------------------------
# Check llama-server
# ------------------------------------------------------------

echo
echo "Checking llama-server..."

if [[ ! -x "$LLAMA_SERVER" ]]; then
  echo "ERROR: llama-server not found:"
  echo "$LLAMA_SERVER"
  exit 1
fi

"$LLAMA_SERVER" --version
"$LLAMA_SERVER" --list-devices

# ------------------------------------------------------------
# Download model in tmux
# ------------------------------------------------------------

mkdir -p "$MODEL_DIR"

DOWNLOAD_DONE="/content/model-download.done"

rm -f "$DOWNLOAD_DONE"

tmux new-session -d -s setup \
  "hf download '$MODEL_REPO' '$MODEL' --local-dir '$MODEL_DIR' && touch '$DOWNLOAD_DONE'; tmux kill-session -t setup"

echo
echo "Downloading model..."

while [[ ! -f "$DOWNLOAD_DONE" ]]; do
  sleep 5
done

echo "Model download complete."

# ------------------------------------------------------------
# Start llama-server
# ------------------------------------------------------------

echo
echo "Starting llama-server..."

nohup "$LLAMA_SERVER" \
  -m "${MODEL_DIR}/${MODEL}" \
  -ngl 99 \
  -c 8192 \
  -fa on \
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

# ------------------------------------------------------------
# Wait for server
# ------------------------------------------------------------

echo "Waiting for llama-server..."

while true; do
  if grep -q "llama_server: listening on " "$LOG_FILE" 2>/dev/null; then
    echo "llama-server is ready."
    break
  fi

  if grep -qiE "error:|error |fatal|failed|exception" "$LOG_FILE" 2>/dev/null; then
    echo "ERROR: llama-server failed to start."
    echo "----- llama-server log -----"
    cat "$LOG_FILE"
    echo "----------------------------"
    exit 1
  fi

  sleep 10
done

# ------------------------------------------------------------
# GPU status
# ------------------------------------------------------------

nvidia-smi \
  --query-gpu=name,memory.used,memory.total,utilization.gpu,temperature.gpu \
  --format=csv,noheader


END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo
echo "========================================"
echo "Setup completed successfully."
printf 'Total elapsed time: %02d:%02d:%02d\n' \
  $((ELAPSED / 3600)) \
  $(((ELAPSED % 3600) / 60)) \
  $((ELAPSED % 60))
echo "========================================"

exit 0
