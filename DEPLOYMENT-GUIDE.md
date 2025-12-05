# llama.cpp Kubernetes Deployment Guide for Dual Qwen2.5 14B Models

## Hardware Configuration

- **GPU:** NVIDIA RTX 5080 (16GB VRAM, Compute Capability 12.0)
- **RAM:** 64GB System Memory
- **Models:** 2x Qwen2.5 14B Q4_K_M (8.4GB each)
- **Kubernetes Node:** 172.22.22.57
- **Storage:** local-path (rancher.io/local-path)

---

## 1. Container Image Recommendation

### Recommended Image

**Image:** `ghcr.io/ggml-org/llama.cpp:server-cuda`

**Why This Image:**

- Official CUDA-enabled llama.cpp server from ggml-org
- Pre-compiled with CUDA support for NVIDIA GPUs
- Compatible with RTX 5080 (Blackwell architecture, Compute Capability 12.0)
- Includes CUDA 12.8 support with Flash Attention optimizations
- Lightweight server-only image (no unnecessary tools)
- Regularly updated with latest llama.cpp improvements

**Alternative Tags:**

- `ghcr.io/ggml-org/llama.cpp:full-cuda` - includes additional tools
- `ghcr.io/ggml-org/llama.cpp:light-cuda` - minimal runtime only
- Specific builds: `server-cuda-b7278` (pinned version)

---

## 2. GPU Memory Calculations for Qwen2.5 14B Q4_K_M

### Model Architecture

- **Model:** Qwen2.5-14B-Instruct
- **Total Parameters:** 14.7B (13.1B non-embedding)
- **Transformer Layers:** 48 layers
- **Attention Heads:** 40 Query (Q), 8 Key-Value (KV) - Grouped Query Attention (GQA)
- **Context Length:** Up to 131,072 tokens (generation up to 8,192)

### VRAM Breakdown for Q4_K_M Quantization

**Per Model VRAM Usage:**

1. **Model Weights:** ~8.4GB (Q4_K_M quantized file size)

2. **CUDA Overhead:** ~0.55GB
   - cuBLAS buffers
   - Runtime allocations
   - Graph memory

3. **KV Cache (context-dependent):**
   - Formula: `2 × n_layers × n_kv_heads × d_head × ctx_size × bytes_per_element`
   - For Qwen2.5 14B with GQA (8 KV heads):
     - 32K context: ~3.2GB
     - 16K context: ~1.6GB
     - 8K context: ~0.8GB

4. **Scratchpad Memory:** ~0.3GB
   - Temporary buffers for computation

**Total VRAM per Configuration:**

| Context Size | Model + Overhead | KV Cache | Total VRAM |
|--------------|------------------|----------|------------|
| 8K tokens    | 8.95GB          | 0.8GB    | ~9.75GB    |
| 16K tokens   | 8.95GB          | 1.6GB    | ~10.55GB   |
| 32K tokens   | 8.95GB          | 3.2GB    | ~12.15GB   |
| 65K tokens   | 8.95GB          | 6.5GB    | ~15.45GB   |

### Optimal --n-gpu-layers Configuration

**Qwen2.5 14B has 48 transformer layers**

**Scenario 1: Single Model (Coding - Max Performance)**

- `--n-gpu-layers 48` (all layers on GPU)
- Context: 32K tokens
- VRAM: ~12.15GB
- Remaining: ~3.85GB buffer
- **Status:** Fits comfortably

**Scenario 2: Dual Models Simultaneously**

**Strategy: Split GPU resources**

- **Coding Model (Priority):**
  - `--n-gpu-layers 48` (all layers)
  - Context: 32K tokens
  - VRAM: ~12.15GB

- **Chat Model (Hybrid GPU/RAM):**
  - `--n-gpu-layers 24` (half layers on GPU)
  - Context: 16K tokens
  - VRAM: ~5.3GB (half model + reduced cache)
  - RAM: ~5GB (remaining layers)

- **Combined VRAM:** ~17.45GB
- **Status:** EXCEEDS 16GB - NOT POSSIBLE SIMULTANEOUSLY

**Recommended Approach:**

Run models **sequentially** or use a **shared GPU with time-slicing**, OR run only **one model at a time** based on workload needs.

---

## 3. Dual Model Deployment Strategy

### Can Both Models Run Simultaneously?

**Short Answer:** NO - with full GPU acceleration for both

**Detailed Analysis:**

The RTX 5080 with 16GB VRAM cannot run both models simultaneously with optimal GPU offloading. Here are your options:

#### Option A: Single Model at a Time (RECOMMENDED)

Deploy both services, but only run one at a time based on workload:

