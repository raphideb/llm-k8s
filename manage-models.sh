#!/bin/bash
#
# LLM Model Manager for Kubernetes
# Manages llama.cpp model deployments on Kubernetes
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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${HOME}/.config/llm-manager/config"
NAMESPACE="llama"
BASE_PORT=30080
OPENCODE_CONFIG="${HOME}/.config/opencode/config.json"
DEFAULT_MODELS_DIR="${HOME}/llm-models"

# Default llama.cpp server parameters
DEFAULT_CTX_SIZE=32768
DEFAULT_BATCH_SIZE=2048
DEFAULT_UBATCH_SIZE=512
DEFAULT_THREADS=8
DEFAULT_GPU_LAYERS=99

# Popular GGUF models on HuggingFace
declare -A HF_MODELS=(
    ["qwen2.5-coder-32b-q4"]="Qwen/Qwen2.5-Coder-32B-Instruct-GGUF|qwen2.5-coder-32b-instruct-q4_k_m.gguf|~18GB"
    ["qwen2.5-coder-14b-q4"]="Qwen/Qwen2.5-Coder-14B-Instruct-GGUF|qwen2.5-coder-14b-instruct-q4_k_m.gguf|~8.5GB"
    ["qwen2.5-coder-7b-q4"]="Qwen/Qwen2.5-Coder-7B-Instruct-GGUF|qwen2.5-coder-7b-instruct-q4_k_m.gguf|~4.5GB"
    ["qwen2.5-coder-3b-q4"]="Qwen/Qwen2.5-Coder-3B-Instruct-GGUF|qwen2.5-coder-3b-instruct-q4_k_m.gguf|~2GB"
    ["qwen2.5-14b-q4"]="Qwen/Qwen2.5-14B-Instruct-GGUF|qwen2.5-14b-instruct-q4_k_m.gguf|~8.5GB"
    ["qwen2.5-7b-q4"]="Qwen/Qwen2.5-7B-Instruct-GGUF|qwen2.5-7b-instruct-q4_k_m.gguf|~4.5GB"
    ["qwen2.5-3b-q4"]="Qwen/Qwen2.5-3B-Instruct-GGUF|qwen2.5-3b-instruct-q4_k_m.gguf|~2GB"
    ["llama3.2-3b-q4"]="bartowski/Llama-3.2-3B-Instruct-GGUF|Llama-3.2-3B-Instruct-Q4_K_M.gguf|~2GB"
    ["llama3.1-8b-q4"]="bartowski/Meta-Llama-3.1-8B-Instruct-GGUF|Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf|~4.9GB"
    ["llama3.1-70b-q4"]="bartowski/Meta-Llama-3.1-70B-Instruct-GGUF|Meta-Llama-3.1-70B-Instruct-Q4_K_M.gguf|~40GB"
    ["mistral-7b-q4"]="TheBloke/Mistral-7B-Instruct-v0.2-GGUF|mistral-7b-instruct-v0.2.Q4_K_M.gguf|~4.4GB"
    ["mixtral-8x7b-q4"]="TheBloke/Mixtral-8x7B-Instruct-v0.1-GGUF|mixtral-8x7b-instruct-v0.1.Q4_K_M.gguf|~26GB"
    ["deepseek-coder-v2-lite-q4"]="bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF|DeepSeek-Coder-V2-Lite-Instruct-Q4_K_M.gguf|~9GB"
    ["deepseek-r1-distill-qwen-14b-q4"]="bartowski/DeepSeek-R1-Distill-Qwen-14B-GGUF|DeepSeek-R1-Distill-Qwen-14B-Q4_K_M.gguf|~8.5GB"
    ["deepseek-r1-distill-qwen-7b-q4"]="bartowski/DeepSeek-R1-Distill-Qwen-7B-GGUF|DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf|~4.5GB"
    ["phi-3-mini-q4"]="bartowski/Phi-3-mini-128k-instruct-GGUF|Phi-3-mini-128k-instruct-Q4_K_M.gguf|~2.4GB"
    ["phi-3-medium-q4"]="bartowski/Phi-3-medium-128k-instruct-GGUF|Phi-3-medium-128k-instruct-Q4_K_M.gguf|~8.4GB"
    ["codestral-22b-q4"]="bartowski/Codestral-22B-v0.1-GGUF|Codestral-22B-v0.1-Q4_K_M.gguf|~13GB"
    ["gemma-2-9b-q4"]="bartowski/gemma-2-9b-it-GGUF|gemma-2-9b-it-Q4_K_M.gguf|~5.8GB"
    ["gemma-2-27b-q4"]="bartowski/gemma-2-27b-it-GGUF|gemma-2-27b-it-Q4_K_M.gguf|~16GB"
)

