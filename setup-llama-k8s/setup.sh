#!/bin/bash
#
# llama.cpp Kubernetes Setup Script
# For WSL2/Linux with NVIDIA GPU
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration (can be overridden by config file or environment)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.llama-config"
LOG_FILE="${SCRIPT_DIR}/setup.log"
NAMESPACE="llama"
SERVICE_PORT=30080
DRY_RUN=false

# Default model settings
DEFAULT_MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-Coder-14B-Instruct-GGUF/resolve/main/qwen2.5-coder-14b-instruct-q4_k_m.gguf"
DEFAULT_MODEL_NAME="qwen2.5-coder-14b-instruct-q4_k_m.gguf"

# Load config if exists
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# Save config
save_config() {
    cat > "$CONFIG_FILE" << EOF
# llama.cpp Kubernetes Configuration
# Generated: $(date)

MODELS_PATH="${MODELS_PATH}"
MODEL_FILE="${MODEL_FILE}"
NODE_IP="${NODE_IP}"
EOF
    log INFO "Configuration saved to $CONFIG_FILE"
}

# Functions
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" >> "$LOG_FILE"

    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} ${message}" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} ${message}" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} ${message}" ;;
        CHECK) echo -e "${CYAN}[CHECK]${NC} ${message}" ;;
        STEP)  echo -e "${BLUE}[STEP]${NC} ${message}" ;;
    esac
}

header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    if [ -n "$default" ]; then
        read -p "$(echo -e "${CYAN}${prompt}${NC} [${default}]: ")" input
        eval "$var_name=\"${input:-$default}\""
    else
        read -p "$(echo -e "${CYAN}${prompt}${NC}: ")" input
        eval "$var_name=\"$input\""
    fi
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        read -p "$(echo -e "${CYAN}${prompt}${NC} [Y/n]: ")" answer
        [[ ! "$answer" =~ ^[Nn]$ ]]
    else
        read -p "$(echo -e "${CYAN}${prompt}${NC} [y/N]: ")" answer
        [[ "$answer" =~ ^[Yy]$ ]]
    fi
}

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: $@"
        return 0
    fi
    "$@"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Configure models interactively
configure_models() {
    header "Model Configuration"

    echo -e "${BOLD}How would you like to set up the model?${NC}"
    echo ""
    echo "  1) Use existing model file"
    echo "  2) Download recommended model (Qwen2.5-Coder-14B-Q4_K_M, ~8.5GB)"
    echo "  3) Download custom model from URL"
    echo ""

    read -p "$(echo -e "${CYAN}Select option${NC} [1-3]: ")" model_option

    case $model_option in
        1)
            configure_existing_model
            ;;
        2)
            download_recommended_model
            ;;
        3)
            download_custom_model
            ;;
        *)
            log ERROR "Invalid option"
            return 1
            ;;
    esac

    # Verify model exists
    if [ ! -f "${MODELS_PATH}/${MODEL_FILE}" ]; then
        log ERROR "Model file not found: ${MODELS_PATH}/${MODEL_FILE}"
        return 1
    fi

    local model_size=$(du -h "${MODELS_PATH}/${MODEL_FILE}" | cut -f1)
    log INFO "Model configured: ${MODEL_FILE} (${model_size})"

    # Save configuration
    save_config
}

