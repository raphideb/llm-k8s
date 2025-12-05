# llama.cpp Kubernetes Deployment for Dual Qwen2.5 14B Models

Complete Kubernetes deployment solution for running Qwen2.5-Coder-14B and Qwen2.5-14B-Instruct models on NVIDIA RTX 5080 (16GB VRAM).

## Overview

This repository contains production-ready Kubernetes manifests and management tools for deploying llama.cpp inference servers with CUDA acceleration.

**Hardware:** NVIDIA RTX 5080 (16GB VRAM) + 64GB RAM

**Models:**

- Qwen2.5-Coder-14B-Instruct-Q4_K_M.gguf (8.4GB) - Coding tasks
- Qwen2.5-14B-Instruct-Q4_K_M.gguf (8.4GB) - Chat/General tasks

**Container Image:** `ghcr.io/ggml-org/llama.cpp:server-cuda`

## Quick Start

### 1. Prerequisites

Ensure your Kubernetes node has:

- NVIDIA GPU device plugin installed
- NVIDIA Container Toolkit configured
- Models downloaded to `/home/raphi/git/models/`

Verify GPU access:

```bash
kubectl run gpu-test --image=nvidia/cuda:12.8.0-base-ubuntu20.04 --rm -it --restart=Never -- nvidia-smi
```

### 2. Update Node Hostname

Get your GPU node's hostname:

```bash
kubectl get nodes -o wide
```

Edit `kubernetes-manifests.yaml` and replace `node-with-gpu` with your actual hostname.

### 3. Deploy Services

```bash
# Using the management script (recommended)
./manage-llm-deployments.sh deploy

# Or manually
kubectl apply -f kubernetes-manifests.yaml
```

### 4. Switch Between Models

```bash
# Use coding model (stops chat model)
./manage-llm-deployments.sh use-coding

# Use chat model (stops coding model)
./manage-llm-deployments.sh use-chat

# Check status
./manage-llm-deployments.sh status
```

### 5. Test the API

```bash
# Health check
curl http://172.22.22.57:30080/health

# Test inference
./manage-llm-deployments.sh test coding
```

## Files in This Repository

| File | Description |
|------|-------------|
| **kubernetes-manifests.yaml** | Main deployment with PersistentVolume |
| **kubernetes-manifests-hostpath.yaml** | Alternative using hostPath (simpler) |
| **DEPLOYMENT-GUIDE.md** | Complete documentation with VRAM calculations |
| **QUICK-REFERENCE.md** | Quick commands and API usage |
| **manage-llm-deployments.sh** | Helper script for managing deployments |
| **README.md** | This file |

## Key Findings

### VRAM Analysis

**Single Model (Full GPU):**

- 32K context: 12.15GB VRAM
- 16K context: 10.55GB VRAM
- Both fit comfortably in 16GB VRAM

**Dual Models (Simultaneous):**

- NOT POSSIBLE with full GPU acceleration (requires 17.45GB)
- Hybrid mode possible: Coding full GPU (12.15GB) + Chat 10 GPU layers (3.5GB) = 15.65GB
- Trade-off: Chat model runs 3-5x slower in hybrid mode

### Recommended Strategy

**Run one model at a time for maximum performance:**

- Switch between models based on workload
- Each gets full 16GB VRAM allocation
- Maximum context windows (32K for coding, 16K for chat)
- Optimal inference speed (30-50 tokens/sec)

### Container Image

**Recommended:** `ghcr.io/ggml-org/llama.cpp:server-cuda`

**Features:**

- Official CUDA-enabled llama.cpp server
- CUDA 12.8 support for RTX 5080 (Compute Capability 12.0)
- Flash Attention 2 support (15% speedup)
- OpenAI-compatible API
- Prometheus metrics endpoint

### Optimal Parameters

**Coding Model:**

```bash
--n-gpu-layers 48      # All layers on GPU
--ctx-size 32768       # 32K context for large codebases
--n-batch 2048         # Large batch for throughput
--flash-attn 1         # Enable Flash Attention
```

**Chat Model:**

```bash
--n-gpu-layers 48      # All layers on GPU
--ctx-size 16384       # 16K context for conversations
--n-batch 1024         # Medium batch size
--flash-attn 1         # Enable Flash Attention
```

## Management Script Usage

```bash
# Deploy services
./manage-llm-deployments.sh deploy

# Check status
./manage-llm-deployments.sh status

# Switch to coding model
./manage-llm-deployments.sh use-coding

# Switch to chat model
./manage-llm-deployments.sh use-chat

# Run both (hybrid mode - degraded chat performance)
./manage-llm-deployments.sh use-both

# View logs
./manage-llm-deployments.sh logs coding
./manage-llm-deployments.sh logs chat

# Check GPU usage
./manage-llm-deployments.sh gpu

# Test model
./manage-llm-deployments.sh test coding

# Stop all models
./manage-llm-deployments.sh stop

# Delete all resources
./manage-llm-deployments.sh delete
```

## API Endpoints

**Coding Model:** http://172.22.22.57:30080

**Chat Model:** http://172.22.22.57:30081

**Available Endpoints:**

- `/health` - Health check
- `/v1/models` - List models
- `/v1/chat/completions` - OpenAI-compatible chat API
- `/v1/completions` - OpenAI-compatible completions API
- `/metrics` - Prometheus metrics

## Example API Usage

### Chat Completion

```bash
curl http://172.22.22.57:30080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder-14b",
    "messages": [
      {"role": "system", "content": "You are a helpful coding assistant."},
      {"role": "user", "content": "Write a Python function to reverse a string"}
    ],
    "max_tokens": 500,
    "temperature": 0.7
  }'
```

### Streaming Response

