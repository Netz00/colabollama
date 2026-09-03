#!/usr/bin/env bash
set -euo pipefail

# Versions - work with T4
CUDA_VERSION="12.8"
LLAMA_CPP_VERSION="master"

# Paths
CUDA_PATH="/usr/local/cuda-${CUDA_VERSION}"
LLAMA_CPP_DIR="${PWD}/llama.cpp"
ARTIFACT_DIR="${PWD}/artifacts"
ARTIFACT="${ARTIFACT_DIR}/llama-cpp-${LLAMA_CPP_VERSION}-cuda${CUDA_VERSION}-t4.tar.gz"

sudo apt-get update -qq
sudo apt-get install -y -qq build-essential cmake git wget
sudo apt-get remove -y nvidia-cuda-toolkit || true

wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb

sudo apt-get update -qq
sudo apt-get install -y "cuda-toolkit-12-8"

export PATH="${CUDA_PATH}/bin:${PATH}"
export CUDACXX="${CUDA_PATH}/bin/nvcc"

nvcc --version

rm -rf "${LLAMA_CPP_DIR}"

git clone \
  --depth 1 \
  --branch "${LLAMA_CPP_VERSION}" \
  https://github.com/ggml-org/llama.cpp.git \
  "${LLAMA_CPP_DIR}"

mkdir -p "${ARTIFACT_DIR}"

cd "${LLAMA_CPP_DIR}"

cmake -B build \
  -DGGML_CUDA=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_ARCHITECTURES=75 \
  -DCMAKE_CUDA_COMPILER="${CUDACXX}"

cmake --build build \
  --config Release \
  -j"$(nproc)"

tar -czf \
  "${ARTIFACT}" \
  -C "${LLAMA_CPP_DIR}" \
  build/

echo "Validating artifact..."

test -f "${ARTIFACT}"
test -s "${ARTIFACT}"

tar -tzf "${ARTIFACT}" | grep -q '^build/'

echo "Artifact successfully created:"
ls -lh "${ARTIFACT}"