configure_existing_model() {
    echo ""
    log INFO "Enter the path to your models directory"
    echo -e "  ${YELLOW}This directory should contain your .gguf model file${NC}"
    echo ""

    prompt_input "Models directory path" "$HOME/models" MODELS_PATH

    # Expand ~ if present
    MODELS_PATH="${MODELS_PATH/#\~/$HOME}"

    if [ ! -d "$MODELS_PATH" ]; then
        log ERROR "Directory does not exist: $MODELS_PATH"
        if prompt_yes_no "Create directory?"; then
            mkdir -p "$MODELS_PATH"
            log INFO "Created directory: $MODELS_PATH"
        else
            return 1
        fi
    fi

    # List available models
    echo ""
    log INFO "Available .gguf files in $MODELS_PATH:"
    local models=$(ls -1 "$MODELS_PATH"/*.gguf 2>/dev/null || true)

    if [ -z "$models" ]; then
        log WARN "No .gguf files found in $MODELS_PATH"
        echo ""
        if prompt_yes_no "Download recommended model to this directory?"; then
            download_recommended_model
            return $?
        fi
        return 1
    fi

    echo "$models" | while read f; do
        local size=$(du -h "$f" | cut -f1)
        echo -e "  ${GREEN}$(basename "$f")${NC} ($size)"
    done
    echo ""

    prompt_input "Model filename" "$(basename "$(ls -1 "$MODELS_PATH"/*.gguf 2>/dev/null | head -1)")" MODEL_FILE
}

download_recommended_model() {
    echo ""
    prompt_input "Download directory" "$HOME/models" MODELS_PATH
    MODELS_PATH="${MODELS_PATH/#\~/$HOME}"
    MODEL_FILE="$DEFAULT_MODEL_NAME"

    mkdir -p "$MODELS_PATH"

    local target="${MODELS_PATH}/${MODEL_FILE}"

    if [ -f "$target" ]; then
        log INFO "Model already exists: $target"
        if ! prompt_yes_no "Re-download?"; then
            return 0
        fi
    fi

    log STEP "Downloading Qwen2.5-Coder-14B-Instruct-Q4_K_M (~8.5GB)..."
    echo -e "  ${YELLOW}This may take a while depending on your connection${NC}"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would download: $DEFAULT_MODEL_URL"
        echo -e "${YELLOW}[DRY-RUN]${NC} To: $target"
        return 0
    fi

    if check_command wget; then
        wget -c --progress=bar:force -O "$target" "$DEFAULT_MODEL_URL"
    elif check_command curl; then
        curl -L --progress-bar -o "$target" "$DEFAULT_MODEL_URL"
    else
        log ERROR "Neither wget nor curl found. Please install one of them."
        return 1
    fi

    log INFO "Download complete: $target"
}

download_custom_model() {
    echo ""
    prompt_input "Model download URL" "" MODEL_URL

    if [ -z "$MODEL_URL" ]; then
        log ERROR "URL is required"
        return 1
    fi

    prompt_input "Download directory" "$HOME/models" MODELS_PATH
    MODELS_PATH="${MODELS_PATH/#\~/$HOME}"

    # Extract filename from URL
    local default_name=$(basename "$MODEL_URL" | sed 's/?.*//')
    prompt_input "Save as filename" "$default_name" MODEL_FILE

    mkdir -p "$MODELS_PATH"

    local target="${MODELS_PATH}/${MODEL_FILE}"

    log STEP "Downloading model..."

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would download: $MODEL_URL"
        echo -e "${YELLOW}[DRY-RUN]${NC} To: $target"
        return 0
    fi

    if check_command wget; then
        wget -c --progress=bar:force -O "$target" "$MODEL_URL"
    elif check_command curl; then
        curl -L --progress-bar -o "$target" "$MODEL_URL"
    else
        log ERROR "Neither wget nor curl found."
        return 1
    fi

    log INFO "Download complete: $target"
}

# Pre-flight Checks
preflight_checks() {
    header "Pre-flight Checks"

    local all_ok=true

    # Check NVIDIA driver
    log CHECK "Checking NVIDIA driver..."
    if nvidia-smi &> /dev/null; then
        local gpu_info=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)
        log INFO "GPU detected: $gpu_info"
    else
        log ERROR "NVIDIA driver not detected. GPU passthrough may not be configured."
        all_ok=false
    fi

    # Check Docker
    log CHECK "Checking Docker..."
    if check_command docker; then
        if docker info &> /dev/null; then
            log INFO "Docker daemon is running"
            if docker info 2>/dev/null | grep -q "nvidia"; then
                log INFO "NVIDIA runtime is configured in Docker"
            else
                log WARN "NVIDIA runtime not found in Docker. Will need to configure."
            fi
        else
            log ERROR "Docker daemon is not running or not accessible"
            all_ok=false
        fi
    else
        log ERROR "Docker not found"
        all_ok=false
    fi

    # Check kubectl
    log CHECK "Checking kubectl..."
    if check_command kubectl; then
        if kubectl cluster-info &> /dev/null; then
            log INFO "Kubernetes cluster is accessible"
            NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
            local node_name=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
            log INFO "Node: $node_name ($NODE_IP)"
        else
            log ERROR "Cannot connect to Kubernetes cluster"
            all_ok=false
        fi
    else
        log ERROR "kubectl not found"
        all_ok=false
    fi

    # Check GPU allocatable
    log CHECK "Checking GPU resources on node..."
    local gpu_count=$(kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null)
    if [ -n "$gpu_count" ] && [ "$gpu_count" != "0" ]; then
        log INFO "GPU allocatable on node: $gpu_count"
    else
        log WARN "No GPU resources detected on node (nvidia.com/gpu). Run 'device-plugin' step first."
    fi

    # Check model configuration
    log CHECK "Checking model configuration..."
    if load_config && [ -n "$MODELS_PATH" ] && [ -n "$MODEL_FILE" ]; then
        if [ -f "${MODELS_PATH}/${MODEL_FILE}" ]; then
            local size=$(du -h "${MODELS_PATH}/${MODEL_FILE}" | cut -f1)
            log INFO "Model: ${MODEL_FILE} (${size})"
        else
            log WARN "Configured model not found. Run 'configure' step."
        fi
    else
        log WARN "Model not configured. Run 'configure' step."
    fi

    echo ""
    if [ "$all_ok" = true ]; then
        log INFO "All pre-flight checks passed!"
        return 0
    else
        log ERROR "Some pre-flight checks failed. Please review the errors above."
        return 1
    fi
}

