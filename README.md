# Local LLM on Kubernetes

Run large language models locally on Kubernetes with GPU acceleration using [llama.cpp](https://github.com/ggerganov/llama.cpp).

This repository provides scripts to deploy llama.cpp as an opencode.ai compatible API server on a single-node Kubernetes cluster. It handles NVIDIA GPU setup, container toolkit configuration, and Kubernetes deployment.

**Tested on:** WSL2 with a Kubernetes cluster deployed using [github.com/raphideb/kube](https://github.com/raphideb/kube)

**Note:** This project was completely done with claude-code opus, I am just getting started with running my own LLM. If you have claude, you can have it read PROJECT-CONTEXT.md as a starting point for your own environment. If your k8s is deployed with the scripts from my kube repo, chances are high that it will just work ;)  

## Hardware Specs

| Component | Specification |
|-----------|---------------|
| GPU | NVIDIA RTX 5080 (16GB VRAM) |
| CPU | AMD Ryzen 9 9900X |
| RAM | 64GB |

I run **Qwen2.5-Coder-14B-Q4_K_M** on GPU for coding tasks. It uses all 16GB VRAM and is surprisingly fast.

**Want to use a different model?** Use [`manage-models.sh`](docs/MODEL-MANAGER-GUIDE.md) to download, install, and switch between models. Only one model can run on GPU at a time, but you can run multiple models on CPU simultaneously.

## Quick Start

```bash
cd setup-llama-k8s

# 1. Configure your model (interactive)
./setup.sh configure

# 2. Full installation
./setup.sh all

# 3. Test it works
./setup.sh test
```

## Model Management

After initial setup, use `manage-models.sh` to manage multiple models:

```bash
./manage-models.sh download qwen2.5-coder-7b-q4   # Download a model
./manage-models.sh install                         # Install to Kubernetes
./manage-models.sh activate                        # Start a model
./manage-models.sh list                            # Show deployed models
```

See the full [Model Manager Guide](docs/MODEL-MANAGER-GUIDE.md) for all commands and examples.

## Commands

| Command | Description |
|---------|-------------|
| `configure` | Set up model path or download a model |
| `preflight` | Check system requirements |
| `nvidia` | Install NVIDIA Container Toolkit |
| `device-plugin` | Deploy NVIDIA device plugin |
| `deploy` | Deploy llama.cpp server |
| `opencode` | Install and configure opencode |
| `test` | Test the deployment |
| `status` | Show current status |
| `cleanup` | Remove llama.cpp deployment |
| `all` | Run full installation |

## Options

```bash
./setup.sh --dry-run <command>  # Preview without executing
./setup.sh --help               # Show help
```

## Model Configuration

The `configure` command offers three options:

1. **Use existing model** - Point to your .gguf file
2. **Download recommended model** - Qwen2.5-Coder-14B-Q4_K_M (~8.5GB)
3. **Download custom model** - Any URL to a .gguf file

Configuration is saved to `.llama-config`.

## Requirements

- NVIDIA GPU with 8GB+ VRAM
- Kubernetes cluster with kubectl access
- Docker with NVIDIA runtime
- wget or curl (for model download)


## After deployment
### opencode
Start opencode and choose your model:
```bash
opencode
```
![opencode](https://github.com/user-attachments/assets/ef123585-6e62-44d1-b2d4-eace16fffdff)

### API Usage

```bash
# Health check
curl http://<NODE_IP>:30080/health

# Chat completion
curl http://<NODE_IP>:30080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"local","messages":[{"role":"user","content":"Hello"}]}'
```

## Troubleshooting

```bash
# Check pod status
kubectl get pods -n llama

# View logs
kubectl logs -n llama -l app=llama-server -f

# Check GPU
nvidia-smi

# Re-deploy after config change
./setup.sh deploy
```
