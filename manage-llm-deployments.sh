#!/bin/bash

# llama.cpp Kubernetes Deployment Management Script
# Manages switching between coding and chat models on shared GPU

set -e

NAMESPACE="llm-inference"
CODING_DEPLOY="qwen-coder-14b"
CHAT_DEPLOY="qwen-chat-14b"
NODE_IP="172.22.22.57"
CODING_PORT="30080"
CHAT_PORT="30081"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_error "Namespace $NAMESPACE does not exist. Please deploy the manifests first."
        exit 1
    fi
}

get_deployment_status() {
    local deploy=$1
    kubectl get deployment -n "$NAMESPACE" "$deploy" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0"
}

wait_for_ready() {
    local deploy=$1
    local timeout=120
    log_info "Waiting for $deploy to be ready..."

    if ! kubectl wait --for=condition=available --timeout=${timeout}s \
        -n "$NAMESPACE" deployment/"$deploy" 2>/dev/null; then
        log_error "Deployment $deploy did not become ready in ${timeout}s"
        return 1
    fi

    log_info "$deploy is ready!"
    return 0
}

# Command functions
cmd_deploy() {
    log_info "Deploying llama.cpp services to Kubernetes..."

    if [ ! -f "kubernetes-manifests.yaml" ]; then
        log_error "kubernetes-manifests.yaml not found in current directory"
        exit 1
    fi

    kubectl apply -f kubernetes-manifests.yaml
    log_info "Deployment complete!"
    log_info "Use './manage-llm-deployments.sh status' to check deployment status"
}

cmd_status() {
    check_namespace

    log_info "Checking deployment status..."
    echo ""
    kubectl get all -n "$NAMESPACE"
    echo ""

    local coding_replicas=$(get_deployment_status "$CODING_DEPLOY")
    local chat_replicas=$(get_deployment_status "$CHAT_DEPLOY")

    log_info "Current state:"
    echo "  Coding model ($CODING_DEPLOY): $coding_replicas replicas"
    echo "  Chat model ($CHAT_DEPLOY): $chat_replicas replicas"
    echo ""

    if [ "$coding_replicas" -gt 0 ]; then
        echo "  Coding model API: http://$NODE_IP:$CODING_PORT"
        echo "  Health check: curl http://$NODE_IP:$CODING_PORT/health"
    fi

    if [ "$chat_replicas" -gt 0 ]; then
        echo "  Chat model API: http://$NODE_IP:$CHAT_PORT"
        echo "  Health check: curl http://$NODE_IP:$CHAT_PORT/health"
    fi
}

cmd_use_coding() {
    check_namespace

    log_info "Switching to coding model (Qwen2.5-Coder-14B)..."
    log_warn "This will scale down the chat model to free GPU resources"

    # Scale down chat model first
    kubectl scale deployment -n "$NAMESPACE" "$CHAT_DEPLOY" --replicas=0
    log_info "Chat model scaled down"

    # Scale up coding model
    kubectl scale deployment -n "$NAMESPACE" "$CODING_DEPLOY" --replicas=1

    if wait_for_ready "$CODING_DEPLOY"; then
        log_info "Coding model is now active!"
        echo ""
        echo "API endpoint: http://$NODE_IP:$CODING_PORT"
        echo "Test with: curl http://$NODE_IP:$CODING_PORT/health"
    fi
}

cmd_use_chat() {
    check_namespace

    log_info "Switching to chat model (Qwen2.5-14B-Instruct)..."
    log_warn "This will scale down the coding model to free GPU resources"

    # Scale down coding model first
    kubectl scale deployment -n "$NAMESPACE" "$CODING_DEPLOY" --replicas=0
    log_info "Coding model scaled down"

    # Scale up chat model
    kubectl scale deployment -n "$NAMESPACE" "$CHAT_DEPLOY" --replicas=1

    if wait_for_ready "$CHAT_DEPLOY"; then
        log_info "Chat model is now active!"
        echo ""
        echo "API endpoint: http://$NODE_IP:$CHAT_PORT"
        echo "Test with: curl http://$NODE_IP:$CHAT_PORT/health"
    fi
}

cmd_use_both() {
    check_namespace

    log_warn "Running both models simultaneously with hybrid GPU/RAM configuration"
    log_warn "The chat model will run with reduced GPU layers (slower performance)"
    echo ""
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        exit 0
    fi

    log_info "Scaling up both deployments..."
    kubectl scale deployment -n "$NAMESPACE" "$CODING_DEPLOY" --replicas=1
    kubectl scale deployment -n "$NAMESPACE" "$CHAT_DEPLOY" --replicas=1

    log_info "Waiting for deployments to be ready..."
    wait_for_ready "$CODING_DEPLOY" &
    local coding_pid=$!
    wait_for_ready "$CHAT_DEPLOY" &
    local chat_pid=$!

    wait $coding_pid
    wait $chat_pid

    log_info "Both models are now active!"
    echo ""
    echo "Coding model API: http://$NODE_IP:$CODING_PORT"
    echo "Chat model API: http://$NODE_IP:$CHAT_PORT"
}

