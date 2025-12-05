# llama.cpp on Kubernetes

Deploy llama.cpp with GPU acceleration on Kubernetes.

## Quick Start

```bash
# 1. Configure your model (interactive)
./setup.sh configure

# 2. Full installation
./setup.sh all

# 3. Test it works
./setup.sh test
```

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

## API Usage

After deployment:

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
