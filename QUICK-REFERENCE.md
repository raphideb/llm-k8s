# llama.cpp Kubernetes Quick Reference

## Hardware Summary

- **GPU:** NVIDIA RTX 5080 (16GB VRAM, Compute Capability 12.0)
- **RAM:** 64GB System Memory
- **Node IP:** 172.22.22.57
- **Storage:** local-path at /home/raphi/git/models/

## Container Image

```
ghcr.io/ggml-org/llama.cpp:server-cuda
```

## Models

| Model | File Size | Layers | Use Case |
|-------|-----------|--------|----------|
| Qwen2.5-Coder-14B-Instruct-Q4_K_M.gguf | 8.4GB | 48 | Coding tasks |
| Qwen2.5-14B-Instruct-Q4_K_M.gguf | 8.4GB | 48 | Chat/General |

## VRAM Usage (Single Model)

| Context Size | VRAM Required | Status |
|--------------|---------------|--------|
| 8K tokens    | 9.75GB       | Fits easily |
| 16K tokens   | 10.55GB      | Fits comfortably |
| 32K tokens   | 12.15GB      | Recommended max |
| 65K tokens   | 15.45GB      | Tight fit |

## Optimal Configurations

### Configuration 1: Single Model (RECOMMENDED)

**Coding Model (Max Performance):**

```bash
--n-gpu-layers 48
--ctx-size 32768
--n-batch 2048
--flash-attn 1
```

**VRAM:** 12.15GB, **Performance:** Maximum

**Chat Model (Max Performance):**

```bash
--n-gpu-layers 48
--ctx-size 16384
--n-batch 1024
--flash-attn 1
```

**VRAM:** 10.55GB, **Performance:** Maximum

### Configuration 2: Dual Models (Hybrid)

**NOT RECOMMENDED:** Both models with full GPU = 17.45GB (exceeds 16GB)

**Alternative for simultaneous operation:**

- Coding: 48 GPU layers, 32K context = 12.15GB
- Chat: 10 GPU layers, 8K context = 3.5GB
- **Total:** 15.65GB (fits, but chat is 3-5x slower)

## Quick Commands

### Deploy Services

```bash
# Initial deployment
./manage-llm-deployments.sh deploy

# Check status
./manage-llm-deployments.sh status
```

### Switch Between Models

```bash
# Use coding model (stops chat)
./manage-llm-deployments.sh use-coding

# Use chat model (stops coding)
./manage-llm-deployments.sh use-chat

# Use both (hybrid mode - degraded chat performance)
./manage-llm-deployments.sh use-both

# Stop all models
./manage-llm-deployments.sh stop
```

### Monitoring

```bash
# View logs
./manage-llm-deployments.sh logs coding
./manage-llm-deployments.sh logs chat

# Check GPU usage
./manage-llm-deployments.sh gpu

# Test model
./manage-llm-deployments.sh test coding
./manage-llm-deployments.sh test chat
```

### Manual kubectl Commands

```bash
# View all resources
kubectl get all -n llm-inference

# Scale deployments
kubectl scale deployment -n llm-inference qwen-coder-14b --replicas=1
kubectl scale deployment -n llm-inference qwen-chat-14b --replicas=0

# View logs
kubectl logs -n llm-inference -l app=qwen-coder-14b -f

# GPU check from pod
kubectl exec -n llm-inference deployment/qwen-coder-14b -- nvidia-smi
```

## API Endpoints

### Coding Model

- **URL:** http://172.22.22.57:30080
- **Health:** http://172.22.22.57:30080/health
- **Models:** http://172.22.22.57:30080/v1/models
- **Chat:** http://172.22.22.57:30080/v1/chat/completions

### Chat Model

- **URL:** http://172.22.22.57:30081
- **Health:** http://172.22.22.57:30081/health
- **Models:** http://172.22.22.57:30081/v1/models
- **Chat:** http://172.22.22.57:30081/v1/chat/completions

## API Usage Examples

### Health Check

```bash
curl http://172.22.22.57:30080/health
```

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
    "messages": [{"role": "user", "content": "Explain async/await in Python"}],
    "stream": true,
    "max_tokens": 1000
  }'