# Install NVIDIA Container Toolkit
install_nvidia_toolkit() {
    header "Installing NVIDIA Container Toolkit"

    if check_command nvidia-ctk; then
        local version=$(nvidia-ctk --version 2>/dev/null | head -1)
        log INFO "NVIDIA Container Toolkit already installed: $version"
        if ! prompt_yes_no "Reinstall?"; then
            return 0
        fi
    fi

    log STEP "Installing prerequisites..."
    run_cmd sudo apt-get update
    run_cmd sudo apt-get install -y curl gnupg2

    log STEP "Adding NVIDIA Container Toolkit repository..."
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would add NVIDIA Container Toolkit apt repository"
    else
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

        curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null
    fi

    log STEP "Installing nvidia-container-toolkit..."
    run_cmd sudo apt-get update
    run_cmd sudo apt-get install -y nvidia-container-toolkit

    log INFO "NVIDIA Container Toolkit installed successfully"
}

# Configure Docker for NVIDIA
configure_docker_nvidia() {
    header "Configuring Docker for NVIDIA"

    if docker info 2>/dev/null | grep -q "Default Runtime: nvidia"; then
        log INFO "Docker already configured with nvidia as default runtime"
        return 0
    fi

    log STEP "Configuring Docker with nvidia runtime..."
    run_cmd sudo nvidia-ctk runtime configure --runtime=docker --set-as-default

    log STEP "Restarting Docker daemon..."
    run_cmd sudo systemctl restart docker

    sleep 3

    log STEP "Verifying Docker NVIDIA configuration..."
    if [ "$DRY_RUN" != true ]; then
        if docker run --rm nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi &> /dev/null; then
            log INFO "Docker NVIDIA runtime configured successfully"
        else
            log ERROR "Failed to verify Docker NVIDIA runtime"
            return 1
        fi
    fi
}