# Functions
log() {
    local level=$1
    shift
    local message="$@"

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

check_command() {
    command -v "$1" &> /dev/null
}

# Load configuration
load_config() {
    # First check our own config
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi

    # Fallback to setup.sh config if exists and MODELS_DIR not set
    local setup_config="${SCRIPT_DIR}/setup-llama-k8s/.llama-config"
    if [ -z "$MODELS_DIR" ] && [ -f "$setup_config" ]; then
        source "$setup_config"
        MODELS_DIR="${MODELS_PATH:-$DEFAULT_MODELS_DIR}"
    fi

    MODELS_DIR="${MODELS_DIR:-$DEFAULT_MODELS_DIR}"
}

# Ensure models directory is configured (called by commands that need it)
ensure_models_dir() {
    load_config

    # If config exists and directory exists, we're good
    if [ -f "$CONFIG_FILE" ] && [ -d "$MODELS_DIR" ]; then
        return 0
    fi

    # If directory exists (from setup.sh config), we're good
    if [ -d "$MODELS_DIR" ]; then
        return 0
    fi

    # First time setup - ask user
    echo ""
    log INFO "Models directory not configured yet."
    echo ""
    echo -e "Default directory: ${CYAN}${DEFAULT_MODELS_DIR}${NC}"
    echo ""

    if prompt_yes_no "Create default directory ($DEFAULT_MODELS_DIR)?"; then
        MODELS_DIR="$DEFAULT_MODELS_DIR"
        mkdir -p "$MODELS_DIR"
        save_config
        log INFO "Created: $MODELS_DIR"
    else
        prompt_input "Enter models directory path" "" MODELS_DIR
        MODELS_DIR="${MODELS_DIR/#\~/$HOME}"

        if [ -z "$MODELS_DIR" ]; then
            log ERROR "Models directory is required"
            return 1
        fi

        if [ ! -d "$MODELS_DIR" ]; then
            if prompt_yes_no "Directory does not exist. Create it?"; then
                mkdir -p "$MODELS_DIR"
                log INFO "Created: $MODELS_DIR"
            else
                log ERROR "Models directory does not exist"
                return 1
            fi
        fi

        save_config
    fi

    echo ""
    return 0
}

# Update opencode configuration - add a model as a provider
update_opencode_config() {
    local model_name="$1"
    local node_ip="$2"
    local port="$3"

    log STEP "Adding model to opencode configuration..."

    mkdir -p "$(dirname "$OPENCODE_CONFIG")"

    # Try to get actual context size from model API (n_ctx_train)
    local ctx_size=""
    local api_response=$(curl -s --connect-timeout 5 "http://${node_ip}:${port}/v1/models" 2>/dev/null)
    if [ -n "$api_response" ]; then
        ctx_size=$(echo "$api_response" | jq -r '.data[0].meta.n_ctx_train // empty' 2>/dev/null)
        if [ -n "$ctx_size" ] && [ "$ctx_size" != "null" ]; then
            log INFO "Detected model context size: $ctx_size"
        fi
    fi

    # Fall back to deployment args if API didn't return context size
    if [ -z "$ctx_size" ] || [ "$ctx_size" = "null" ]; then
        local args=$(kubectl get deployment "$model_name" -n "$NAMESPACE" -o json 2>/dev/null | \
            jq -r '.spec.template.spec.containers[0].args | join(" ")' 2>/dev/null)
        ctx_size=$(echo "$args" | grep -oP '(?<=--ctx-size )\d+' || echo "32768")
        ctx_size="${ctx_size:-32768}"
        log INFO "Using configured context size: $ctx_size"
    fi

    # Calculate output size (half of context, max 8192)
    local output_size=$((ctx_size / 2))
    if [ "$output_size" -gt 8192 ]; then
        output_size=8192
    fi

    # Create a friendly model name
    local friendly_name=$(echo "$model_name" | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')

    local base_url="http://${node_ip}:${port}/v1"

    # Use model name as provider key (sanitized)
    local provider_key="$model_name"

    if [ -f "$OPENCODE_CONFIG" ]; then
        # Backup existing config
        cp "$OPENCODE_CONFIG" "${OPENCODE_CONFIG}.bak"

        # Add/update this model's provider while preserving others
        local new_config=$(jq \
            --arg url "$base_url" \
            --arg name "$friendly_name" \
            --arg model "$model_name" \
            --arg provider "$provider_key" \
            --argjson ctx "$ctx_size" \
            --argjson out "$output_size" '
            .provider[$provider] = {
                "npm": "@ai-sdk/openai-compatible",
                "name": $name,
                "options": {
                    "baseURL": $url,
                    "apiKey": "not-needed"
                },
                "models": {
                    ($model): {
                        "name": $name,
                        "limit": {
                            "context": $ctx,
                            "output": $out
                        }
                    }
                }
            }
        ' "$OPENCODE_CONFIG" 2>/dev/null)

        if [ -n "$new_config" ] && echo "$new_config" | jq -e '.' &>/dev/null; then
            echo "$new_config" > "$OPENCODE_CONFIG"
        else
            log WARN "Could not update config with jq, creating new config"
            create_fresh_opencode_config "$model_name" "$friendly_name" "$base_url" "$ctx_size" "$output_size"
        fi
    else
        # Create new config
        create_fresh_opencode_config "$model_name" "$friendly_name" "$base_url" "$ctx_size" "$output_size"
    fi

    log INFO "Added to opencode: $friendly_name"
    log INFO "Endpoint: $base_url"
}

# Remove a model from opencode configuration
remove_from_opencode_config() {
    local model_name="$1"

    if [ ! -f "$OPENCODE_CONFIG" ]; then
        return 0
    fi

    log STEP "Removing model from opencode configuration..."

    cp "$OPENCODE_CONFIG" "${OPENCODE_CONFIG}.bak"

    local new_config=$(jq \
        --arg provider "$model_name" \
        'del(.provider[$provider])' \
        "$OPENCODE_CONFIG" 2>/dev/null)

    if [ -n "$new_config" ] && echo "$new_config" | jq -e '.' &>/dev/null; then
        echo "$new_config" > "$OPENCODE_CONFIG"
        log INFO "Removed '$model_name' from opencode config"
    fi
}

# Create a fresh opencode config (when no existing config)
create_fresh_opencode_config() {
    local model_name="$1"
    local friendly_name="$2"
    local base_url="$3"
    local ctx_size="$4"
    local output_size="${5:-8192}"

    cat > "$OPENCODE_CONFIG" << EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "${model_name}": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "${friendly_name}",
      "options": {
        "baseURL": "${base_url}",
        "apiKey": "not-needed"
      },
      "models": {
        "${model_name}": {
          "name": "${friendly_name}",
          "limit": {
            "context": ${ctx_size},
            "output": ${output_size}
          }
        }
      }
    }
  }
}
EOF
}

# Save configuration
save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << EOF
# LLM Manager Configuration
# Generated: $(date)

MODELS_DIR="${MODELS_DIR}"
EOF
    log INFO "Configuration saved to $CONFIG_FILE"
}

# Get node IP
get_node_ip() {
    kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null
}