```bash
curl http://172.22.22.57:30080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-coder-14b",
    "messages": [{"role": "user", "content": "Explain async/await"}],
    "stream": true
  }'
```

## Performance Expectations

**Coding Model (Full GPU - 48/48 layers):**

- Prompt Processing: 500-800 tokens/sec
- Text Generation: 30-50 tokens/sec
- Context Window: 32K tokens
- VRAM Usage: 12.15GB

**Chat Model (Full GPU - 48/48 layers):**

- Prompt Processing: 500-800 tokens/sec
- Text Generation: 30-50 tokens/sec
- Context Window: 16K tokens
- VRAM Usage: 10.55GB

**Flash Attention Benefits:**

- 15% throughput improvement
- Better memory efficiency
- Enabled by default with `--flash-attn 1`

## Architecture Details

**Qwen2.5 14B Model:**

- Total Parameters: 14.7B (13.1B non-embedding)
- Transformer Layers: 48
- Attention Heads: 40 Query, 8 Key-Value (Grouped Query Attention)
- Maximum Context: 131,072 tokens (generation up to 8,192)
- Quantization: Q4_K_M (4-bit, optimal quality/size balance)

**VRAM Breakdown:**

1. Model Weights: ~8.4GB
2. CUDA Overhead: ~0.55GB
3. KV Cache (context-dependent): 0.8GB (8K) to 6.5GB (65K)
4. Scratchpad Memory: ~0.3GB

## Troubleshooting

### Pod Stuck in Pending

```bash
# Check GPU availability
kubectl describe node | grep nvidia.com/gpu

# Check pod events
kubectl describe pod -n llm-inference
```

### CUDA Out of Memory

Reduce context size or GPU layers:

```bash
# Edit deployment args:
--ctx-size 16384  # Lower context
# OR
--n-gpu-layers 40  # Fewer GPU layers

# Apply changes
kubectl apply -f kubernetes-manifests.yaml
```

### Slow Inference

```bash
# Verify GPU layer offloading
kubectl logs -n llm-inference -l app=qwen-coder-14b | grep "offload"

# Check Flash Attention is enabled
kubectl logs -n llm-inference -l app=qwen-coder-14b | grep "flash"
```

### Service Not Accessible

```bash
# Check service endpoints
kubectl get svc -n llm-inference

# Port forward for debugging
kubectl port-forward -n llm-inference svc/qwen-coder-14b-service 8080:8080

# Test locally
curl http://localhost:8080/health
```

## Best Practices

1. Run one model at a time for maximum performance
2. Use 32K context for coding (large files, codebases)
3. Use 16K context for chat (conversations, Q&A)
4. Always enable Flash Attention (`--flash-attn 1`)
5. Monitor VRAM usage with `nvidia-smi` or metrics endpoint
6. Scale unused models to 0 replicas to free GPU resources
7. Test with health checks before sending prompts
8. Use streaming for interactive applications

## Alternative Configurations

### Simultaneous Operation (Hybrid Mode)

If you need both models running at once:

- Coding Model: 48 GPU layers, 32K context = 12.15GB VRAM
- Chat Model: 10 GPU layers, 8K context = 3.5GB VRAM
- Total: 15.65GB VRAM (fits in 16GB)
- Trade-off: Chat model is significantly slower

Edit `kubernetes-manifests.yaml` and change chat model args:

```yaml
- --n-gpu-layers
- "10"  # Instead of 24
- --ctx-size
- "8192"  # Instead of 16384
```

### Using hostPath Instead of PersistentVolume

If you have issues with PersistentVolumes, use:

```bash
kubectl apply -f kubernetes-manifests-hostpath.yaml
```

This uses direct hostPath mounting (simpler but less flexible).

## Resource Requirements

**Per Model:**

- GPU: 1x NVIDIA GPU (RTX 5080 or equivalent)
- VRAM: 16GB recommended (12-15GB used)
- RAM: 16-24GB
- CPU: 4-8 cores
- Disk: 10GB per model + 5GB for container images

**Kubernetes Node:**

- NVIDIA Container Toolkit
- NVIDIA GPU device plugin
- Storage class: local-path or equivalent
- Kernel: Linux 5.x+ with CUDA drivers

## Documentation

- **DEPLOYMENT-GUIDE.md** - Complete guide with detailed VRAM calculations, architecture analysis, and deployment strategies
- **QUICK-REFERENCE.md** - Quick commands, API examples, and common tasks

## Sources and References

### Container Images

- [GitHub - ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
- [llama.cpp Docker Documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/docker.md)

### VRAM Calculations

- [VRAM Calculator for Local Open Source LLMs](https://localllm.in/blog/interactive-vram-calculator)
- [How to calculate the required memory for context size](https://github.com/ggml-org/llama.cpp/discussions/10068)

### Model Information

- [Qwen2.5-14B-Instruct on Hugging Face](https://huggingface.co/Qwen/Qwen2.5-14B-Instruct)
- [Qwen2.5: A Party of Foundation Models](https://qwenlm.github.io/blog/qwen2.5/)

### RTX 5080 & Flash Attention

- [LM Studio Accelerates LLM Performance With NVIDIA GeForce RTX GPUs](https://blogs.nvidia.com/blog/rtx-ai-garage-lmstudio-llamacpp-blackwell/)

## License

This deployment configuration is provided as-is for use with llama.cpp and Qwen2.5 models. Please refer to the respective licenses:

- llama.cpp: MIT License
- Qwen2.5 models: Apache 2.0 License
- NVIDIA CUDA: NVIDIA CUDA Toolkit License

## Support

For issues with:

- llama.cpp: https://github.com/ggml-org/llama.cpp/issues
- Qwen2.5 models: https://github.com/QwenLM/Qwen2.5/issues
- Kubernetes GPU support: https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/
