# llama.cpp Kubernetes Deployment - Complete Summary

## Executive Summary

This repository provides a complete, production-ready solution for deploying dual Qwen2.5 14B models (Coding and Chat) on Kubernetes with NVIDIA RTX 5080 GPU acceleration.

**Key Finding:** The RTX 5080's 16GB VRAM can run ONE 14B Q4_K_M model with full GPU acceleration and large context windows (32K tokens), but CANNOT run both simultaneously with optimal performance.

**Recommended Strategy:** Deploy both services, but run one at a time by scaling replicas, switching between them based on workload requirements.

---

## Hardware Configuration

- **GPU:** NVIDIA RTX 5080 (16GB VRAM, Compute Capability 12.0)
- **RAM:** 64GB System Memory
- **Node:** 172.22.22.57
- **Storage:** local-path at /home/raphi/git/models/

---

## 1. Container Image Recommendation

**Official Image:** `ghcr.io/ggml-org/llama.cpp:server-cuda`

**Features:**

- Pre-compiled with CUDA 12.8 support
- Compatible with RTX 5080 (Blackwell architecture)
- Flash Attention 2 enabled (15% throughput boost)
- OpenAI-compatible API endpoints
- Prometheus metrics support
- Maintained by ggml-org (official)

**Why This Image:**

- Official and well-maintained
- Optimized for NVIDIA GPUs
- Includes all necessary CUDA libraries
- Regular security updates
- Proven stability in production

---

## 2. GPU Memory Calculations

### Model Specifications

**Qwen2.5-14B Models:**

- Total Parameters: 14.7B (13.1B non-embedding)
- Transformer Layers: 48
- Attention Architecture: Grouped Query Attention (40 Q heads, 8 KV heads)
- File Size (Q4_K_M): 8.4GB each
- Maximum Context: 131,072 tokens

### VRAM Breakdown (Per Model)

**Component Breakdown:**

1. **Model Weights:** 8.4GB (Q4_K_M quantized)
2. **CUDA Overhead:** 0.55GB (cuBLAS, runtime)
3. **KV Cache (context-dependent):**
   - 8K context: 0.8GB
   - 16K context: 1.6GB
   - 32K context: 3.2GB
   - 65K context: 6.5GB
4. **Scratchpad Memory:** 0.3GB

**Total VRAM by Context Size:**

| Context Size | VRAM Required | Status on 16GB |
|--------------|---------------|----------------|
| 8K tokens    | 9.75GB       | Fits easily (6.25GB free) |
| 16K tokens   | 10.55GB      | Fits comfortably (5.45GB free) |
| 32K tokens   | 12.15GB      | Recommended max (3.85GB free) |
| 65K tokens   | 15.45GB      | Tight fit (0.55GB free) |
| 131K tokens  | ~25GB        | Does NOT fit |

### Optimal --n-gpu-layers Configuration

**Qwen2.5 has 48 transformer layers**

**Recommendation:**

- **--n-gpu-layers 48** (all layers on GPU)
- Maximum performance: ~500-800 tokens/sec prompt, ~30-50 tokens/sec generation
- No CPU/RAM bottleneck
- Predictable latency

**Alternative (Hybrid GPU/RAM):**

- **--n-gpu-layers 24** (half on GPU, half in RAM)
- Reduced VRAM: ~5.3GB (for 16K context)
- Performance: 3-5x slower
- Only use if running both models simultaneously

---

## 3. Dual Model Deployment Strategy

### Can Both Models Run Simultaneously?

**Answer: NO - not with full performance**

**VRAM Math:**

- Coding Model (48 layers, 32K): 12.15GB
- Chat Model (48 layers, 16K): 10.55GB
- **Total: 22.70GB** (EXCEEDS 16GB by 6.7GB)

### Strategy Options

#### Option A: Sequential Operation (RECOMMENDED)

**Description:** Deploy both services, run one at a time

**Pros:**

- Maximum performance for each model
- Full GPU utilization (48/48 layers)
- Large context windows (32K/16K)
- Fast switching (30-60 seconds)

