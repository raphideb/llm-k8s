# Parallel Agent Prompt: llama.cpp on Kubernetes with NVIDIA GPU

## Context & Environment

**Hardware:**

- 64GB RAM
- NVIDIA RTX 5080 GPU (16GB VRAM)
- WSL2 on Windows with Debian 13 (trixie)

**Current State:**

- NVIDIA driver already working: Driver 581.42, CUDA 13.0
- Single-node Kubernetes cluster "plexus" running on WSL2
- Container runtime: Docker 26.1.5
- Storage class: `local-path` (rancher.io/local-path) - default
- Calico CNI networking installed
- Metrics server and Prometheus monitoring stack present

**Models Available (at /home/raphi/git/models/):**

- `Qwen2.5-Coder-14B-Instruct-Q4_K_M.gguf` (8.4GB) - for coding tasks
- `Qwen2.5-14B-Instruct-Q4_K_M.gguf` (8.4GB) - for chat tasks

**Requirements:**

- Context window: minimum 32k tokens (or optimal for hardware)
- Coding model: primarily use GPU VRAM
- Chat model: can use RAM if needed
- Services exposed via NodePort (no port-forwarding needed)
- Install opencode from opencode.ai for IDE integration

---

## Agent 1: NVIDIA Kubernetes GPU Integration

**Objective:** Research and plan the complete GPU setup for Kubernetes on WSL2.

**Tasks:**

1. **Verify WSL2 GPU passthrough requirements:**
   - Confirm NVIDIA Container Toolkit setup for WSL2
   - Check if additional WSL configuration is needed
   - Verify Docker runtime GPU support

2. **Kubernetes NVIDIA Device Plugin:**
   - Research the nvidia-device-plugin-daemonset deployment
   - Determine if nvidia-container-runtime needs special config for WSL2
   - Check compatibility with CUDA 13.0 and driver 581.42

3. **Container Runtime Configuration:**
   - Docker daemon configuration for nvidia runtime
   - RuntimeClass setup in Kubernetes if needed
   - Node labeling for GPU scheduling

4. **Validation Steps:**
   - Commands to verify GPU is visible to containers
   - Test pod specification for GPU access

**Output Required:**

- List all packages/tools needed (with exact versions if critical)
- Provide shell commands for installation and configuration
- Include Kubernetes manifests for NVIDIA device plugin
- Provide test commands to validate GPU access works

---

## Agent 2: llama.cpp Kubernetes Deployment

**Objective:** Design the llama.cpp deployment on Kubernetes with optimal GPU utilization.

**Tasks:**

1. **llama.cpp Server Options:**
   - Research llama.cpp server mode (llama-server)
   - Evaluate container images: ghcr.io/ggml-org/llama.cpp or alternatives
   - Determine best image tag for CUDA 13.0 support

2. **GPU Memory Optimization:**
   - Calculate optimal `--n-gpu-layers` for 14B Q4_K_M models on 16GB VRAM
   - Determine context size (--ctx-size) that fits in memory
   - Configure `--n-batch` for throughput vs latency trade-off

3. **Dual Deployment Strategy:**
   - **Coding Model** (priority GPU): Maximum GPU layers, VRAM-focused
   - **Chat Model** (hybrid): Partial GPU offload, can use system RAM

4. **Kubernetes Resources:**
   - Deployment manifests with GPU resource requests
   - NodePort Services for external access
   - ConfigMaps for model configurations
   - PersistentVolumeClaims for model storage (or hostPath)
   - Resource limits (memory, GPU)

5. **llama.cpp Server Configuration:**
   - OpenAI-compatible API endpoint setup
   - Optimal parameters for RTX 5080 (compute capability 12.0)

**Output Required:**

- Complete Kubernetes manifests (Deployment, Service, PVC/hostPath, ConfigMap)
- Recommended llama-server parameters for both models
- GPU layer calculations and reasoning
- NodePort assignments (suggest ports)

---

## Agent 3: opencode Installation & Integration

**Objective:** Install opencode from opencode.ai and configure it to use the llama.cpp endpoints.

**Tasks:**

1. **opencode Installation:**
   - Research installation methods for Debian 13
   - Check dependencies and prerequisites
   - Installation commands

2. **Configuration for llama.cpp:**
   - Configure opencode to use local llama.cpp OpenAI-compatible API
   - Set up coding model endpoint for code completion/generation
   - Configure chat model endpoint if supported

3. **Integration Testing:**
   - Commands to verify opencode connects to llama.cpp
   - Test code completion functionality

4. **Alternative Clients (if applicable):**
   - Document any other clients that work with llama.cpp's OpenAI API
   - VS Code extensions, CLI tools, etc.

**Output Required:**

- Installation commands for opencode
- Configuration file examples
- Environment variables if needed
- Testing/validation steps

---

## Shared Deliverable: Setup Script Requirements

After all agents complete their research, collaborate to produce a **unified setup script** with these characteristics:

**Script Requirements:**

1. **Pre-flight Checks:**
   - Detect existing NVIDIA driver installation
   - Check Docker daemon status and nvidia runtime
   - Verify Kubernetes cluster connectivity
   - List available storage classes
   - Check if NVIDIA device plugin already deployed
   - Verify models exist at expected path

2. **Modular Installation:**
   - Each component should be installable independently
   - Skip already-installed components
   - Clear progress indicators

3. **Components to Install (if missing):**
   - NVIDIA Container Toolkit (if not present)
   - Docker nvidia runtime configuration
   - NVIDIA Kubernetes device plugin
   - llama.cpp deployments (coding + chat)
   - opencode

4. **Configuration:**
   - Generate Kubernetes manifests dynamically based on detected storage class
   - Use NodePort services with configurable ports
   - Support custom model paths

5. **Validation:**
   - Health checks after each component installation
   - Final end-to-end test

**Script Format:**

- Bash script for Debian/WSL2
- Use functions for each component
- Include `--dry-run` option to show what would be done
- Colored output for status messages
- Log file generation

---

## Expected Final Output Structure

```
setup-llama-k8s/
├── setup.sh                     # Main setup script
├── manifests/
│   ├── nvidia-device-plugin.yaml
│   ├── llama-coding-deployment.yaml
│   ├── llama-chat-deployment.yaml
│   ├── llama-coding-service.yaml
│   └── llama-chat-service.yaml
├── config/
│   └── opencode-config.example
└── README.md                    # Usage instructions
```

---

## Technical Constraints

- Node IP for services: 172.22.22.57 (or use $(hostname -I | awk '{print $1}'))
- Models path: /home/raphi/git/models/
- Preferred ports: 8080 (coding), 8081 (chat) - or suggest better alternatives
- Kubernetes namespace: `llama` (create if not exists)
- Do not use Helm - plain manifests preferred for simplicity

---

## Questions to Answer

1. Can both models run simultaneously given 16GB VRAM + 64GB RAM?
2. What's the maximum context size achievable for each model?
3. Is there a better quantization or model size for this hardware?
4. Should we use Flash Attention if available?
5. What are the recommended batch sizes for coding vs chat workloads?