- **Coding tasks:** Use Qwen2.5-Coder-14B with full GPU (48 layers, 32K context)
- **Chat tasks:** Use Qwen2.5-14B-Instruct with full GPU (48 layers, 16K context)
- **Method:** Scale down the unused deployment to 0 replicas

#### Option B: Hybrid GPU/RAM for Simultaneous Operation

- **Coding Model:** 48 GPU layers, 32K context (~12.15GB VRAM)
- **Chat Model:** 10-15 GPU layers, 8K context (~3.5GB VRAM)
- **Total:** ~15.65GB VRAM (fits in 16GB)
- **Trade-off:** Chat model will be significantly slower due to CPU processing

#### Option C: Time-Sliced GPU (MIG Alternative)

NVIDIA RTX 5080 doesn't support MIG, but you can use:

- NVIDIA Time-Slicing GPU Sharing (requires device plugin configuration)
- Both pods share GPU with round-robin scheduling
- Adds latency but allows concurrent access

### Recommended Configuration

**Use Option A:** Deploy both services but run one at a time. This gives you:

- Maximum performance for each model
- Full GPU acceleration (48/48 layers)
- Large context windows (32K for coding, 16K for chat)
- Easy switching via kubectl scale

---

## 4. Complete Kubernetes Manifests

See `kubernetes-manifests.yaml` for the complete deployment configuration.

### Key Features

**Namespace:** `llm-inference`

**Storage:**

- PersistentVolume with hostPath to `/home/raphi/git/models`
- ReadOnlyMany access mode (models are static)

**Deployments:**

1. **qwen-coder-14b**
   - Full GPU acceleration (48 layers)
   - 32K context window
   - NodePort: 30080

2. **qwen-chat-14b**
   - Hybrid mode (24 GPU layers for simultaneous operation)
   - 16K context window
   - NodePort: 30081

**Resource Limits:**

- GPU: 1 per deployment
- Memory: 16Gi request, 24Gi limit
- CPU: 4 cores request, 8 cores limit

---

## 5. llama-server Command Lines

### Coding Model (Qwen2.5-Coder-14B-Instruct)

```bash
/llama-server \
  --model /models/Qwen2.5-Coder-14B-Instruct-Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --n-gpu-layers 48 \
  --ctx-size 32768 \
  --n-batch 2048 \
  --n-ubatch 512 \
  --threads 8 \
  --flash-attn 1 \
  --metrics \
  --log-format json
```

**Parameters Explained:**

- `--n-gpu-layers 48`: All transformer layers on GPU
- `--ctx-size 32768`: 32K token context for large codebases
- `--n-batch 2048`: Large batch for prompt processing throughput
- `--n-ubatch 512`: Micro-batch size for generation
- `--threads 8`: CPU threads for auxiliary tasks
- `--flash-attn 1`: Enable Flash Attention 2 (15% throughput boost on CUDA)

### Chat Model (Qwen2.5-14B-Instruct)

```bash
/llama-server \
  --model /models/Qwen2.5-14B-Instruct-Q4_K_M.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --n-gpu-layers 24 \
  --ctx-size 16384 \
  --n-batch 1024 \
  --n-ubatch 256 \
  --threads 8 \
  --flash-attn 1 \
  --metrics \
  --log-format json
```

**Parameters Explained:**

- `--n-gpu-layers 24`: Half layers on GPU for hybrid operation
- `--ctx-size 16384`: 16K context (sufficient for most conversations)
- `--n-batch 1024`: Medium batch size
- `--n-ubatch 256`: Smaller micro-batch for memory efficiency
- `--threads 8`: More CPU work for RAM-based layers

---

## 6. Memory Usage Estimates

### Coding Model (Full GPU - 48/48 layers)

| Resource | Usage |
|----------|-------|
| VRAM | 12.15GB (model + 32K cache) |
| System RAM | ~4GB (overhead + buffers) |
| **Total** | **12.15GB VRAM + 4GB RAM** |

### Chat Model (Hybrid - 24/48 GPU layers)

| Resource | Usage |
|----------|-------|
| VRAM | ~5.3GB (half model + 16K cache) |
| System RAM | ~9GB (24 CPU layers + buffers) |
| **Total** | **5.3GB VRAM + 9GB RAM** |

### Simultaneous Operation (Hybrid Mode)

| Resource | Combined Usage |
|----------|----------------|
| VRAM | ~17.45GB (**EXCEEDS 16GB**) |
| System RAM | ~13GB |
| **Feasible** | **NO** (VRAM overflow) |

### Alternative Simultaneous Setup

**Coding Model:** 48 GPU layers, 32K context = 12.15GB VRAM

**Chat Model:** 10 GPU layers, 8K context = 3.5GB VRAM

**Total:** ~15.65GB VRAM + ~10GB RAM = **FITS**