# Deploy NVIDIA Device Plugin
deploy_nvidia_device_plugin() {
    header "Deploying NVIDIA Device Plugin"

    if kubectl get daemonset -n nvidia-device-plugin nvidia-device-plugin-daemonset &> /dev/null; then
        log INFO "NVIDIA device plugin already deployed"
        if ! prompt_yes_no "Redeploy?"; then
            return 0
        fi
        run_cmd kubectl delete -f "${SCRIPT_DIR}/manifests/nvidia-device-plugin.yaml" || true
    fi

    log STEP "Creating nvidia-device-plugin namespace..."
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would create namespace: nvidia-device-plugin"
    else
        kubectl create namespace nvidia-device-plugin --dry-run=client -o yaml | kubectl apply -f -
    fi

    log STEP "Deploying NVIDIA device plugin..."
    run_cmd kubectl apply -f "${SCRIPT_DIR}/manifests/nvidia-device-plugin.yaml"

    log STEP "Waiting for device plugin to be ready..."
    run_cmd kubectl rollout status daemonset/nvidia-device-plugin-daemonset -n nvidia-device-plugin --timeout=120s

    log STEP "Waiting for GPU to be detected by Kubernetes..."
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would wait for GPU to be detected on node"
        return 0
    fi

    local retries=0
    while [ $retries -lt 30 ]; do
        local gpu_count=$(kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' 2>/dev/null)
        if [ -n "$gpu_count" ] && [ "$gpu_count" != "0" ]; then
            log INFO "GPU detected: $gpu_count available"
            return 0
        fi
        sleep 2
        retries=$((retries + 1))
    done

    log ERROR "Timeout waiting for GPU to be detected"
    return 1
}

# Generate deployment manifest
generate_deployment_manifest() {
    local node_name=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    cat > "${SCRIPT_DIR}/manifests/llama-deployment.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llama-server
  namespace: ${NAMESPACE}
  labels:
    app: llama-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: llama-server
  template:
    metadata:
      labels:
        app: llama-server
    spec:
      containers:
        - name: llama-server
          image: ghcr.io/ggml-org/llama.cpp:server-cuda
          ports:
            - containerPort: 8080
              name: http
          args:
            - --model
            - /models/${MODEL_FILE}
            - --host
            - "0.0.0.0"
            - --port
            - "8080"
            - -ngl
            - "99"
            - --ctx-size
            - "32768"
            - -b
            - "2048"
            - -ub
            - "512"
            - --threads
            - "8"
            - --flash-attn
            - "on"
            - --metrics
          resources:
            limits:
              nvidia.com/gpu: 1
              memory: "16Gi"
            requests:
              nvidia.com/gpu: 1
              memory: "8Gi"
          volumeMounts:
            - name: models
              mountPath: /models
              readOnly: true
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 120
            periodSeconds: 30
            timeoutSeconds: 10
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          env:
            - name: CUDA_VISIBLE_DEVICES
              value: "0"
      volumes:
        - name: models
          hostPath:
            path: ${MODELS_PATH}
            type: Directory
      nodeSelector:
        kubernetes.io/hostname: ${node_name}
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
EOF

    cat > "${SCRIPT_DIR}/manifests/llama-service.yaml" << EOF
apiVersion: v1
kind: Service
metadata:
  name: llama-server
  namespace: ${NAMESPACE}
  labels:
    app: llama-server
spec:
  type: NodePort
  selector:
    app: llama-server
  ports:
    - name: http
      port: 8080
      targetPort: 8080
      nodePort: ${SERVICE_PORT}
      protocol: TCP
EOF

    log INFO "Generated deployment manifests"
}

# Deploy llama.cpp
deploy_llama() {
    header "Deploying llama.cpp Server"

    # Check configuration
    if ! load_config || [ -z "$MODELS_PATH" ] || [ -z "$MODEL_FILE" ]; then
        log ERROR "Model not configured. Run './setup.sh configure' first."
        return 1
    fi

    if [ ! -f "${MODELS_PATH}/${MODEL_FILE}" ]; then
        log ERROR "Model file not found: ${MODELS_PATH}/${MODEL_FILE}"
        return 1
    fi

    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    log INFO "Target node IP: $NODE_IP"
    log INFO "Model: ${MODEL_FILE}"
    log INFO "Models path: ${MODELS_PATH}"

    log STEP "Generating deployment manifests..."
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would generate manifests with:"
        echo -e "${YELLOW}[DRY-RUN]${NC}   MODEL_FILE=${MODEL_FILE}"
        echo -e "${YELLOW}[DRY-RUN]${NC}   MODELS_PATH=${MODELS_PATH}"
    else
        generate_deployment_manifest
    fi

    log STEP "Creating namespace..."
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would create namespace: $NAMESPACE"
    else
        kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    fi

    log STEP "Deploying llama.cpp server..."
    run_cmd kubectl apply -f "${SCRIPT_DIR}/manifests/llama-deployment.yaml"
    run_cmd kubectl apply -f "${SCRIPT_DIR}/manifests/llama-service.yaml"

    log STEP "Waiting for deployment to be ready..."
    if [ "$DRY_RUN" != true ]; then
        if ! kubectl rollout status deployment/llama-server -n "$NAMESPACE" --timeout=300s; then
            log WARN "Deployment may still be starting (large model load time)"
            log INFO "Check logs with: kubectl logs -n $NAMESPACE -l app=llama-server -f"
        fi
    fi

    echo ""
    log INFO "Deployment complete!"
    log INFO "API endpoint: http://${NODE_IP}:${SERVICE_PORT}/v1"
    log INFO ""
    log INFO "Test with:"
    log INFO "  curl http://${NODE_IP}:${SERVICE_PORT}/health"
}

# Install opencode
install_opencode() {
    header "Installing opencode"

    if check_command opencode; then
        local version=$(opencode --version 2>/dev/null || echo "unknown")
        log INFO "opencode already installed: $version"
        if ! prompt_yes_no "Reinstall?"; then
            configure_opencode
            return 0
        fi
    fi

    log STEP "Installing opencode..."
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: curl -fsSL https://opencode.ai/install | bash"
        echo -e "${YELLOW}[DRY-RUN]${NC} Would add ~/.opencode/bin to PATH in ~/.bashrc"
    else
        curl -fsSL https://opencode.ai/install | bash

        if [ -d "$HOME/.opencode/bin" ]; then
            export PATH="$HOME/.opencode/bin:$PATH"
            if ! grep -q ".opencode/bin" "$HOME/.bashrc" 2>/dev/null; then
                echo 'export PATH="$HOME/.opencode/bin:$PATH"' >> "$HOME/.bashrc"
            fi
        fi
    fi

    configure_opencode
}

# Configure opencode
configure_opencode() {
    header "Configuring opencode for llama.cpp"

    load_config
    NODE_IP=${NODE_IP:-$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)}

    log STEP "Creating opencode configuration..."

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would create opencode config at ~/.config/opencode/config.json"
        echo -e "${YELLOW}[DRY-RUN]${NC} Would configure endpoint: http://${NODE_IP}:${SERVICE_PORT}/v1"
    else
        mkdir -p "$HOME/.config/opencode"
        mkdir -p "$HOME/.local/share/opencode"

        cat > "$HOME/.config/opencode/config.json" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "llama-local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Local LLM",
      "options": {
        "baseURL": "http://${NODE_IP}:${SERVICE_PORT}/v1",
        "apiKey": "not-needed"
      },
      "models": {
        "local-model": {
          "name": "Local Model",
          "limit": {
            "context": 32768,
            "output": 8192
          }
        }
      }
    }
  }
}
EOF

        cat > "$HOME/.local/share/opencode/auth.json" << EOF
{
  "llama-local": {
    "type": "api",
    "key": "not-needed"
  }
}
EOF
    fi

    log INFO "opencode configured successfully"
    log INFO "Config file: $HOME/.config/opencode/config.json"
    log INFO "Run 'opencode' to start"
}