# Get node name
get_node_name() {
    kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# Sanitize model name for Kubernetes resource names
sanitize_name() {
    local name="$1"
    echo "$name" | sed 's/[^a-zA-Z0-9]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-63
}

# Get next available port
get_next_port() {
    local used_ports=$(kubectl get svc -n "$NAMESPACE" -o jsonpath='{.items[*].spec.ports[*].nodePort}' 2>/dev/null | tr ' ' '\n' | sort -n)
    local port=$BASE_PORT

    while echo "$used_ports" | grep -q "^${port}$"; do
        port=$((port + 1))
    done

    echo $port
}

# Get deployment info for a model
get_deployment_info() {
    local deployment="$1"
    kubectl get deployment "$deployment" -n "$NAMESPACE" -o json 2>/dev/null
}

# ============================================================================
# COMMAND: list
# Shows which models are deployed
# ============================================================================
cmd_list() {
    header "Deployed Models"

    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log INFO "No models deployed (namespace '$NAMESPACE' does not exist)"
        return 0
    fi

    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    if [ -z "$deployments" ]; then
        log INFO "No models deployed"
        return 0
    fi

    printf "${BOLD}%-30s %-10s %-8s %-15s %-10s${NC}\n" "MODEL" "REPLICAS" "PORT" "STATUS" "GPU"
    echo "--------------------------------------------------------------------------------"

    for deployment in $deployments; do
        local info=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o json 2>/dev/null)
        local replicas=$(echo "$info" | jq -r '.spec.replicas // 0')
        local ready=$(echo "$info" | jq -r '.status.readyReplicas // 0')
        local gpu=$(echo "$info" | jq -r '.spec.template.spec.containers[0].resources.limits["nvidia.com/gpu"] // "0"')
        local port=$(kubectl get svc "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")

        local status="${GREEN}Running${NC}"
        if [ "$ready" = "0" ] && [ "$replicas" != "0" ]; then
            status="${YELLOW}Starting${NC}"
        elif [ "$replicas" = "0" ]; then
            status="${RED}Stopped${NC}"
        fi

        printf "%-30s %-10s %-8s %-15b %-10s\n" "$deployment" "$ready/$replicas" "$port" "$status" "$gpu"
    done

    echo ""

    # Show which model is active (has replicas > 0)
    local active=$(kubectl get deployments -n "$NAMESPACE" -o json 2>/dev/null | \
        jq -r '.items[] | select(.spec.replicas > 0) | .metadata.name' | head -1)

    if [ -n "$active" ]; then
        local active_port=$(kubectl get svc "$active" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
        local node_ip=$(get_node_ip)
        echo -e "${GREEN}Active model:${NC} $active"
        echo -e "${GREEN}API endpoint:${NC} http://${node_ip}:${active_port}/v1"
    fi
}

# ============================================================================
# COMMAND: available
# Shows which models are available locally
# ============================================================================
cmd_available() {
    header "Available Local Models"

    if ! ensure_models_dir; then
        return 1
    fi

    local models=$(find "$MODELS_DIR" -maxdepth 1 -name "*.gguf" -type f 2>/dev/null)

    if [ -z "$models" ]; then
        log INFO "No .gguf files found in $MODELS_DIR"
        log INFO "Run '$0 download' to download models"
        return 0
    fi

    echo -e "${BOLD}Models in ${MODELS_DIR}:${NC}"
    echo ""

    printf "${BOLD}%-50s %-10s %-10s${NC}\n" "FILENAME" "SIZE" "INSTALLED"
    echo "--------------------------------------------------------------------------------"

    while IFS= read -r model_path; do
        local filename=$(basename "$model_path")
        local size=$(du -h "$model_path" | cut -f1)
        local sanitized=$(sanitize_name "${filename%.gguf}")

        # Check if installed in Kubernetes
        local installed="${RED}No${NC}"
        if kubectl get deployment "$sanitized" -n "$NAMESPACE" &>/dev/null; then
            installed="${GREEN}Yes${NC}"
        fi

        printf "%-50s %-10s %-10b\n" "$filename" "$size" "$installed"
    done <<< "$models"

    echo ""
    log INFO "Total: $(echo "$models" | wc -l) model(s)"
}

# ============================================================================
# COMMAND: download
# Download models from HuggingFace
# ============================================================================
cmd_download() {
    local model_name="$1"

    if ! ensure_models_dir; then
        return 1
    fi

    if [ -z "$model_name" ]; then
        # Show available models
        header "Available Models on HuggingFace"

        echo -e "${BOLD}Pre-configured models (use short name to download):${NC}"
        echo ""

        printf "${BOLD}%-35s %-15s %-50s${NC}\n" "SHORT NAME" "SIZE" "REPOSITORY"
        echo "────────────────────────────────────────────────────────────────────────────────────────────────"

        for key in $(echo "${!HF_MODELS[@]}" | tr ' ' '\n' | sort); do
            IFS='|' read -r repo filename size <<< "${HF_MODELS[$key]}"
            printf "%-35s %-15s %-50s\n" "$key" "$size" "$repo"
        done

        echo ""
        echo -e "${BOLD}Usage:${NC}"
        echo "  $0 download <short-name>           Download pre-configured model"
        echo "  $0 download <huggingface-url>      Download from custom URL"
        echo ""
        echo -e "${BOLD}Examples:${NC}"
        echo "  $0 download qwen2.5-coder-14b-q4"
        echo "  $0 download https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF/resolve/main/mistral-7b-instruct-v0.2.Q4_K_M.gguf"
        echo ""

        # Search HuggingFace for GGUF models
        if prompt_yes_no "Search HuggingFace for more GGUF models?"; then
            echo ""
            prompt_input "Search term (e.g., 'qwen coder')" "" search_term
            if [ -n "$search_term" ]; then
                log STEP "Searching HuggingFace for '${search_term}'..."
                echo ""

                local search_url="https://huggingface.co/api/models?search=${search_term// /+}+gguf&sort=downloads&direction=-1&limit=20"
                local results=$(curl -s "$search_url" 2>/dev/null)

                if [ -n "$results" ] && echo "$results" | jq -e '.' &>/dev/null; then
                    echo -e "${BOLD}Search Results:${NC}"
                    echo ""
                    echo "$results" | jq -r '.[] | "  \(.id) (\(.downloads // 0) downloads)"' 2>/dev/null | head -20

                    echo ""
                    log INFO "To download, find the GGUF file URL on the model page and run:"
                    log INFO "  $0 download <url>"
                else
                    log WARN "Could not fetch search results"
                fi
            fi
        fi

        return 0
    fi

    # Check if it's a pre-configured model
    if [ -n "${HF_MODELS[$model_name]}" ]; then
        IFS='|' read -r repo filename size <<< "${HF_MODELS[$model_name]}"
        local url="https://huggingface.co/${repo}/resolve/main/${filename}"

        log INFO "Downloading: $filename ($size)"
        log INFO "From: $repo"
    elif [[ "$model_name" == http* ]]; then
        # It's a URL
        local url="$model_name"
        local filename=$(basename "$url" | sed 's/?.*//')
        log INFO "Downloading from URL: $url"
    else
        log ERROR "Unknown model: $model_name"
        log INFO "Run '$0 download' to see available models"
        return 1
    fi

    # Ensure models directory exists
    mkdir -p "$MODELS_DIR"

    local target="${MODELS_DIR}/${filename}"

    if [ -f "$target" ]; then
        log INFO "Model already exists: $target"
        if ! prompt_yes_no "Re-download?"; then
            return 0
        fi
    fi

    log STEP "Downloading to $target..."
    echo ""

    if check_command wget; then
        wget -c --progress=bar:force -O "$target" "$url"
    elif check_command curl; then
        curl -L --progress-bar -C - -o "$target" "$url"
    else
        log ERROR "Neither wget nor curl found. Please install one of them."
        return 1
    fi

    echo ""
    log INFO "Download complete: $target"
    log INFO "Run '$0 install $filename' to deploy this model"
}

# ============================================================================
# COMMAND: install
# Create Kubernetes manifests and deploy a model
# ============================================================================
cmd_install() {
    local model_file="$1"

    header "Install Model"

    if ! ensure_models_dir; then
        return 1
    fi

    if [ -z "$model_file" ]; then
        # Interactive selection
        log INFO "Select a model to install:"
        echo ""

        local models=$(find "$MODELS_DIR" -maxdepth 1 -name "*.gguf" -type f 2>/dev/null)

        if [ -z "$models" ]; then
            log ERROR "No models found in $MODELS_DIR"
            log INFO "Run '$0 download' to download models first"
            return 1
        fi

        local i=1
        declare -a model_array
        while IFS= read -r model_path; do
            local filename=$(basename "$model_path")
            local size=$(du -h "$model_path" | cut -f1)
            local sanitized=$(sanitize_name "${filename%.gguf}")

            local status=""
            if kubectl get deployment "$sanitized" -n "$NAMESPACE" &>/dev/null; then
                status="${YELLOW}(already installed)${NC}"
            fi

            echo -e "  $i) $filename ($size) $status"
            model_array[$i]="$filename"
            i=$((i + 1))
        done <<< "$models"

        echo ""
        prompt_input "Select model number" "" selection

        if [ -z "$selection" ] || [ -z "${model_array[$selection]}" ]; then
            log ERROR "Invalid selection"
            return 1
        fi

        model_file="${model_array[$selection]}"
    fi

    # Verify model exists
    local model_path="${MODELS_DIR}/${model_file}"
    if [ ! -f "$model_path" ]; then
        log ERROR "Model file not found: $model_path"
        return 1
    fi

    local deployment_name=$(sanitize_name "${model_file%.gguf}")
    local node_ip=$(get_node_ip)
    local node_name=$(get_node_name)

    # Check if already installed
    if kubectl get deployment "$deployment_name" -n "$NAMESPACE" &>/dev/null; then
        log INFO "Model '$deployment_name' is already installed"
        log INFO "Use '$0 activate $deployment_name' to activate it"
        log INFO "Use '$0 modify $deployment_name' to change its settings"
        return 0
    fi

    # Check for existing GPU models
    local gpu_models=$(kubectl get deployments -n "$NAMESPACE" -o json 2>/dev/null | \
        jq -r '.items[] | select(.spec.template.spec.containers[0].resources.limits["nvidia.com/gpu"] != null) | .metadata.name' 2>/dev/null)

    local running_gpu_model=""
    for gm in $gpu_models; do
        local replicas=$(kubectl get deployment "$gm" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
        if [ "$replicas" != "0" ]; then
            running_gpu_model="$gm"
            break
        fi
    done

    # Get configuration options
    echo ""
    echo -e "${BOLD}Configuration options:${NC}"
    echo ""

    local use_gpu="n"

    if [ -n "$running_gpu_model" ]; then
        log WARN "GPU is currently in use by: $running_gpu_model"
        echo ""
        echo "Options:"
        echo "  1) Install new model in CPU mode (recommended)"
        echo "  2) Switch '$running_gpu_model' to CPU mode, install new model with GPU"
        echo "  3) Install with GPU anyway (will compete for GPU resources)"
        echo ""
        prompt_input "Select option" "1" gpu_option

        case $gpu_option in
            1)
                use_gpu="n"
                log INFO "Installing in CPU mode"
                ;;
            2)
                log STEP "Switching '$running_gpu_model' to CPU mode..."
                kubectl patch deployment "$running_gpu_model" -n "$NAMESPACE" --type='json' -p='[
                    {"op": "remove", "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu"},
                    {"op": "remove", "path": "/spec/template/spec/containers/0/resources/requests/nvidia.com~1gpu"}
                ]' 2>/dev/null || log WARN "Could not remove GPU from $running_gpu_model"
                use_gpu="y"
                log INFO "Installing new model with GPU"
                ;;
            3)
                use_gpu="y"
                log WARN "Both models will compete for GPU resources"
                ;;
            *)
                use_gpu="n"
                log INFO "Installing in CPU mode"
                ;;
        esac
    else
        if prompt_yes_no "Use GPU?" "y"; then
            use_gpu="y"
        fi
    fi

    prompt_input "Context size" "$DEFAULT_CTX_SIZE" ctx_size
    prompt_input "Initial replicas (0 = scaled down)" "0" replicas

    local port=$(get_next_port)
    log INFO "Assigned port: $port"

    # Create namespace if needed
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null

    # Create manifests directory
    local manifests_dir="${SCRIPT_DIR}/setup-llama-k8s/manifests/models"
    mkdir -p "$manifests_dir"

    # Generate deployment manifest
    local deployment_file="${manifests_dir}/${deployment_name}-deployment.yaml"
    local service_file="${manifests_dir}/${deployment_name}-service.yaml"

    log STEP "Generating deployment manifest..."

    local gpu_resources=""
    local gpu_env=""
    if [ "$use_gpu" = "y" ]; then
        gpu_resources="
            limits:
              nvidia.com/gpu: 1
              memory: \"16Gi\"
            requests:
              nvidia.com/gpu: 1
              memory: \"8Gi\""
        gpu_env="
            - name: CUDA_VISIBLE_DEVICES
              value: \"0\""
    else
        gpu_resources="
            limits:
              memory: \"16Gi\"
            requests:
              memory: \"8Gi\""
    fi

    cat > "$deployment_file" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${deployment_name}
  namespace: ${NAMESPACE}
  labels:
    app: ${deployment_name}
    managed-by: llm-manager