---

## 7. Deployment Instructions

### Prerequisites

1. **NVIDIA Container Toolkit installed on Kubernetes node:**

```bash
# Verify GPU access
kubectl run gpu-test --image=nvidia/cuda:12.8.0-base-ubuntu20.04 --rm -it --restart=Never -- nvidia-smi
```

2. **Get your actual node hostname:**

```bash
kubectl get nodes -o wide
```

Replace `node-with-gpu` in the manifests with your actual hostname.

3. **Verify model files exist:**

```bash
ls -lh /home/raphi/git/models/
# Should show:
# Qwen2.5-Coder-14B-Instruct-Q4_K_M.gguf (~8.4GB)
# Qwen2.5-14B-Instruct-Q4_K_M.gguf (~8.4GB)
```

### Deploy to Kubernetes

```bash
# Create namespace and deploy resources
kubectl apply -f kubernetes-manifests.yaml

# Check deployment status
kubectl get all -n llm-inference

# Watch pod startup
kubectl logs -n llm-inference -l app=qwen-coder-14b -f

# Check GPU allocation
kubectl describe pod -n llm-inference -l app=qwen-coder-14b | grep -A 5 "Limits"
```

### Access the Services

**Coding Model:**

```bash
# Via NodePort
curl http://172.22.22.57:30080/health

# OpenAI-compatible API
curl http://172.22.22.57:30080/v1/models
```

**Chat Model:**

```bash
# Via NodePort
curl http://172.22.22.57:30081/health

# OpenAI-compatible API
curl http://172.22.22.57:30081/v1/models
```

### Test Inference

```bash
# Coding model test
curl http://172.22.22.57:30080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder-14b",
    "messages": [{"role": "user", "content": "Write a Python function to sort a list"}],
    "max_tokens": 500
  }'

# Chat model test
curl http://172.22.22.57:30081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-14b",
    "messages": [{"role": "user", "content": "Hello! How are you?"}],
    "max_tokens": 100
  }'
```

---

## 8. Answers to Key Questions

### Q: Maximum Context Size Achievable?

**Coding Model (Full GPU):**

- **32K tokens** comfortably (12.15GB VRAM)
- **65K tokens** possible (15.45GB VRAM - tight fit)
- **131K tokens** (model max) - NO, requires ~25GB VRAM

**Chat Model (Full GPU):**

- **16K tokens** recommended (10.55GB VRAM)
- **32K tokens** possible (12.15GB VRAM)
- **65K tokens** possible (15.45GB VRAM - tight fit)

**Flash Attention Benefit:**

Flash Attention (enabled with `--flash-attn 1`) provides:

- 15% throughput improvement on CUDA
- Better memory efficiency for longer contexts
- No downsides on RTX 5080 (NVIDIA GPU with compute capability 12.0)

### Q: Can Both Models Run Simultaneously?

**Short Answer:** Not both with full GPU acceleration

**Options:**

1. **No (Recommended):** Run one at a time, scale the other to 0 replicas
   - Best performance for each
   - Full GPU utilization
   - Maximum context windows

2. **Yes (Degraded):** Hybrid configuration
   - Coding: 48 GPU layers, 32K context (12.15GB)
   - Chat: 10 GPU layers, 8K context (3.5GB)
   - Total: 15.65GB VRAM (fits)
   - Chat model will be 3-5x slower

3. **Yes (Advanced):** NVIDIA Time-Slicing
   - Requires device plugin reconfiguration
   - Adds scheduling latency
   - Not recommended for production

### Q: Better Model Alternatives for This Hardware?

**For 16GB VRAM:**

1. **Current Choice (Excellent):**
   - Qwen2.5-Coder-14B-Q4_K_M: Best coding model for 16GB
   - Qwen2.5-14B-Q4_K_M: Best chat model for 16GB
   - Q4_K_M quantization: Optimal quality/size balance

2. **Higher Quantization (More Quality):**
   - Qwen2.5-7B-Q8_0: 8-bit quantization, better quality, fits easily
   - Trade-off: Smaller model (7B vs 14B parameters)

3. **Larger Models (Hybrid):**
   - Qwen2.5-32B-Q4_K_M: 19GB file size
   - Needs 30-35 GPU layers offloaded, rest in RAM
   - Slower but more capable

4. **Specialized Alternatives:**
   - **Coding:** DeepSeek-Coder-V2-Lite-Instruct 16B Q4_K_M
   - **Chat:** Llama-3.1-8B-Instruct-Q8_0 (smaller, higher quality)
   - **Math:** Qwen2.5-Math-14B-Q4_K_M

**Recommendation:**

Stick with **Qwen2.5-Coder-14B-Q4_K_M** and **Qwen2.5-14B-Q4_K_M**. These are optimal for your 16GB VRAM and provide:

- Excellent performance (14B parameter models)
- Good quality (Q4_K_M quantization)
- Reasonable context windows (32K/16K)
- Best-in-class for coding and chat tasks

---

## 9. RTX 5080 Specific Optimizations

### Compute Capability 12.0 (Blackwell Architecture)

**Supported Features:**

- CUDA 12.8 compatibility
- Flash Attention 2 (15% speedup)
- Tensor Cores for matrix operations
- High memory bandwidth (448 GB/s)

**Flash Attention Configuration:**

```bash
# Always enable flash attention for RTX 5080
--flash-attn 1
```

**Benefits:**

- Reduced memory footprint for attention computation
- 10-15% faster prompt processing
- Enables longer context windows with same VRAM

**Important Notes:**

- Flash Attention 3 is not yet stable for Blackwell
- Use Flash Attention 2 (default in llama.cpp CUDA build)
- ROCm (AMD) does NOT benefit from flash attention (CUDA-only optimization)

---

## 10. Monitoring and Troubleshooting

### Monitor GPU Usage

```bash
# From Kubernetes node
nvidia-smi -l 1

# From inside pod
kubectl exec -n llm-inference -it deployment/qwen-coder-14b -- nvidia-smi
```

### Check Metrics

```bash
# Prometheus metrics endpoint
curl http://172.22.22.57:30080/metrics
```

### Common Issues

**1. Pod stuck in Pending:**

```bash
# Check GPU availability
kubectl describe node | grep nvidia.com/gpu

# Check events
kubectl describe pod -n llm-inference -l app=qwen-coder-14b
```

**2. CUDA out of memory:**

Reduce context size or GPU layers:

```bash
# Lower context
--ctx-size 16384

# Or reduce GPU layers
--n-gpu-layers 40
```

**3. Slow inference:**

Check layer distribution:

```bash
# Check logs for layer offload confirmation
kubectl logs -n llm-inference -l app=qwen-coder-14b | grep "offload"
```

### Performance Tuning

**For Maximum Speed:**

```bash
--n-gpu-layers 48    # All layers on GPU
--n-batch 2048       # Large batch
--flash-attn 1       # Enable flash attention
--threads 8          # Match physical cores
```

**For Maximum Context:**

```bash
--n-gpu-layers 48
--ctx-size 65536     # 65K context (uses ~15.4GB VRAM)
--n-batch 512        # Smaller batch to save memory
--flash-attn 1
```

---

## Sources

### Container Images

- [GitHub - ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
- [llama.cpp Docker Documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/docker.md)
- [Package llama.cpp on GitHub](https://github.com/ggml-org/llama.cpp/pkgs/container/llama.cpp)

### VRAM Calculations

- [VRAM Calculator for Local Open Source LLMs](https://localllm.in/blog/interactive-vram-calculator)
- [Ollama VRAM Requirements Guide 2025](https://localllm.in/blog/ollama-vram-requirements-for-local-llms)
- [Why does llama.cpp use so much VRAM](https://github.com/ggml-org/llama.cpp/discussions/9784)

### RTX 5080 & Flash Attention

- [LM Studio Accelerates LLM Performance With NVIDIA GeForce RTX GPUs](https://blogs.nvidia.com/blog/rtx-ai-garage-lmstudio-llamacpp-blackwell/)
- [Performance of llama.cpp on Nvidia CUDA](https://github.com/ggml-org/llama.cpp/discussions/15013)

### llama-server Parameters

- [llama.cpp guide - Running LLMs locally](https://blog.steelph0enix.dev/posts/llama-cpp-guide/)
- [llama-server Debian Manual](https://manpages.debian.org/unstable/llama.cpp-tools/llama-server.1.en.html)
- [guide: running gpt-oss with llama.cpp](https://github.com/ggml-org/llama.cpp/discussions/15396)

### Model Architecture

- [Qwen2.5-14B-Instruct on Hugging Face](https://huggingface.co/Qwen/Qwen2.5-14B-Instruct)
- [Qwen2.5-14B on Hugging Face](https://huggingface.co/Qwen/Qwen2.5-14B)
- [Qwen2.5: A Party of Foundation Models](https://qwenlm.github.io/blog/qwen2.5/)

### KV Cache Calculations

- [How to calculate the required memory for context size](https://github.com/ggml-org/llama.cpp/discussions/10068)
- [How to calculate size of KV cache](https://www.rohan-paul.com/p/how-to-calculate-size-of-kv-cache)
- [LLM Inference Series: 4. KV caching, a deeper look](https://medium.com/@plienhar/llm-inference-series-4-kv-caching-a-deeper-look-4ba9a77746c8)