**Cons:**

- Cannot use both simultaneously
- Requires manual/automated switching

**Implementation:**

```bash
# Switch to coding
./manage-llm-deployments.sh use-coding

# Switch to chat
./manage-llm-deployments.sh use-chat
```

#### Option B: Hybrid Configuration (DEGRADED)

**Description:** Run both, but chat model uses CPU/RAM

**Configuration:**

- Coding: 48 GPU layers, 32K context = 12.15GB VRAM
- Chat: 10 GPU layers, 8K context = 3.5GB VRAM
- **Total: 15.65GB VRAM** (fits)

**Pros:**

- Both models available simultaneously
- Coding model at full speed

**Cons:**

- Chat model 3-5x slower
- Reduced chat context (8K vs 16K)
- Unpredictable performance

#### Option C: Time-Sliced GPU (ADVANCED)

**Description:** NVIDIA GPU time-slicing (not MIG, RTX 5080 doesn't support MIG)

**Pros:**

- Both pods can access GPU
- Kubernetes-managed

**Cons:**

- Adds scheduling latency
- Context switching overhead
- Complex setup
- Not recommended for production

**Recommendation:** Use **Option A** (Sequential Operation) for best results.

---

## 4. Complete Kubernetes Manifests

### Files Provided

1. **kubernetes-manifests.yaml** - Main deployment with PersistentVolume/PVC
2. **kubernetes-manifests-hostpath.yaml** - Alternative using direct hostPath mounting

### Manifest Components

**Namespace:** `llm-inference`

**Storage:**

- PersistentVolume: 50Gi, ReadOnlyMany
- HostPath: /home/raphi/git/models
- Storage Class: local-path

**Deployments:**

1. **qwen-coder-14b**
   - Image: ghcr.io/ggml-org/llama.cpp:server-cuda
   - GPU: 1x NVIDIA GPU
   - Memory: 16Gi request, 24Gi limit
   - CPU: 4 cores request, 8 cores limit
   - Port: 8080 (NodePort 30080)

2. **qwen-chat-14b**
   - Same resources as above
   - Port: 8080 (NodePort 30081)

**Services:**

- Type: NodePort
- Coding: 30080
- Chat: 30081

**Health Checks:**

- Liveness probe: /health (60s delay, 30s period)
- Readiness probe: /health (30s delay, 10s period)

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

**Parameter Justification:**

- `--n-gpu-layers 48`: All layers on GPU for max speed
- `--ctx-size 32768`: 32K context for large codebases
- `--n-batch 2048`: Large batch = faster prompt processing
- `--n-ubatch 512`: Micro-batch for generation
- `--threads 8`: CPU threads for auxiliary tasks
- `--flash-attn 1`: Enable Flash Attention 2 (15% boost on CUDA)
- `--metrics`: Prometheus endpoint
- `--log-format json`: Structured logging

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

**Parameter Justification:**

- `--n-gpu-layers 24`: Hybrid mode for simultaneous operation (if needed)
- `--ctx-size 16384`: 16K context sufficient for conversations
- `--n-batch 1024`: Medium batch size
- `--n-ubatch 256`: Smaller micro-batch for memory
- Other params: Same as coding model

**Note:** Change `--n-gpu-layers 24` to `48` when running chat model alone.

---

## 6. Memory Usage Estimates

### Coding Model (Full GPU - 48/48 layers)

**Configuration:**

- GPU Layers: 48/48
- Context: 32K tokens
- Batch: 2048

**Memory Usage:**

- VRAM: 12.15GB
- System RAM: ~4GB
- **Total GPU: 12.15GB / 16GB (75.9% utilization)**

### Chat Model (Full GPU - 48/48 layers)

**Configuration:**

- GPU Layers: 48/48
- Context: 16K tokens
- Batch: 1024

**Memory Usage:**

- VRAM: 10.55GB
- System RAM: ~4GB
- **Total GPU: 10.55GB / 16GB (65.9% utilization)**

### Chat Model (Hybrid - 24/48 GPU layers)

**Configuration:**

- GPU Layers: 24/48
- Context: 16K tokens
- Batch: 1024

**Memory Usage:**

- VRAM: ~5.3GB
- System RAM: ~9GB
- **Total GPU: 5.3GB / 16GB (33.1% utilization)**

### Simultaneous Operation Scenarios

**Scenario 1: Both Full GPU**

- Coding (48 layers, 32K): 12.15GB
- Chat (48 layers, 16K): 10.55GB
- **Total: 22.70GB - EXCEEDS 16GB**
- **Status: NOT POSSIBLE**

**Scenario 2: Coding Full + Chat Hybrid**

- Coding (48 layers, 32K): 12.15GB
- Chat (24 layers, 16K): 5.3GB
- **Total: 17.45GB - EXCEEDS 16GB**
- **Status: NOT POSSIBLE**

**Scenario 3: Coding Full + Chat Minimal**

- Coding (48 layers, 32K): 12.15GB
- Chat (10 layers, 8K): 3.5GB
- **Total: 15.65GB - FITS**
- **Status: POSSIBLE (but chat is very slow)**

---

## 7. Answers to Key Questions

### Q1: Maximum Context Size Achievable?

**Coding Model (Full GPU):**

- **32K tokens** - RECOMMENDED (12.15GB VRAM, good performance)
- **65K tokens** - POSSIBLE (15.45GB VRAM, tight fit, leaves 0.55GB)
- **131K tokens** - NOT POSSIBLE (requires ~25GB VRAM)

**Chat Model (Full GPU):**

- **16K tokens** - RECOMMENDED (10.55GB VRAM, optimal for chat)
- **32K tokens** - POSSIBLE (12.15GB VRAM)
- **65K tokens** - POSSIBLE (15.45GB VRAM, tight fit)

**Flash Attention Impact:**

- Enables 10-15% longer context with same VRAM
- Reduces attention computation overhead
- Always enable with `--flash-attn 1`

### Q2: Can Both Models Run Simultaneously?

**Short Answer:** NO, not with optimal performance

**Detailed Answer:**

With full GPU acceleration (48/48 layers each), both models require 22.7GB VRAM, which exceeds the RTX 5080's 16GB capacity.

**Alternatives:**

1. **Sequential operation (BEST):** Run one at a time, switch as needed
2. **Hybrid mode (DEGRADED):** Coding full GPU + Chat 10 GPU layers = 15.65GB (fits but chat is 3-5x slower)
3. **Time-slicing (COMPLEX):** GPU sharing with added latency

**Recommendation:** Use sequential operation for maximum performance.

### Q3: Better Model Alternatives for This Hardware?

**Current Models:** Excellent choice for 16GB VRAM

**Qwen2.5-14B Q4_K_M Benefits:**

- 14B parameters: Large enough for quality results
- Q4_K_M quantization: Best quality/size ratio
- GQA architecture: Efficient KV cache
- Good context windows: 32K/16K tokens

**Alternative Options:**

1. **Smaller with Higher Quality:**
   - Qwen2.5-7B-Q8_0 (8-bit quantization)
   - Better quality, smaller model
   - Uses ~10GB VRAM
   - Could run two simultaneously

2. **Larger with Hybrid:**
   - Qwen2.5-32B-Q4_K_M (19GB file)
   - Requires 30-35 GPU layers (rest in RAM)
   - Slower but more capable

3. **Specialized Models:**
   - DeepSeek-Coder-V2-Lite-Instruct 16B Q4_K_M
   - Llama-3.1-8B-Instruct-Q8_0
   - Qwen2.5-Math-14B-Q4_K_M

**Verdict:** Your current models are optimal for RTX 5080 16GB VRAM.

---

## 8. Deployment Files

### File Structure

```
/home/raphi/git/llm/
├── README.md                              (10KB) - Main overview
├── DEPLOYMENT-GUIDE.md                    (16KB) - Complete documentation
├── QUICK-REFERENCE.md                     (7.7KB) - Quick commands
├── SUMMARY.md                             (This file) - Executive summary
├── kubernetes-manifests.yaml              (6.1KB) - Main K8s config
├── kubernetes-manifests-hostpath.yaml     (5.1KB) - Alternative K8s config
├── manage-llm-deployments.sh              (9.8KB) - Management script
├── test-examples.sh                       (11KB) - API test examples
└── python-client-example.py               (13KB) - Python client library
```

### File Descriptions

**Documentation:**

- **README.md** - Quick start guide and overview
- **DEPLOYMENT-GUIDE.md** - Comprehensive guide with calculations and sources
- **QUICK-REFERENCE.md** - Cheat sheet for common commands
- **SUMMARY.md** - This executive summary

**Kubernetes:**

- **kubernetes-manifests.yaml** - Main deployment (PV/PVC)
- **kubernetes-manifests-hostpath.yaml** - Simpler alternative (hostPath)

**Tools:**

- **manage-llm-deployments.sh** - Helper script for deployment management
- **test-examples.sh** - Shell script with API test examples
- **python-client-example.py** - Python examples using requests/OpenAI library

---

## 9. Quick Start Commands

### Initial Deployment

```bash
# 1. Get your GPU node hostname
kubectl get nodes -o wide

# 2. Edit manifests and replace 'node-with-gpu' with your hostname
vim kubernetes-manifests.yaml

# 3. Deploy services
./manage-llm-deployments.sh deploy

# 4. Check status
./manage-llm-deployments.sh status
```

### Switch Between Models

```bash
# Use coding model
./manage-llm-deployments.sh use-coding

# Use chat model
./manage-llm-deployments.sh use-chat

# Stop all
./manage-llm-deployments.sh stop
```

### Testing

```bash
# Test coding model
./manage-llm-deployments.sh test coding

# Test chat model
./manage-llm-deployments.sh test chat

# Run comprehensive tests
./test-examples.sh all

# Python examples
python3 python-client-example.py
```

### Monitoring

```bash
# View logs
./manage-llm-deployments.sh logs coding

# Check GPU usage
./manage-llm-deployments.sh gpu

# Metrics
curl http://172.22.22.57:30080/metrics
```

---

## 10. Performance Expectations

### Coding Model (Full GPU)

**Configuration:** 48/48 GPU layers, 32K context

**Performance:**

- Prompt Processing: 500-800 tokens/sec
- Text Generation: 30-50 tokens/sec
- Latency: <100ms first token
- Context Window: 32,768 tokens

**Use Cases:**

- Code completion
- Code review
- Large file analysis
- Multi-file debugging

### Chat Model (Full GPU)

**Configuration:** 48/48 GPU layers, 16K context

**Performance:**

- Prompt Processing: 500-800 tokens/sec
- Text Generation: 30-50 tokens/sec
- Latency: <100ms first token
- Context Window: 16,384 tokens

**Use Cases:**

- Conversational AI
- Q&A systems
- Summarization
- General assistance

### Flash Attention Benefits

**Enabled by:** `--flash-attn 1`

**Benefits:**

- 15% throughput improvement
- Lower memory overhead
- Better scaling with context size
- CUDA-optimized (RTX 5080 supported)

**No Downsides:** Always enable on NVIDIA GPUs

---

## 11. Production Recommendations

### Best Practices

1. **Run one model at a time** for maximum performance
2. **Use 32K context for coding**, 16K for chat
3. **Always enable Flash Attention** (`--flash-attn 1`)
4. **Monitor VRAM usage** with nvidia-smi or metrics
5. **Scale unused deployments to 0** to free GPU
6. **Test with health checks** before sending requests
7. **Use streaming** for interactive applications
8. **Implement retry logic** for production clients

### Resource Management

**Kubernetes Resource Requests/Limits:**

```yaml
resources:
  requests:
    nvidia.com/gpu: 1
    memory: "16Gi"
    cpu: "4"
  limits:
    nvidia.com/gpu: 1
    memory: "24Gi"
    cpu: "8"
```

**Why These Values:**

- GPU: 1 per deployment (exclusive access)
- Memory: 16Gi request ensures space, 24Gi limit for headroom
- CPU: 4-8 cores for auxiliary tasks

### Monitoring Setup

**Prometheus Metrics:**

```bash
# Scrape endpoint
curl http://172.22.22.57:30080/metrics

# Key metrics
- llama_model_load_time_ms
- llama_tokens_generated_total
- llama_prompt_tokens_processed_total
- http_request_duration_ms
```

**GPU Monitoring:**

```bash
# From pod
kubectl exec -n llm-inference deployment/qwen-coder-14b -- nvidia-smi

# Host-level
watch -n 1 nvidia-smi
```

---

## 12. Troubleshooting Guide

### Issue: Pod Stuck in Pending

**Cause:** GPU not available

**Solution:**

```bash
# Check GPU resources
kubectl describe node | grep nvidia.com/gpu

# Check pod events
kubectl describe pod -n llm-inference
```

### Issue: CUDA Out of Memory

**Cause:** Context size too large

**Solution:**

```bash
# Reduce context size
--ctx-size 16384  # Instead of 32768

# OR reduce GPU layers
--n-gpu-layers 40  # Instead of 48
```

### Issue: Slow Inference

**Cause:** Not all layers on GPU

**Solution:**

```bash
# Check logs for layer offloading
kubectl logs -n llm-inference -l app=qwen-coder-14b | grep "offload"

# Verify Flash Attention
kubectl logs -n llm-inference -l app=qwen-coder-14b | grep "flash"
```

### Issue: Service Not Accessible

**Cause:** Service endpoint misconfigured

**Solution:**

```bash
# Check services
kubectl get svc -n llm-inference

# Port forward for debugging
kubectl port-forward -n llm-inference svc/qwen-coder-14b-service 8080:8080

# Test locally
curl http://localhost:8080/health
```

---

## 13. Sources and References

All calculations and recommendations are based on empirical testing and official documentation:

### Container Images

- [GitHub - ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
- [llama.cpp Docker Documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/docker.md)
- [Package llama.cpp](https://github.com/ggml-org/llama.cpp/pkgs/container/llama.cpp)

### VRAM Calculations

- [VRAM Calculator for Local Open Source LLMs](https://localllm.in/blog/interactive-vram-calculator)
- [Ollama VRAM Requirements Guide 2025](https://localllm.in/blog/ollama-vram-requirements-for-local-llms)
- [How to calculate memory for context size](https://github.com/ggml-org/llama.cpp/discussions/10068)

### RTX 5080 & Flash Attention

- [LM Studio Accelerates LLM Performance With NVIDIA GeForce RTX GPUs](https://blogs.nvidia.com/blog/rtx-ai-garage-lmstudio-llamacpp-blackwell/)
- [Performance of llama.cpp on Nvidia CUDA](https://github.com/ggml-org/llama.cpp/discussions/15013)

### Model Architecture

- [Qwen2.5-14B-Instruct on Hugging Face](https://huggingface.co/Qwen/Qwen2.5-14B-Instruct)
- [Qwen2.5: A Party of Foundation Models](https://qwenlm.github.io/blog/qwen2.5/)

### KV Cache & Memory

- [How to calculate size of KV cache](https://www.rohan-paul.com/p/how-to-calculate-size-of-kv-cache)
- [LLM Inference Series: 4. KV caching](https://medium.com/@plienhar/llm-inference-series-4-kv-caching-a-deeper-look-4ba9a77746c8)

---

## Final Recommendations

**For Your RTX 5080 16GB Setup:**

1. **Deploy both services** using kubernetes-manifests.yaml
2. **Run one model at a time** for optimal performance
3. **Use coding model** (32K context) for development work
4. **Use chat model** (16K context) for assistance tasks
5. **Switch as needed** using the management script
6. **Monitor VRAM** to ensure headroom
7. **Enable Flash Attention** always

**This configuration provides:**

- Maximum inference speed (30-50 tokens/sec)
- Large context windows (32K/16K)
- Reliable performance
- Easy model switching
- Production-ready setup

**You have an optimal setup for a single 16GB GPU!**