cmd_stop_all() {
    check_namespace

    log_info "Stopping all models..."
    kubectl scale deployment -n "$NAMESPACE" "$CODING_DEPLOY" --replicas=0
    kubectl scale deployment -n "$NAMESPACE" "$CHAT_DEPLOY" --replicas=0
    log_info "All models stopped"
}

cmd_logs() {
    check_namespace

    local model=${1:-coding}
    local deploy=""

    case "$model" in
        coding|coder)
            deploy="$CODING_DEPLOY"
            ;;
        chat)
            deploy="$CHAT_DEPLOY"
            ;;
        *)
            log_error "Unknown model: $model. Use 'coding' or 'chat'"
            exit 1
            ;;
    esac

    log_info "Showing logs for $deploy..."
    kubectl logs -n "$NAMESPACE" -l "app=$deploy" --tail=100 -f
}

cmd_gpu_status() {
    check_namespace

    log_info "Checking GPU usage..."

    # Try to get GPU stats from running pods
    local coding_pod=$(kubectl get pod -n "$NAMESPACE" -l "app=$CODING_DEPLOY" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    local chat_pod=$(kubectl get pod -n "$NAMESPACE" -l "app=$CHAT_DEPLOY" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -n "$coding_pod" ]; then
        echo ""
        log_info "GPU usage from coding pod:"
        kubectl exec -n "$NAMESPACE" "$coding_pod" -- nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv
    fi

    if [ -n "$chat_pod" ]; then
        echo ""
        log_info "GPU usage from chat pod:"
        kubectl exec -n "$NAMESPACE" "$chat_pod" -- nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv
    fi

    if [ -z "$coding_pod" ] && [ -z "$chat_pod" ]; then
        log_warn "No running pods found. GPU is idle."
    fi
}

cmd_test() {
    check_namespace

    local model=${1:-coding}
    local port=""
    local model_name=""
    local prompt=""

    case "$model" in
        coding|coder)
            port="$CODING_PORT"
            model_name="qwen2.5-coder-14b"
            prompt="Write a Python function to calculate fibonacci numbers"
            ;;
        chat)
            port="$CHAT_PORT"
            model_name="qwen2.5-14b"
            prompt="Hello! Tell me a short joke."
            ;;
        *)
            log_error "Unknown model: $model. Use 'coding' or 'chat'"
            exit 1
            ;;
    esac

    log_info "Testing $model model..."

    # Health check first
    if ! curl -s -f "http://$NODE_IP:$port/health" > /dev/null; then
        log_error "Health check failed. Is the model running?"
        exit 1
    fi

    log_info "Health check passed. Sending test prompt..."

    curl -s "http://$NODE_IP:$port/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$model_name\",
            \"messages\": [{\"role\": \"user\", \"content\": \"$prompt\"}],
            \"max_tokens\": 200,
            \"temperature\": 0.7
        }" | jq -r '.choices[0].message.content' || log_error "Test failed"
}

cmd_delete() {
    log_warn "This will delete all llama.cpp deployments and resources"
    echo ""
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cancelled"
        exit 0
    fi

    log_info "Deleting resources..."
    kubectl delete -f kubernetes-manifests.yaml
    log_info "All resources deleted"
}

# Main command dispatcher
case "${1:-help}" in
    deploy)
        cmd_deploy
        ;;
    status)
        cmd_status
        ;;
    use-coding|coding)
        cmd_use_coding
        ;;
    use-chat|chat)
        cmd_use_chat
        ;;
    use-both|both)
        cmd_use_both
        ;;
    stop|stop-all)
        cmd_stop_all
        ;;
    logs)
        cmd_logs "${2:-coding}"
        ;;
    gpu)
        cmd_gpu_status
        ;;
    test)
        cmd_test "${2:-coding}"
        ;;
    delete)
        cmd_delete
        ;;
    help|--help|-h|*)
        cat << EOF
llama.cpp Kubernetes Deployment Management Script

Usage: $0 <command> [options]

Commands:
    deploy          Deploy llama.cpp services to Kubernetes
    status          Show current deployment status
    use-coding      Switch to coding model (scales down chat model)
    use-chat        Switch to chat model (scales down coding model)
    use-both        Run both models simultaneously (hybrid mode)
    stop            Stop all models
    logs [MODEL]    Show logs (MODEL: coding or chat, default: coding)
    gpu             Show GPU usage statistics
    test [MODEL]    Test model with sample prompt (MODEL: coding or chat)
    delete          Delete all deployments and resources
    help            Show this help message

Examples:
    $0 deploy                 # Initial deployment
    $0 use-coding            # Switch to coding model
    $0 logs chat             # View chat model logs
    $0 test coding           # Test coding model with sample prompt
    $0 gpu                   # Check GPU usage

Service Endpoints:
    Coding Model: http://$NODE_IP:$CODING_PORT
    Chat Model:   http://$NODE_IP:$CHAT_PORT

For detailed documentation, see: DEPLOYMENT-GUIDE.md
EOF
        ;;
esac
