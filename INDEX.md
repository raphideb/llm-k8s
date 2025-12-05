# Documentation Index

## Overview

This repository contains a complete, production-ready solution for deploying dual Qwen2.5 14B models (Coding and Chat) on Kubernetes with NVIDIA RTX 5080 GPU acceleration using llama.cpp.

**Quick Links:**

- [Start Here: README.md](#readmemd)
- [Quick Commands: QUICK-REFERENCE.md](#quick-referencemd)
- [Complete Guide: DEPLOYMENT-GUIDE.md](#deployment-guidemd)

---

## File Structure

```
/home/raphi/git/llm/
├── Documentation Files (70KB)
│   ├── INDEX.md (this file)              - Documentation index
│   ├── README.md                         - Start here: Overview and quick start
│   ├── SUMMARY.md                        - Executive summary with key findings
│   ├── DEPLOYMENT-GUIDE.md               - Comprehensive deployment guide
│   ├── QUICK-REFERENCE.md                - Command cheat sheet
│   └── DEPLOYMENT-CHECKLIST.md           - Step-by-step deployment checklist
│
├── Kubernetes Manifests (11KB)
│   ├── kubernetes-manifests.yaml         - Main deployment (PV/PVC)
│   └── kubernetes-manifests-hostpath.yaml - Alternative (hostPath)
│
└── Tools and Scripts (34KB)
    ├── manage-llm-deployments.sh         - Deployment management script
    ├── test-examples.sh                  - Shell-based API tests
    └── python-client-example.py          - Python client examples
```

**Total Size:** 144KB

---

## Documentation Files

### README.md

**Size:** 10KB | **Type:** Overview

**Contents:**

- Quick start guide
- Hardware configuration
- Model specifications
- Container image recommendation
- Deployment instructions
- API endpoints
- Performance expectations
- Troubleshooting
- Best practices

**When to Read:**

- First time setup
- Getting started
- Understanding the deployment

**Start Command:**

```bash
cat README.md
```

---

### SUMMARY.md

**Size:** 18KB | **Type:** Executive Summary

**Contents:**

- Executive summary of findings
- Complete VRAM calculations
- Dual model deployment strategy
- Optimal parameters
- Memory usage estimates
- Answers to key questions
- Performance expectations
- Production recommendations
- Troubleshooting guide
- Sources and references

**When to Read:**

- Understanding VRAM limitations
- Planning deployment strategy
- Deciding between configurations
- Reference for calculations

**Key Finding:**

RTX 5080 16GB can run ONE 14B Q4_K_M model optimally, NOT both simultaneously with full GPU acceleration.

---

### DEPLOYMENT-GUIDE.md

**Size:** 16KB | **Type:** Comprehensive Guide

**Contents:**

1. Container image recommendation
2. GPU memory calculations (detailed)
3. Dual model deployment strategy
4. Complete Kubernetes manifests explained
5. llama-server command lines
6. Memory usage estimates
7. Deployment instructions
8. Answers to key questions
9. RTX 5080 specific optimizations
10. Monitoring and troubleshooting
11. Sources and references

**When to Read:**

- Deep dive into VRAM calculations
- Understanding architecture decisions
- Optimizing parameters
- Advanced troubleshooting

**Includes:**

- Detailed VRAM breakdown tables
- KV cache calculations
- Flash Attention explanation
- Alternative model suggestions

---

### QUICK-REFERENCE.md

**Size:** 7.7KB | **Type:** Cheat Sheet

**Contents:**

- Hardware summary
- Container image
- Model specifications
- VRAM usage tables
- Optimal configurations
- Quick commands (kubectl, script)
- API endpoints
- API usage examples
- Performance expectations
- Troubleshooting quick fixes

**When to Read:**

- Daily operations
- Quick command lookup
- API integration
- Common tasks

**Perfect For:**

Copy-paste commands and API examples

---

### DEPLOYMENT-CHECKLIST.md

**Size:** 11KB | **Type:** Checklist

**Contents:**

- Pre-deployment verification
- Step-by-step deployment
- Testing checklist
- Operational checklist
- Troubleshooting checklist
- Performance verification
- Security checklist
- Maintenance schedule
- Rollback procedures
- Production readiness

**When to Read:**

- First deployment
- Deployment verification
- Production launch
- Troubleshooting issues

**Use As:**

Systematic verification during deployment

---

## Kubernetes Manifests

### kubernetes-manifests.yaml

**Size:** 6.1KB | **Type:** Main Deployment

**Contains:**

- Namespace: llm-inference
- PersistentVolume (50Gi, hostPath)
- PersistentVolumeClaim
- Deployment: qwen-coder-14b
- Deployment: qwen-chat-14b
- Service: qwen-coder-14b-service (NodePort 30080)
- Service: qwen-chat-14b-service (NodePort 30081)

**Features:**

- Proper resource limits (GPU, memory, CPU)
- Health checks (liveness, readiness)
- Node affinity for GPU scheduling
- Metrics enabled
- JSON logging

**Deploy With:**

```bash
# Update node hostname first
vim kubernetes-manifests.yaml
# Then deploy
./manage-llm-deployments.sh deploy
```

---

### kubernetes-manifests-hostpath.yaml

**Size:** 5.1KB | **Type:** Alternative Deployment

**Differences from Main:**

- Uses hostPath directly (no PV/PVC)
- Simpler configuration
- Same deployments and services
- Better for single-node or testing

**When to Use:**

- PersistentVolume issues
- Single-node cluster
- Simpler setup preferred
- Testing/development

**Deploy With:**

```bash
kubectl apply -f kubernetes-manifests-hostpath.yaml
```

---

## Tools and Scripts

### manage-llm-deployments.sh

**Size:** 9.8KB | **Type:** Bash Script

**Commands:**

- `deploy` - Deploy services
- `status` - Show deployment status
- `use-coding` - Switch to coding model
- `use-chat` - Switch to chat model
- `use-both` - Run both (hybrid mode)
- `stop` - Stop all models
- `logs [MODEL]` - View logs
- `gpu` - Show GPU usage
- `test [MODEL]` - Test with sample prompt
- `delete` - Delete all resources

**Features:**

- Colored output
- Error handling
- Wait for ready
- Health checks
- GPU monitoring

**Usage:**

```bash
./manage-llm-deployments.sh help
./manage-llm-deployments.sh deploy
./manage-llm-deployments.sh use-coding
```

---

### test-examples.sh

**Size:** 11KB | **Type:** Test Script

**Tests:**

- Health checks (coding, chat)
- List models
- Simple completions
- Code explanations
- Multi-turn conversations
- Streaming responses
- Code review
- Performance benchmarks
- Error handling
- Large context windows
- JSON mode
- Metrics endpoint

**Usage:**

```bash
./test-examples.sh help
./test-examples.sh all          # Run all quick tests
./test-examples.sh performance  # Performance test
./test-examples.sh simple-coding
```

**Requirements:**

- jq (JSON processor)
- bc (calculator)
- curl

---

### python-client-example.py

**Size:** 13KB | **Type:** Python Script

**Examples:**

1. Code generation (coding model)
2. Code review (coding model)
3. Chat conversation (chat model)
4. Streaming response
5. OpenAI library usage
6. Multi-turn conversation
7. Performance testing

**Features:**

- Works with requests library
- Works with openai library
- Streaming support
- Error handling
- Performance measurement

**Usage:**

```bash
# Install dependencies
pip install openai requests

# Run all examples
python3 python-client-example.py

# Or import and use in your code
from python_client_example import simple_completion_requests
```

---

## Reading Guide by Use Case

### Use Case: First Time Deployment

**Read in Order:**

1. **README.md** - Understand the setup
2. **DEPLOYMENT-CHECKLIST.md** - Follow step-by-step
3. **QUICK-REFERENCE.md** - Commands reference

**Files to Edit:**

- kubernetes-manifests.yaml (update node hostname)

**Commands to Run:**

```bash
./manage-llm-deployments.sh deploy
./manage-llm-deployments.sh status
./manage-llm-deployments.sh use-coding
./test-examples.sh simple-coding
```

---

### Use Case: Understanding VRAM Limitations

**Read in Order:**

1. **SUMMARY.md** - Executive summary and key findings
2. **DEPLOYMENT-GUIDE.md** - Section 2 (GPU Memory Calculations)
3. **DEPLOYMENT-GUIDE.md** - Section 3 (Dual Model Strategy)

**Key Sections:**

- VRAM Breakdown (component-by-component)
- KV Cache calculations
- Simultaneous operation analysis
- Alternative configurations

---

### Use Case: Daily Operations

**Primary Reference:**

- **QUICK-REFERENCE.md** - All common commands

**Scripts to Use:**

```bash
./manage-llm-deployments.sh use-coding
./manage-llm-deployments.sh use-chat
./manage-llm-deployments.sh status
./manage-llm-deployments.sh logs coding
```

**Monitoring:**

```bash
./manage-llm-deployments.sh gpu
curl http://172.22.22.57:30080/metrics
```

---

### Use Case: API Integration

**Read:**

- **QUICK-REFERENCE.md** - API endpoints and examples
- **python-client-example.py** - Code examples

**Test:**

```bash
./test-examples.sh simple-coding
./test-examples.sh simple-chat
python3 python-client-example.py
```

**API Documentation:**

- OpenAI-compatible API
- Endpoints: /v1/chat/completions, /v1/models, /health
- Streaming support
- JSON format

---

### Use Case: Troubleshooting

**Resources:**

1. **DEPLOYMENT-CHECKLIST.md** - Troubleshooting section
2. **DEPLOYMENT-GUIDE.md** - Section 10 (Monitoring & Troubleshooting)
3. **QUICK-REFERENCE.md** - Quick fixes

**Common Issues:**

- Pod stuck in Pending → Check GPU availability
- CUDA out of memory → Reduce context size
- Slow inference → Verify GPU layers
- Connection refused → Check service/port

**Debug Commands:**

```bash
kubectl describe pod -n llm-inference
kubectl logs -n llm-inference -l app=qwen-coder-14b
./manage-llm-deployments.sh gpu
```

---

### Use Case: Performance Optimization

**Read:**

- **SUMMARY.md** - Section 10 (Performance Expectations)
- **DEPLOYMENT-GUIDE.md** - Section 9 (RTX 5080 Optimizations)

**Test:**

```bash
./test-examples.sh performance
```

**Key Parameters:**

- `--n-gpu-layers 48` - All layers on GPU
- `--flash-attn 1` - Enable Flash Attention
- `--ctx-size 32768` - Large context (coding)
- `--n-batch 2048` - Large batch (throughput)

---

### Use Case: Production Deployment

**Read in Order:**

1. **SUMMARY.md** - Final Recommendations
2. **DEPLOYMENT-CHECKLIST.md** - Production Readiness section
3. **DEPLOYMENT-GUIDE.md** - Section 11 (Production Recommendations)

**Checklist Items:**

- [ ] Security audit completed
- [ ] Monitoring configured
- [ ] Backup strategy defined
- [ ] Runbook created
- [ ] Load testing completed
- [ ] SLA/SLO defined

---

## Quick Command Reference

### Deployment

```bash
# Deploy
./manage-llm-deployments.sh deploy

# Status
./manage-llm-deployments.sh status

# Delete
./manage-llm-deployments.sh delete
```

### Model Management

```bash
# Use coding model
./manage-llm-deployments.sh use-coding

# Use chat model
./manage-llm-deployments.sh use-chat

# Stop all
./manage-llm-deployments.sh stop
```

### Monitoring

```bash
# Logs
./manage-llm-deployments.sh logs coding

# GPU usage
./manage-llm-deployments.sh gpu

# Metrics
curl http://172.22.22.57:30080/metrics
```

### Testing

```bash
# Quick test
./manage-llm-deployments.sh test coding

# All tests
./test-examples.sh all

# Performance test
./test-examples.sh performance

# Python examples
python3 python-client-example.py
```

---

## API Endpoints

**Coding Model:** http://172.22.22.57:30080

**Chat Model:** http://172.22.22.57:30081

**Available Endpoints:**

- `/health` - Health check
- `/v1/models` - List models
- `/v1/chat/completions` - Chat completions (OpenAI-compatible)
- `/v1/completions` - Text completions
- `/metrics` - Prometheus metrics

---

## Key Findings Summary

1. **VRAM Capacity:** RTX 5080 16GB can run ONE 14B Q4_K_M model optimally
2. **Simultaneous Operation:** NOT POSSIBLE with full GPU acceleration (would need 22.7GB)
3. **Recommended Strategy:** Deploy both, run one at a time (sequential operation)
4. **Container Image:** ghcr.io/ggml-org/llama.cpp:server-cuda (official, CUDA 12.8)
5. **Optimal Config:** 48 GPU layers, 32K context (coding), 16K context (chat)
6. **Flash Attention:** Always enable (15% boost, no downside on RTX 5080)
7. **Performance:** 30-50 tokens/sec generation, 500-800 tokens/sec prompt processing

---

## Support and References

### Documentation in This Repo

- All .md files in /home/raphi/git/llm/
- Management script help: `./manage-llm-deployments.sh help`
- Test script help: `./test-examples.sh help`

### External Resources

- [llama.cpp GitHub](https://github.com/ggml-org/llama.cpp)
- [Qwen2.5 Models](https://huggingface.co/Qwen)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)
- [Kubernetes GPU Support](https://kubernetes.io/docs/tasks/manage-gpus/scheduling-gpus/)

### Community

- llama.cpp Issues: https://github.com/ggml-org/llama.cpp/issues
- Qwen Issues: https://github.com/QwenLM/Qwen2.5/issues

---

## Version History

**Version 1.0** (2025-12-05)

- Initial deployment solution
- Complete documentation
- Management scripts
- Test examples
- Python client

**Created By:** Agent 2 - llama.cpp Kubernetes Deployment Specialist

**Hardware:** NVIDIA RTX 5080 (16GB VRAM) + 64GB RAM

**Models:** Qwen2.5-Coder-14B-Instruct + Qwen2.5-14B-Instruct (Q4_K_M)

---

## Next Steps

1. **Start Deployment:** Read README.md
2. **Follow Checklist:** Use DEPLOYMENT-CHECKLIST.md
3. **Deploy Services:** Run `./manage-llm-deployments.sh deploy`
4. **Test Setup:** Run `./test-examples.sh all`
5. **Integrate API:** Use python-client-example.py as reference

**Good luck with your deployment!**
