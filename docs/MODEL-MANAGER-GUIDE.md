# LLM Model Manager User Guide

Manage multiple LLM models on your Kubernetes cluster with `manage-models.sh`. Download models from HuggingFace, install them to Kubernetes, and switch between models with automatic GPU management.

## Quick Reference

| Command | Description |
|---------|-------------|
| `./manage-models.sh list` | Show deployed models and status |
| `./manage-models.sh available` | Show locally downloaded models |
| `./manage-models.sh download` | Browse/download models from HuggingFace |
| `./manage-models.sh install` | Deploy a model to Kubernetes |
| `./manage-models.sh activate` | Start a model |
| `./manage-models.sh stop` | Stop a running model |
| `./manage-models.sh uninstall` | Remove model from Kubernetes |
| `./manage-models.sh modify` | Change model settings |
| `./manage-models.sh configure` | Set models directory |

---

## GPU vs CPU: Important Constraint

**Only one model can use the GPU at a time.** Multiple models can run simultaneously on CPU.

When you activate a GPU model while another is already using the GPU, the manager will offer options:

- Switch the new model to CPU mode
- Switch the existing GPU model to CPU and give GPU to the new model
- Cancel the operation

The manager handles this automatically during `install`, `activate`, and `modify` operations.

---

## Downloading Models

### Browse Available Models

```bash
./manage-models.sh download
```

This shows pre-configured models with their sizes:

```
SHORT NAME                         SIZE            REPOSITORY
────────────────────────────────────────────────────────────────────────
qwen2.5-coder-32b-q4               ~18GB           Qwen/Qwen2.5-Coder-32B-Instruct-GGUF
qwen2.5-coder-14b-q4               ~8.5GB          Qwen/Qwen2.5-Coder-14B-Instruct-GGUF
qwen2.5-coder-7b-q4                ~4.5GB          Qwen/Qwen2.5-Coder-7B-Instruct-GGUF
llama3.1-8b-q4                     ~4.9GB          bartowski/Meta-Llama-3.1-8B-Instruct-GGUF
deepseek-r1-distill-qwen-14b-q4    ~8.5GB          bartowski/DeepSeek-R1-Distill-Qwen-14B-GGUF
...
```

### Download a Pre-configured Model

```bash
./manage-models.sh download qwen2.5-coder-14b-q4
```

### Download from Custom URL

```bash
./manage-models.sh download https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf
```

### Search HuggingFace

Run `./manage-models.sh download` and answer "yes" when asked to search HuggingFace.

---

## Installing Models

Install deploys a model to Kubernetes but doesn't start it (replicas=0 by default).

### Interactive Install

```bash
./manage-models.sh install
```

Presents a menu of your downloaded models:

```
  1) qwen2.5-coder-14b-instruct-q4_k_m.gguf (8.5G)
  2) llama-3.2-3b-instruct-q4_k_m.gguf (2.0G) (already installed)

Select model number: 1
```

### Install by Filename

```bash
./manage-models.sh install qwen2.5-coder-14b-instruct-q4_k_m.gguf
```

### Installation Options

During install, you'll be asked:

- **Use GPU?** - Yes for GPU acceleration, No for CPU-only
- **Context size** - Default 32768, adjust based on your needs
- **Initial replicas** - 0 (scaled down) or 1 (start immediately)

If another model is already using the GPU, you get options:

```
GPU is currently in use by: llama-3-2-3b-instruct-q4-k-m

Options:
  1) Install new model in CPU mode (recommended)
  2) Switch 'llama-3-2-3b-instruct-q4-k-m' to CPU mode, install new model with GPU
  3) Install with GPU anyway (will compete for GPU resources)
```

---

## Activating Models

Start a model that's installed but stopped.

### Interactive Activation

```bash
./manage-models.sh activate
```

Shows models with their current state:

```
  1) qwen2-5-coder-14b-instruct-q4-k-m (stopped - GPU)
  2) llama-3-2-3b-instruct-q4-k-m (running - CPU)

Select model number: 1
```

### Activate by Name

```bash
./manage-models.sh activate qwen2-5-coder-14b-instruct-q4-k-m
```

### GPU Handling on Activation

If activating a GPU model while another uses the GPU:

```
GPU is already in use by: llama-3-2-3b-instruct-q4-k-m

Options:
  1) Start 'qwen2-5-coder-14b-instruct-q4-k-m' in CPU mode instead
  2) Switch 'llama-3-2-3b-instruct-q4-k-m' to CPU, start 'qwen2-5-coder-14b-instruct-q4-k-m' on GPU
  3) Cancel
```