```

## Performance Expectations

### Coding Model (Full GPU)

- **Prompt Processing:** ~500-800 tokens/sec
- **Generation:** ~30-50 tokens/sec
- **Context Window:** 32K tokens
- **Use Case:** Code completion, debugging, large file analysis

### Chat Model (Full GPU)

- **Prompt Processing:** ~500-800 tokens/sec
- **Generation:** ~30-50 tokens/sec
- **Context Window:** 16K tokens
- **Use Case:** Conversations, Q&A, summarization

### Chat Model (Hybrid 10 GPU layers)

- **Prompt Processing:** ~150-250 tokens/sec
- **Generation:** ~10-15 tokens/sec
- **Context Window:** 8K tokens
- **Use Case:** Background assistant while coding

## Flash Attention Benefits

**Enabled with:** `--flash-attn 1`

- 15% throughput improvement on CUDA
- Better memory efficiency for longer contexts
- No downsides on RTX 5080
- CUDA-only optimization (not for AMD ROCm)

## Troubleshooting

### Pod Stuck in Pending

```bash
# Check GPU availability
kubectl describe node | grep nvidia.com/gpu

# Check pod events
kubectl describe pod -n llm-inference -l app=qwen-coder-14b
```

### CUDA Out of Memory

Reduce context or layers:

```bash
# Edit deployment, change args:
--ctx-size 16384  # Lower context
# OR
--n-gpu-layers 40  # Fewer GPU layers
```

### Slow Inference

```bash
# Check GPU layer offloading
kubectl logs -n llm-inference -l app=qwen-coder-14b | grep "offload"

# Verify Flash Attention is enabled
kubectl logs -n llm-inference -l app=qwen-coder-14b | grep "flash"
```

### Model Not Responding

```bash
# Check service endpoints
kubectl get svc -n llm-inference

# Port forward for debugging
kubectl port-forward -n llm-inference svc/qwen-coder-14b-service 8080:8080

# Test locally
curl http://localhost:8080/health
```

## Resource Requirements

### Kubernetes Node Requirements

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

### Storage Requirements

- **Model Storage:** 20GB (both models + overhead)
- **Container Images:** ~5GB
- **Logs/Cache:** ~1GB

**Total:** ~26GB disk space

## Best Practices

1. **Run one model at a time** for maximum performance
2. **Use 32K context** for coding (large files, codebases)
3. **Use 16K context** for chat (conversations, Q&A)
4. **Enable Flash Attention** (`--flash-attn 1`) always
5. **Monitor VRAM usage** with `nvidia-smi` or metrics endpoint
6. **Scale to 0 replicas** for unused models to free GPU
7. **Test with health checks** before sending prompts
8. **Use streaming** for interactive applications

## Recommended Workflow

### For Coding Sessions

```bash
# Start coding model
./manage-llm-deployments.sh use-coding

# Test it
./manage-llm-deployments.sh test coding

# Monitor performance
./manage-llm-deployments.sh gpu
```

### For Chat Sessions

```bash
# Start chat model
./manage-llm-deployments.sh use-chat

# Test it
./manage-llm-deployments.sh test chat
```

### For Development (Both Models)

```bash
# Use hybrid mode (degraded chat performance)
./manage-llm-deployments.sh use-both

# Monitor both
kubectl get pods -n llm-inference -w
```

### When Done

```bash
# Stop all models to free GPU
./manage-llm-deployments.sh stop
```

## Files Created

- **kubernetes-manifests.yaml** - Kubernetes deployment configurations
- **DEPLOYMENT-GUIDE.md** - Complete documentation with calculations
- **QUICK-REFERENCE.md** - This file (quick commands and tips)
- **manage-llm-deployments.sh** - Helper script for managing deployments

## Additional Resources

- [llama.cpp Documentation](https://github.com/ggml-org/llama.cpp)
- [Qwen2.5 Model Card](https://huggingface.co/Qwen/Qwen2.5-14B-Instruct)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)
- [Kubernetes GPU Support](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)