spec:
  replicas: ${replicas}
  selector:
    matchLabels:
      app: ${deployment_name}
  template:
    metadata:
      labels:
        app: ${deployment_name}
    spec:
      containers:
        - name: llama-server
          image: ghcr.io/ggml-org/llama.cpp:server-cuda
          ports:
            - containerPort: 8080
              name: http
          args:
            - --model
            - /models/${model_file}
            - --host
            - "0.0.0.0"
            - --port
            - "8080"
            - -ngl
            - "${DEFAULT_GPU_LAYERS}"
            - --ctx-size
            - "${ctx_size}"
            - -b
            - "${DEFAULT_BATCH_SIZE}"
            - -ub
            - "${DEFAULT_UBATCH_SIZE}"
            - --threads
            - "${DEFAULT_THREADS}"
            - --flash-attn
            - "on"
            - --metrics
          resources:${gpu_resources}
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
          env:${gpu_env:-"
            - name: PLACEHOLDER
              value: \"none\""}
      volumes:
        - name: models
          hostPath:
            path: ${MODELS_DIR}
            type: Directory
      nodeSelector:
        kubernetes.io/hostname: ${node_name}
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
EOF

    # Generate service manifest
    cat > "$service_file" << EOF
apiVersion: v1
kind: Service
metadata:
  name: ${deployment_name}
  namespace: ${NAMESPACE}
  labels:
    app: ${deployment_name}
    managed-by: llm-manager