# Test deployment
test_deployment() {
    header "Testing Deployment"

    load_config
    NODE_IP=${NODE_IP:-$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)}

    log STEP "Checking pod status..."
    kubectl get pods -n "$NAMESPACE"

    log STEP "Testing API endpoint..."
    local health=$(curl -s -o /dev/null -w "%{http_code}" "http://${NODE_IP}:${SERVICE_PORT}/health" 2>/dev/null || echo "000")

    if [ "$health" = "200" ]; then
        log INFO "Health check: OK"

        log STEP "Testing completion..."
        local response=$(curl -s "http://${NODE_IP}:${SERVICE_PORT}/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d '{"model":"local","messages":[{"role":"user","content":"Say hello"}],"max_tokens":20}' 2>/dev/null)

        if echo "$response" | grep -q "choices"; then
            log INFO "Completion test: OK"
            echo ""
            echo -e "${GREEN}Response:${NC}"
            echo "$response" | grep -o '"content":"[^"]*"' | head -1 | sed 's/"content":"//;s/"$//'
        else
            log WARN "Completion test returned unexpected response"
        fi
    else
        log WARN "API not responding (HTTP $health) - model may still be loading"
        log INFO "Check logs with: kubectl logs -n $NAMESPACE -l app=llama-server -f"
    fi

    echo ""
    log INFO "GPU Status:"
    nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv 2>/dev/null || log WARN "nvidia-smi not available"
}