After activation, the model is automatically added to your opencode configuration.

---

## Stopping Models

Scale a model to 0 replicas (keeps it installed for quick restart).

### Interactive Stop

```bash
./manage-models.sh stop
```

### Stop by Name

```bash
./manage-models.sh stop qwen2-5-coder-14b-instruct-q4-k-m
```

---

## Uninstalling Models

Remove a model from Kubernetes entirely. Model files on disk are preserved.

### Interactive Uninstall

```bash
./manage-models.sh uninstall
```

### Uninstall by Name

```bash
./manage-models.sh uninstall qwen2-5-coder-14b-instruct-q4-k-m
```

To reinstall later:

```bash
./manage-models.sh install qwen2.5-coder-14b-instruct-q4_k_m.gguf
```

---

## Modifying Model Settings

Change settings for an installed model.

```bash
./manage-models.sh modify
```

Or specify the model:

```bash
./manage-models.sh modify qwen2-5-coder-14b-instruct-q4-k-m
```

### Available Modifications

```
Current settings for 'qwen2-5-coder-14b-instruct-q4-k-m':

  Replicas:     1
  GPU enabled:  yes
  Context size: 32768

What would you like to modify?

  1) Replicas
  2) GPU mode (enable/disable)
  3) Context size
  4) All settings
```

### Switching GPU Mode

Select option 2 to toggle between GPU and CPU mode. The manager handles GPU conflicts automatically.

---

## Checking Status

### List Deployed Models

```bash
./manage-models.sh list
```

Output:

```
MODEL                              REPLICAS   PORT     STATUS          GPU
--------------------------------------------------------------------------------
qwen2-5-coder-14b-instruct-q4-k-m  1/1        30080    Running         1
llama-3-2-3b-instruct-q4-k-m       0/0        30081    Stopped         0

Active model: qwen2-5-coder-14b-instruct-q4-k-m
API endpoint: http://192.168.1.100:30080/v1
```

### List Local Models

```bash
./manage-models.sh available
```

Shows downloaded .gguf files and whether they're installed:

```
FILENAME                                           SIZE       INSTALLED
--------------------------------------------------------------------------------
qwen2.5-coder-14b-instruct-q4_k_m.gguf             8.5G       Yes
llama-3.2-3b-instruct-q4_k_m.gguf                  2.0G       Yes
mistral-7b-instruct-v0.2.Q4_K_M.gguf               4.4G       No
```

---

## Configuration

### Set Models Directory

```bash
./manage-models.sh configure
```

The directory where .gguf model files are stored. Default: `~/llm-models`

### Configuration File

Settings are stored in `~/.config/llm-manager/config`

---

## Typical Workflows

### Adding a New Model

```bash
# 1. Download
./manage-models.sh download qwen2.5-coder-7b-q4

# 2. Install (creates Kubernetes resources)
./manage-models.sh install

# 3. Activate (starts the model)
./manage-models.sh activate
```

### Switching Between Models (GPU)

```bash
# Stop current GPU model
./manage-models.sh stop qwen2-5-coder-14b-instruct-q4-k-m

# Activate different model with GPU
./manage-models.sh activate llama-3-2-3b-instruct-q4-k-m
# When prompted, choose to use GPU
```

### Running Multiple Models (CPU)

```bash
# Model A on GPU
./manage-models.sh activate model-a
# Choose GPU when prompted

# Model B on CPU (runs alongside)
./manage-models.sh activate model-b
# Choose CPU mode since GPU is in use
```

### Clean Removal

```bash
# Stop if running
./manage-models.sh stop my-model

# Remove from Kubernetes
./manage-models.sh uninstall my-model

# Optionally delete the file
rm ~/llm-models/my-model.gguf
```

---

## Troubleshooting

### Model Won't Start

```bash
# Check pod status
kubectl get pods -n llama

# View logs
kubectl logs -n llama -l app=<model-name> -f
```

### GPU Not Available

```bash
# Check GPU status
nvidia-smi

# Check device plugin
kubectl get pods -n kube-system | grep nvidia
```

### Model Loading Slowly

Large models take time to load into memory. Check progress:

```bash
kubectl logs -n llama -l app=<model-name> -f
```

### API Not Responding

```bash
# Check service
kubectl get svc -n llama

# Test health endpoint
curl http://<NODE_IP>:<PORT>/health
```

---

## opencode Integration

When you activate a model, it's automatically added to `~/.config/opencode/config.json`. Start opencode and select your model:

```bash
opencode
```

The model appears as a provider option in the opencode interface.