spec:
  type: NodePort
  selector:
    app: ${deployment_name}
  ports:
    - name: http
      port: 8080
      targetPort: 8080
      nodePort: ${port}
      protocol: TCP
EOF

    log STEP "Deploying to Kubernetes..."
    kubectl apply -f "$deployment_file"
    kubectl apply -f "$service_file"

    echo ""
    log INFO "Model '${deployment_name}' installed successfully!"
    log INFO "Port: $port"
    log INFO "API endpoint: http://${node_ip}:${port}/v1"

    # Add to opencode config
    update_opencode_config "$deployment_name" "$node_ip" "$port"

    if [ "$replicas" = "0" ]; then
        log INFO "Model is scaled down. Run '$0 activate $deployment_name' to start it."
    else
        log INFO "Waiting for deployment to be ready..."
        kubectl rollout status deployment/"$deployment_name" -n "$NAMESPACE" --timeout=300s || true
    fi
}

# ============================================================================
# COMMAND: activate
# Start a model (supports multiple concurrent models)
# ============================================================================
cmd_activate() {
    local model_name="$1"

    header "Activate Model"

    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log ERROR "No models installed"
        return 1
    fi

    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    if [ -z "$deployments" ]; then
        log ERROR "No models installed"
        return 1
    fi

    if [ -z "$model_name" ]; then
        # Interactive selection
        log INFO "Select a model to activate:"
        echo ""

        local i=1
        declare -a deploy_array
        for deployment in $deployments; do
            local replicas=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
            local has_gpu=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o json 2>/dev/null | \
                jq -r '.spec.template.spec.containers[0].resources.limits["nvidia.com/gpu"] // "0"')
            local mode="CPU"
            [ "$has_gpu" != "0" ] && [ "$has_gpu" != "null" ] && mode="GPU"

            local status=""
            if [ "$replicas" != "0" ]; then
                status="${GREEN}(running - ${mode})${NC}"
            else
                status="${YELLOW}(stopped - ${mode})${NC}"
            fi
            echo -e "  $i) $deployment $status"
            deploy_array[$i]="$deployment"
            i=$((i + 1))
        done

        echo ""
        prompt_input "Select model number" "" selection

        if [ -z "$selection" ] || [ -z "${deploy_array[$selection]}" ]; then
            log ERROR "Invalid selection"
            return 1
        fi

        model_name="${deploy_array[$selection]}"
    fi

    # Verify model exists
    if ! kubectl get deployment "$model_name" -n "$NAMESPACE" &>/dev/null; then
        log ERROR "Model '$model_name' is not installed"
        return 1
    fi

    # Check if already running
    local current_replicas=$(kubectl get deployment "$model_name" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [ "$current_replicas" != "0" ]; then
        log INFO "Model '$model_name' is already running"
        local port=$(kubectl get svc "$model_name" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
        local node_ip=$(get_node_ip)
        log INFO "API endpoint: http://${node_ip}:${port}/v1"
        # Still update opencode config in case it's missing
        update_opencode_config "$model_name" "$node_ip" "$port"
        return 0
    fi

    # Check if this model wants GPU
    local model_wants_gpu=$(kubectl get deployment "$model_name" -n "$NAMESPACE" -o json 2>/dev/null | \
        jq -r '.spec.template.spec.containers[0].resources.limits["nvidia.com/gpu"] // "0"')

    # Find running GPU model
    local running_gpu_model=""
    for deployment in $deployments; do
        local dep_replicas=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
        if [ "$dep_replicas" != "0" ]; then
            local dep_gpu=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o json 2>/dev/null | \
                jq -r '.spec.template.spec.containers[0].resources.limits["nvidia.com/gpu"] // "0"')
            if [ "$dep_gpu" != "0" ] && [ "$dep_gpu" != "null" ]; then
                running_gpu_model="$deployment"
                break
            fi
        fi
    done

    # Handle GPU allocation
    if [ "$model_wants_gpu" != "0" ] && [ "$model_wants_gpu" != "null" ]; then
        if [ -n "$running_gpu_model" ]; then
            log WARN "GPU is already in use by: $running_gpu_model"
            echo ""
            echo "Options:"
            echo "  1) Start '$model_name' in CPU mode instead"
            echo "  2) Switch '$running_gpu_model' to CPU, start '$model_name' on GPU"
            echo "  3) Cancel"
            echo ""
            prompt_input "Select option" "1" gpu_option

            case $gpu_option in
                1)
                    log STEP "Switching '$model_name' to CPU mode..."
                    kubectl patch deployment "$model_name" -n "$NAMESPACE" --type='json' -p='[
                        {"op": "remove", "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu"},
                        {"op": "remove", "path": "/spec/template/spec/containers/0/resources/requests/nvidia.com~1gpu"}
                    ]' 2>/dev/null || true
                    log INFO "Model will run on CPU"
                    ;;
                2)
                    log STEP "Switching '$running_gpu_model' to CPU mode..."
                    kubectl patch deployment "$running_gpu_model" -n "$NAMESPACE" --type='json' -p='[
                        {"op": "remove", "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu"},
                        {"op": "remove", "path": "/spec/template/spec/containers/0/resources/requests/nvidia.com~1gpu"}
                    ]' 2>/dev/null || true
                    log INFO "'$running_gpu_model' now running on CPU"
                    log INFO "'$model_name' will use GPU"
                    ;;
                *)
                    log INFO "Cancelled"
                    return 0
                    ;;
            esac
        else
            log INFO "GPU is available - '$model_name' will use GPU"
        fi
    else
        # Model is configured for CPU
        if [ -z "$running_gpu_model" ]; then
            # No GPU model running, offer to use GPU
            if prompt_yes_no "No GPU model running. Start '$model_name' with GPU instead?" "y"; then
                log STEP "Enabling GPU for '$model_name'..."
                kubectl patch deployment "$model_name" -n "$NAMESPACE" --type='json' -p='[
                    {"op": "add", "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu", "value": "1"},
                    {"op": "add", "path": "/spec/template/spec/containers/0/resources/requests/nvidia.com~1gpu", "value": "1"}
                ]' 2>/dev/null || true
                log INFO "GPU enabled for '$model_name'"
            fi
        fi
    fi

    log STEP "Starting: $model_name"
    kubectl scale deployment "$model_name" -n "$NAMESPACE" --replicas=1

    # Update opencode config
    local port=$(kubectl get svc "$model_name" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    local node_ip=$(get_node_ip)

    update_opencode_config "$model_name" "$node_ip" "$port"

    log STEP "Waiting for model to be ready..."
    kubectl rollout status deployment/"$model_name" -n "$NAMESPACE" --timeout=300s || true

    echo ""
    log INFO "Model '$model_name' is now active!"
    log INFO "API endpoint: http://${node_ip}:${port}/v1"

    # Test health
    local health=$(curl -s -o /dev/null -w "%{http_code}" "http://${node_ip}:${port}/health" 2>/dev/null || echo "000")
    if [ "$health" = "200" ]; then
        log INFO "Health check: ${GREEN}OK${NC}"
    else
        log WARN "Health check returned $health (model may still be loading)"
        log INFO "Check logs: kubectl logs -n $NAMESPACE -l app=$model_name -f"
    fi
}