# Show status
show_status() {
    header "Current Status"

    load_config
    NODE_IP=${NODE_IP:-$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)}

    echo -e "${CYAN}Configuration:${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        echo "  Models path: ${MODELS_PATH:-not set}"
        echo "  Model file:  ${MODEL_FILE:-not set}"
        echo "  Node IP:     ${NODE_IP:-not set}"
    else
        echo "  Not configured. Run './setup.sh configure'"
    fi
    echo ""

    echo -e "${CYAN}Kubernetes Cluster:${NC}"
    kubectl get nodes -o wide 2>/dev/null || echo "  Not accessible"
    echo ""

    echo -e "${CYAN}NVIDIA Device Plugin:${NC}"
    kubectl get pods -n nvidia-device-plugin 2>/dev/null || echo "  Not deployed"
    echo ""

    echo -e "${CYAN}llama.cpp Deployment:${NC}"
    kubectl get deployments,pods,svc -n "$NAMESPACE" 2>/dev/null || echo "  Not deployed"
    echo ""

    echo -e "${CYAN}GPU Usage:${NC}"
    nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv 2>/dev/null || echo "  nvidia-smi not available"
    echo ""

    if [ -n "$NODE_IP" ]; then
        echo -e "${CYAN}API Endpoint:${NC}"
        echo "  http://${NODE_IP}:${SERVICE_PORT}/v1"
    fi
}

# Cleanup
cleanup() {
    header "Cleanup"

    log WARN "This will remove all llama.cpp deployments from Kubernetes"
    if ! prompt_yes_no "Continue?"; then
        return 0
    fi

    log STEP "Deleting llama namespace..."
    run_cmd kubectl delete namespace "$NAMESPACE" --ignore-not-found

    log INFO "Cleanup complete"
    log INFO "Note: NVIDIA device plugin and container toolkit were not removed"
}

# Usage
usage() {
    echo -e "${BOLD}llama.cpp Kubernetes Setup Script${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  configure     Configure model path and download models"
    echo "  preflight     Run pre-flight checks"
    echo "  nvidia        Install NVIDIA Container Toolkit and configure Docker"
    echo "  device-plugin Deploy NVIDIA device plugin to Kubernetes"
    echo "  deploy        Deploy llama.cpp server"
    echo "  opencode      Install and configure opencode"
    echo "  test          Test the deployment"
    echo "  status        Show current status"
    echo "  cleanup       Remove llama.cpp deployment"
    echo "  all           Run full installation (configure + nvidia + device-plugin + deploy)"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --dry-run     Show what would be done without executing"
    echo "  --help        Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 configure        # Configure model path"
    echo "  $0 preflight        # Check system requirements"
    echo "  $0 all              # Full installation"
    echo "  $0 --dry-run all    # Preview full installation"
    echo "  $0 deploy           # Deploy only llama.cpp"
    echo ""
    echo -e "${BOLD}Quick Start:${NC}"
    echo "  1. $0 configure     # Set up your model"
    echo "  2. $0 all           # Install everything"
    echo "  3. $0 test          # Verify it works"
}

# Main
main() {
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done

    local command=${1:-help}

    # Initialize log
    echo "=== Setup started at $(date) ===" >> "$LOG_FILE"

    if [ "$DRY_RUN" = true ]; then
        log INFO "Running in DRY-RUN mode - no changes will be made"
    fi

    case $command in
        configure)
            configure_models
            ;;
        preflight)
            preflight_checks
            ;;
        nvidia)
            install_nvidia_toolkit
            configure_docker_nvidia
            ;;
        device-plugin)
            deploy_nvidia_device_plugin
            ;;
        deploy)
            deploy_llama
            ;;
        opencode)
            install_opencode
            ;;
        test)
            test_deployment
            ;;
        status)
            show_status
            ;;
        cleanup)
            cleanup
            ;;
        all)
            configure_models || exit 1
            preflight_checks || {
                log WARN "Some pre-flight checks failed but continuing..."
            }
            install_nvidia_toolkit
            configure_docker_nvidia
            deploy_nvidia_device_plugin
            deploy_llama
            install_opencode
            echo ""
            log INFO "Setup complete! Run './setup.sh test' to verify."
            ;;
        help|*)
            usage
            ;;
    esac
}

main "$@"
