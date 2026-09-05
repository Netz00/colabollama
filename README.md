# Ollama on Google Colab GPU

Run **Ollama on a Google Colab T4 GPU** and access it locally through an OpenAI-compatible API.

## How it works

The project consists of two parts:

1. **Build** — GitHub Actions builds and releases a CUDA-enabled, T4-optimized `llama.cpp` binary.
2. **Colab setup** — the setup script downloads the `llama.cpp` build and model, starts Ollama, and exposes the API through an SSH tunnel.

Ollama uses the `llama.cpp` build produced by this project. The standard Ollama installation was also tested, but performed worse on the T4 in my tests.

The **Colab T4 handles inference**, while the **local machine runs the client or coding agent**.

## Configured Model

- **Model:** [`zai-org_GLM-4.7-Flash-IQ3_M.gguf`](https://huggingface.co/bartowski/zai-org_GLM-4.7-Flash-GGUF/blob/main/zai-org_GLM-4.7-Flash-IQ3_M.gguf)
- **Base model:** [`zai-org/GLM-4.7-Flash`](https://huggingface.co/zai-org/GLM-4.7-Flash)
- **Quantization:** IQ3_M

## Requirements

- Google Colab with an NVIDIA T4
- Linux
- Python
- `colab` CLI
- SSH

> Tested only on Linux.

## Configure SSH once

```
nano ~/.ssh/config
```

Add:

```
Host colab-llm-t4
    ProxyCommand colab ssh --proxy-mode -s colab-llm-t4
    User root
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

## Start Ollama

Start the T4 runtime and Ollama:

```
run_session_id="colab-llm-t4"

colab new --session "$run_session_id" --gpu T4

colab ssh -s "$run_session_id" < scripts/start-ollama.sh
```

Create the SSH tunnel:

```
ssh -L 8000:localhost:8000 "$run_session_id"
```

The API is then available locally at:

```
http://localhost:8000
```

Stop the Colab session when finished:

```
colab stop -s "$run_session_id"
```

## Local AI Coding Agent

The Ollama endpoint can be used by local AI coding agents that support OpenAI-compatible APIs.

For the recommended coding-agent setup, see:

https://github.com/earendil-works/pi

## Performance

Tested in August 2026 using the Google Colab free tier.

### Hardware

| ComponentValue     |                       |
| ------------------ | --------------------- |
| GPU                | NVIDIA Tesla T4       |
| VRAM               | 15 GB                 |
| Driver             | 580.82.07             |
| CUDA               | 13.0                  |
| CPU                | Intel Xeon @ 2.00 GHz |
| vCPU               | 2                     |
| RAM                | 12 GB                 |
| Architecture       | x86_64                |
| Compute Capability | 7.5 (Turing)          |
| Virtualization     | KVM                   |

### Results

| MetricResult           |                |
| ---------------------- | -------------- |
| Generation speed       | **42.6 tok/s** |
| Prompt processing      | 89.4 tok/s     |
| Prompt tokens          | 15             |
| Generated tokens       | 500            |
| Generation time        | 11.72 s        |
| Prompt processing time | 0.17 s         |

Results are specific to the tested T4 environment and model. Different Colab plans or GPUs may require changes to the CUDA/architecture settings.