# ============================================================================
# COMMAND: stop
# Stop a running model (scale to 0)
# ============================================================================
cmd_stop() {
    local model_name="$1"

    header "Stop Model"

    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log ERROR "No models installed"
        return 1
    fi

    # Get running models only
    local running_models=""
    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    for deployment in $deployments; do
        local replicas=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
        if [ "$replicas" != "0" ]; then
            running_models="$running_models $deployment"
        fi
    done

    running_models=$(echo "$running_models" | xargs)  # trim whitespace

    if [ -z "$running_models" ]; then
        log INFO "No models are currently running"
        return 0
    fi

    if [ -z "$model_name" ]; then
        # Interactive selection
        log INFO "Select a model to stop:"
        echo ""

        local i=1
        declare -a model_array
        for model in $running_models; do
            local has_gpu=$(kubectl get deployment "$model" -n "$NAMESPACE" -o json 2>/dev/null | \
                jq -r '.spec.template.spec.containers[0].resources.limits["nvidia.com/gpu"] // "0"')
            local mode="CPU"
            [ "$has_gpu" != "0" ] && [ "$has_gpu" != "null" ] && mode="GPU"

            echo -e "  $i) $model ${GREEN}(running - ${mode})${NC}"
            model_array[$i]="$model"
            i=$((i + 1))
        done

        echo ""
        prompt_input "Select model number" "" selection

        if [ -z "$selection" ] || [ -z "${model_array[$selection]}" ]; then
            log ERROR "Invalid selection"
            return 1
        fi

        model_name="${model_array[$selection]}"
    fi

    # Verify model exists and is running
    local current_replicas=$(kubectl get deployment "$model_name" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [ "$current_replicas" = "0" ]; then
        log INFO "Model '$model_name' is already stopped"
        return 0
    fi

    log STEP "Stopping: $model_name"
    kubectl scale deployment "$model_name" -n "$NAMESPACE" --replicas=0

    # Remove from opencode config
    remove_from_opencode_config "$model_name"

    echo ""
    log INFO "Model '$model_name' stopped"

    # Show remaining running models
    local still_running=""
    for deployment in $deployments; do
        if [ "$deployment" != "$model_name" ]; then
            local replicas=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
            if [ "$replicas" != "0" ]; then
                still_running="$still_running $deployment"
            fi
        fi
    done

    if [ -n "$still_running" ]; then
        log INFO "Still running:$still_running"
    else
        log INFO "No models are running"
    fi
}

# ============================================================================
# COMMAND: uninstall
# Remove model from Kubernetes (keep files)
# ============================================================================
cmd_uninstall() {
    local model_name="$1"

    header "Uninstall Model"

    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log ERROR "No models installed"
        return 1
    fi

    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    if [ -z "$deployments" ]; then
        log ERROR "No models installed"
        return 1
    fi

    if [ -z "$model_name" ]; then
        # Interactive selection
        log INFO "Select a model to uninstall:"
        echo ""

        local i=1
        declare -a deploy_array
        for deployment in $deployments; do
            echo "  $i) $deployment"
            deploy_array[$i]="$deployment"
            i=$((i + 1))
        done

        echo ""
        prompt_input "Select model number" "" selection

        if [ -z "$selection" ] || [ -z "${deploy_array[$selection]}" ]; then
            log ERROR "Invalid selection"
            return 1
        fi

        model_name="${deploy_array[$selection]}"
    fi

    # Verify model exists
    if ! kubectl get deployment "$model_name" -n "$NAMESPACE" &>/dev/null; then
        log ERROR "Model '$model_name' is not installed"
        return 1
    fi

    if ! prompt_yes_no "Uninstall '$model_name' from Kubernetes? (model files will be kept)"; then
        return 0
    fi

    log STEP "Removing deployment and service..."
    kubectl delete deployment "$model_name" -n "$NAMESPACE" --ignore-not-found
    kubectl delete svc "$model_name" -n "$NAMESPACE" --ignore-not-found

    # Remove manifest files if they exist
    local manifests_dir="${SCRIPT_DIR}/setup-llama-k8s/manifests/models"
    rm -f "${manifests_dir}/${model_name}-deployment.yaml" 2>/dev/null || true
    rm -f "${manifests_dir}/${model_name}-service.yaml" 2>/dev/null || true

    # Remove from opencode config
    remove_from_opencode_config "$model_name"

    echo ""
    log INFO "Model '$model_name' uninstalled from Kubernetes"
    log INFO "Model files in $MODELS_DIR were not deleted"
}

# ============================================================================
# COMMAND: configure
# Set download directory for models
# ============================================================================
cmd_configure() {
    header "Configure LLM Manager"

    load_config

    echo -e "${BOLD}Current configuration:${NC}"
    echo ""
    echo "  Models directory: ${MODELS_DIR:-not set}"
    echo ""

    prompt_input "Models directory" "${MODELS_DIR:-$DEFAULT_MODELS_DIR}" MODELS_DIR

    # Expand ~ if present
    MODELS_DIR="${MODELS_DIR/#\~/$HOME}"

    if [ ! -d "$MODELS_DIR" ]; then
        if prompt_yes_no "Directory does not exist. Create it?"; then
            mkdir -p "$MODELS_DIR"
            log INFO "Created directory: $MODELS_DIR"
        fi
    fi

    save_config

    echo ""
    log INFO "Configuration complete!"
}

# ============================================================================
# COMMAND: modify
# Change model settings (replicas, cpu/gpu, context size)
# ============================================================================
cmd_modify() {
    local model_name="$1"

    header "Modify Model Settings"

    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log ERROR "No models installed"
        return 1
    fi

    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

    if [ -z "$deployments" ]; then
        log ERROR "No models installed"
        return 1
    fi

    if [ -z "$model_name" ]; then
        # Interactive selection
        log INFO "Select a model to modify:"
        echo ""

        local i=1
        declare -a deploy_array
        for deployment in $deployments; do
            echo "  $i) $deployment"
            deploy_array[$i]="$deployment"
            i=$((i + 1))
        done

        echo ""
        prompt_input "Select model number" "" selection

        if [ -z "$selection" ] || [ -z "${deploy_array[$selection]}" ]; then
            log ERROR "Invalid selection"
            return 1
        fi

        model_name="${deploy_array[$selection]}"
    fi

    # Verify model exists
    if ! kubectl get deployment "$model_name" -n "$NAMESPACE" &>/dev/null; then
        log ERROR "Model '$model_name' is not installed"
        return 1
    fi

    # Get current settings
    local info=$(kubectl get deployment "$model_name" -n "$NAMESPACE" -o json 2>/dev/null)
    local current_replicas=$(echo "$info" | jq -r '.spec.replicas // 0')
    local current_gpu=$(echo "$info" | jq -r '.spec.template.spec.containers[0].resources.limits["nvidia.com/gpu"] // "0"')
    local current_args=$(echo "$info" | jq -r '.spec.template.spec.containers[0].args | join(" ")' 2>/dev/null)

    # Extract current context size from args
    local current_ctx=$(echo "$current_args" | grep -oP '(?<=--ctx-size )\d+' || echo "$DEFAULT_CTX_SIZE")

    echo ""
    echo -e "${BOLD}Current settings for '${model_name}':${NC}"
    echo ""
    echo "  Replicas:     $current_replicas"
    echo "  GPU enabled:  $([ "$current_gpu" != "0" ] && echo "yes" || echo "no")"
    echo "  Context size: $current_ctx"
    echo ""

    echo -e "${BOLD}What would you like to modify?${NC}"
    echo ""
    echo "  1) Replicas"
    echo "  2) GPU mode (enable/disable)"
    echo "  3) Context size"
    echo "  4) All settings"
    echo ""

    prompt_input "Select option" "" option

    case $option in
        1)
            prompt_input "New replica count" "$current_replicas" new_replicas
            log STEP "Updating replicas..."
            kubectl scale deployment "$model_name" -n "$NAMESPACE" --replicas="$new_replicas"
            log INFO "Replicas updated to $new_replicas"
            ;;
        2)
            local current_mode=$([ "$current_gpu" != "0" ] && [ "$current_gpu" != "null" ] && echo "GPU" || echo "CPU")
            echo ""
            echo "Current mode: $current_mode"
            echo ""
            echo "  1) GPU mode (uses nvidia.com/gpu)"
            echo "  2) CPU mode (no GPU allocation)"
            echo ""
            prompt_input "Select mode" "" mode_option

            if [ "$mode_option" = "1" ]; then
                # Check if already in GPU mode
                if [ "$current_mode" = "GPU" ]; then
                    log INFO "Model is already in GPU mode"
                else
                    # Find running GPU model (excluding this one)
                    local running_gpu_model=""
                    local deployments=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
                    for deployment in $deployments; do
                        if [ "$deployment" != "$model_name" ]; then
                            local dep_replicas=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
                            if [ "$dep_replicas" != "0" ]; then
                                local dep_gpu=$(kubectl get deployment "$deployment" -n "$NAMESPACE" -o json 2>/dev/null | \
                                    jq -r '.spec.template.spec.containers[0].resources.limits["nvidia.com/gpu"] // "0"')
                                if [ "$dep_gpu" != "0" ] && [ "$dep_gpu" != "null" ]; then
                                    running_gpu_model="$deployment"
                                    break
                                fi
                            fi
                        fi
                    done

                    if [ -n "$running_gpu_model" ]; then
                        log WARN "GPU is already in use by: $running_gpu_model"
                        echo ""
                        echo "Options:"
                        echo "  1) Switch '$running_gpu_model' to CPU, then enable GPU for '$model_name'"
                        echo "  2) Cancel"
                        echo ""
                        prompt_input "Select option" "2" gpu_choice

                        if [ "$gpu_choice" = "1" ]; then
                            log STEP "Switching '$running_gpu_model' to CPU mode..."
                            kubectl patch deployment "$running_gpu_model" -n "$NAMESPACE" --type='json' -p='[
                                {"op": "remove", "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu"},
                                {"op": "remove", "path": "/spec/template/spec/containers/0/resources/requests/nvidia.com~1gpu"}
                            ]' 2>/dev/null || true
                            log INFO "'$running_gpu_model' switched to CPU mode"

                            log STEP "Enabling GPU mode for '$model_name'..."
                            kubectl patch deployment "$model_name" -n "$NAMESPACE" --type='json' -p='[
                                {"op": "add", "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu", "value": "1"},
                                {"op": "add", "path": "/spec/template/spec/containers/0/resources/requests/nvidia.com~1gpu", "value": "1"}
                            ]' 2>/dev/null || log WARN "GPU resources may already be configured"
                            log INFO "GPU mode enabled for '$model_name'"
                        else
                            log INFO "Cancelled"
                        fi
                    else
                        log STEP "Enabling GPU mode..."
                        kubectl patch deployment "$model_name" -n "$NAMESPACE" --type='json' -p='[
                            {"op": "add", "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu", "value": "1"},
                            {"op": "add", "path": "/spec/template/spec/containers/0/resources/requests/nvidia.com~1gpu", "value": "1"}
                        ]' 2>/dev/null || log WARN "GPU resources may already be configured"
                        log INFO "GPU mode enabled"
                    fi
                fi
            else
                log STEP "Disabling GPU mode..."
                kubectl patch deployment "$model_name" -n "$NAMESPACE" --type='json' -p='[
                    {"op": "remove", "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu"},
                    {"op": "remove", "path": "/spec/template/spec/containers/0/resources/requests/nvidia.com~1gpu"}
                ]' 2>/dev/null || log WARN "GPU resources may not be configured"
                log INFO "CPU mode enabled"
            fi
            ;;
        3)
            prompt_input "New context size" "$current_ctx" new_ctx
            log STEP "Updating context size..."

            # Get current args and update context size
            local new_args=$(echo "$info" | jq -r --arg ctx "$new_ctx" '
                .spec.template.spec.containers[0].args |
                to_entries |
                map(
                    if .value == "--ctx-size" then
                        .
                    elif (.key > 0) and (.[.key - 1].value == "--ctx-size") then
                        .value = $ctx | .
                    else
                        .
                    end
                ) |
                from_entries | values
            ')

            # This is complex, so let's use kubectl edit approach
            log WARN "Context size changes require redeployment"
            if prompt_yes_no "Redeploy with new context size $new_ctx?"; then
                # Find the manifest file
                local manifest_file="${SCRIPT_DIR}/setup-llama-k8s/manifests/models/${model_name}-deployment.yaml"
                if [ -f "$manifest_file" ]; then
                    sed -i "s/--ctx-size.*/--ctx-size\n            - \"$new_ctx\"/" "$manifest_file" 2>/dev/null || true
                    kubectl apply -f "$manifest_file"
                    log INFO "Context size updated to $new_ctx"
                else
                    log ERROR "Manifest file not found. Please reinstall the model."
                fi
            fi
            ;;
        4)
            prompt_input "New replica count" "$current_replicas" new_replicas
            echo ""
            echo "GPU mode:"
            echo "  1) GPU"
            echo "  2) CPU"
            prompt_input "Select mode" "$([ "$current_gpu" != "0" ] && echo "1" || echo "2")" mode_option
            prompt_input "New context size" "$current_ctx" new_ctx

            log STEP "Applying all changes..."

            # Update replicas
            kubectl scale deployment "$model_name" -n "$NAMESPACE" --replicas="$new_replicas"

            # GPU mode
            if [ "$mode_option" = "1" ]; then
                kubectl patch deployment "$model_name" -n "$NAMESPACE" --type='json' -p='[
                    {"op": "add", "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu", "value": "1"},
                    {"op": "add", "path": "/spec/template/spec/containers/0/resources/requests/nvidia.com~1gpu", "value": "1"}
                ]' 2>/dev/null || true
            else
                kubectl patch deployment "$model_name" -n "$NAMESPACE" --type='json' -p='[
                    {"op": "remove", "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu"},
                    {"op": "remove", "path": "/spec/template/spec/containers/0/resources/requests/nvidia.com~1gpu"}
                ]' 2>/dev/null || true
            fi

            log INFO "Settings updated"
            ;;
        *)
            log ERROR "Invalid option"
            return 1
            ;;
    esac

    echo ""
    log INFO "Done!"
}

