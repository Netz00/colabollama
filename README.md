# Ollama on Google Colab GPU — PoC

A small proof of concept for running **Ollama as a remote LLM server on a Google Colab GPU** and accessing it from a local machine through an OpenAI-compatible API.

The Colab runtime provides the GPU for model inference, while the local machine runs the client or coding agent.

The setup uses a CUDA-enabled `llama.cpp` build and Google Drive to persist the build artifact between Colab sessions.

> **Prerequisites:** Python, Google Colab, and a Linux environment.
>
> **Tested only on Linux.**

**Testing scope:** This PoC was tested in August 2026 using the Google Colab free tier, with approximately 5 hours of T4 GPU runtime per Google account available in my testing. The scripts were written and tested for a T4. If using a paid Colab plan or a different GPU, the scripts and CUDA/architecture settings may need to be adjusted accordingly.

## 1st-time setup — Build llama.cpp with CUDA

Build `llama.cpp` with CUDA support on a CPU runtime to avoid using GPU time for compilation. In my test, the build took approximately **1 hour** and produced a **~300 MB** compressed artifact stored on Google Drive.

> **Performance note:** I also tested the simpler Ollama installation approach. In my tests, it performed worse on the T4 than this T4-targeted `llama.cpp` build, so I kept the optimized `llama.cpp` approach for this PoC.

### 1. Start a build session

```bash
build_session_id="build-llama"

colab new --session "$build_session_id"
```

### 2. Mount Google Drive

```bash
colab drivemount -s "$build_session_id"
```

### 3. Run the build script

Send the build script to the Colab session:

```bash
colab ssh -s "$build_session_id" < src/build-llama.sh
```

Then run it:

```bash
bash build-llama.sh
```

The script will:

- Install CUDA 12.8 and build dependencies
- Clone `llama.cpp`
- Build it with CUDA support for the **T4 (`sm_75`)**
- Create a compressed build artifact
- Store the artifact in Google Drive

### 4. Verify the artifact

Check Google Drive and confirm that the `llama.cpp` artifact was created successfully.

### 5. Stop the build runtime

Once the artifact is safely stored, stop the Colab runtime to avoid unnecessary runtime usage:

```bash
colab sessions

colab stop -s "$build_session_id"

colab sessions
```

## Start Ollama

Configure SSH once:

```bash
nano ~/.ssh/config
```

Add:

```sshconfig
Host colab-llm-t4
    ProxyCommand colab ssh --proxy-mode -s colab-llm-t4
    User root
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

Start the T4 runtime and Ollama:

```bash
run_session_id="colab-llm-t4"

colab new --session "$run_session_id" --gpu T4
colab drivemount -s "$run_session_id"
colab ssh -s "$run_session_id" < scripts/start-ollama.sh
```

Create the SSH tunnel:

```bash
ssh -L 8000:localhost:8000 "$run_session_id"
```

Open http://localhost:8000/ to test it.

Stop the session when finished to save credits:

```bash
colab stop -s "$run_session_id"
```

---

## Local AI Coding Agents / CLI Shims — Testing Notes

Tested in **August 2026** on **Fedora** with:

- **Model:** `qwen2.5-coder-14b-instruct-q5_k_m`
- **Inference:** `llama.cpp`
- **API:** OpenAI-compatible endpoint
- **Terminal:** Terminator

I tested the shims with simple repository tasks, including asking them to locate a test file such as `test_main`. The goal was to verify basic repository inspection, tool execution, and applying changes.

The same model and OpenAI-compatible endpoint were also tested independently and responded correctly. The configured model ID was verified against `/v1/models`.

The following are personal test results from this setup.

### Anomalyco/OpenCode

OpenCode did not produce a usable agent workflow.

<details>
<summary><strong>Details</strong></summary>

Simple prompts resulted in repeated output such as:

> _Objection > work state > active > blocked > next move..._

I could not copy the generated output from the Terminator terminal emulator as expected.

The same model and endpoint worked correctly when tested independently. I also changed the OpenCode model ID to exactly match the ID returned by `/v1/models`; the behavior did not change.

I spent approximately 20 minutes troubleshooting the setup without reaching a working configuration.

</details>

### Aider-AI/aider

Aider required files to be explicitly added before it could inspect them.

<details>
<summary><strong>Details</strong></summary>

A documentation prompt continued to appear after selecting `D` ("Don't ask again"):

> Open documentation url for more info? (Y)es/(N)o/(D)on't ask again [Yes]: D

When asked to locate a test file, for example:

`find test_main location`

Aider did not run `find` against the repository. It reported that it could not access files that had not been explicitly added.

</details>

### Cline

Cline did not execute tool calls correctly with the local model.

<details>
<summary><strong>Details</strong></summary>

Instead of executing a tool, it generated tool-call structures as plain text, for example:

```text
<tools> {"name": "read_files", ...} </tools>
```

Prompting it to "do it" again resulted in the same tool call being generated again.

Observed behavior:

`Qwen → tool-call text → nothing happens → repeat`

</details>

### aaif-goose/goose

Goose did not perform basic agent actions reliably in this setup.

<details>
<summary><strong>Details</strong></summary>

I tried changing the configuration and tweaking extensions, but I was still unable to get it to perform simple repository actions.

</details>

### IntelliJ AI

IntelliJ AI was the easiest to use in this test.

<details>
<summary><strong>Details</strong></summary>

Files or code snippets could be selected and sent as context to the AI.

However, changes still had to be applied manually because automatic change application did not work reliably in my test.

</details>

### Conclusion

In this setup, the direct model/API path worked correctly, while the tested agent integrations had issues with **tool execution, repository access, or applying changes**.

IntelliJ AI provided the most usable workflow of the tested options, but still required manual change application.