# ============================================================================
# USAGE
# ============================================================================
usage() {
    echo -e "${BOLD}LLM Model Manager for Kubernetes${NC}"
    echo ""
    echo "Usage: $0 COMMAND [OPTIONS]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  list                    Show deployed models and their status"
    echo "  available               Show models available locally in MODELS_DIR"
    echo "  download [name|url]     Browse/download models from HuggingFace"
    echo "  install [model.gguf]    Install a model to Kubernetes"
    echo "  activate [name]         Start a model (auto-manages GPU allocation)"
    echo "  stop [name]             Stop a running model"
    echo "  uninstall [name]        Remove model from Kubernetes (keeps files)"
    echo "  configure               Set download directory for models"
    echo "  modify [name]           Change model settings (replicas, GPU, context)"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 list"
    echo "  $0 download                         # Show available models"
    echo "  $0 download qwen2.5-coder-14b-q4    # Download specific model"
    echo "  $0 install                          # Interactive install"
    echo "  $0 activate my-model                # Activate a model"
    echo "  $0 modify                           # Interactive settings"
    echo ""
    echo -e "${BOLD}Configuration:${NC}"
    echo "  Config file: $CONFIG_FILE"
    echo "  Models dir:  $(load_config; echo $MODELS_DIR)"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    local command=${1:-help}
    shift 2>/dev/null || true

    case $command in
        list)
            cmd_list "$@"
            ;;
        available)
            cmd_available "$@"
            ;;
        download)
            cmd_download "$@"
            ;;
        install)
            cmd_install "$@"
            ;;
        activate)
            cmd_activate "$@"
            ;;
        stop)
            cmd_stop "$@"
            ;;
        uninstall)
            cmd_uninstall "$@"
            ;;
        configure)
            cmd_configure "$@"
            ;;
        modify)
            cmd_modify "$@"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log ERROR "Unknown command: $command"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
