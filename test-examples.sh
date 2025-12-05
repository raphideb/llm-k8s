#!/bin/bash

# Example API test scripts for llama.cpp Kubernetes deployment
# Usage: ./test-examples.sh <command>

NODE_IP="172.22.22.57"
CODING_PORT="30080"
CHAT_PORT="30081"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Test 1: Health Check
test_health_coding() {
    log_test "Testing coding model health endpoint..."
    curl -s http://$NODE_IP:$CODING_PORT/health | jq .
}

test_health_chat() {
    log_test "Testing chat model health endpoint..."
    curl -s http://$NODE_IP:$CHAT_PORT/health | jq .
}

# Test 2: List Models
test_list_models_coding() {
    log_test "Listing available models (coding)..."
    curl -s http://$NODE_IP:$CODING_PORT/v1/models | jq .
}

test_list_models_chat() {
    log_test "Listing available models (chat)..."
    curl -s http://$NODE_IP:$CHAT_PORT/v1/models | jq .
}

# Test 3: Simple Completion (Coding)
test_coding_simple() {
    log_test "Testing coding model with simple Python function request..."
    curl -s http://$NODE_IP:$CODING_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{
            "model": "qwen2.5-coder-14b",
            "messages": [
                {"role": "system", "content": "You are a helpful coding assistant."},
                {"role": "user", "content": "Write a Python function to reverse a string"}
            ],
            "max_tokens": 500,
            "temperature": 0.7
        }' | jq -r '.choices[0].message.content'
}

# Test 4: Code Explanation (Coding)
test_coding_explain() {
    log_test "Testing coding model with code explanation request..."
    curl -s http://$NODE_IP:$CODING_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{
            "model": "qwen2.5-coder-14b",
            "messages": [
                {"role": "user", "content": "Explain what async/await does in Python with a simple example"}
            ],
            "max_tokens": 800,
            "temperature": 0.5
        }' | jq -r '.choices[0].message.content'
}

# Test 5: Chat Conversation (Chat)
test_chat_simple() {
    log_test "Testing chat model with simple conversation..."
    curl -s http://$NODE_IP:$CHAT_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{
            "model": "qwen2.5-14b",
            "messages": [
                {"role": "user", "content": "Hello! Can you tell me a short joke about programming?"}
            ],
            "max_tokens": 200,
            "temperature": 0.8
        }' | jq -r '.choices[0].message.content'
}

# Test 6: Multi-turn Conversation (Chat)
test_chat_multiturn() {
    log_test "Testing chat model with multi-turn conversation..."
    curl -s http://$NODE_IP:$CHAT_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{
            "model": "qwen2.5-14b",
            "messages": [
                {"role": "user", "content": "What is the capital of France?"},
                {"role": "assistant", "content": "The capital of France is Paris."},
                {"role": "user", "content": "What is the population of that city?"}
            ],
            "max_tokens": 200,
            "temperature": 0.7
        }' | jq -r '.choices[0].message.content'
}

# Test 7: Streaming Response (Coding)
test_coding_stream() {
    log_test "Testing coding model with streaming response..."
    log_info "Streaming output (press Ctrl+C to stop):"
    curl -s http://$NODE_IP:$CODING_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{
            "model": "qwen2.5-coder-14b",
            "messages": [
                {"role": "user", "content": "Write a Python class for a simple calculator"}
            ],
            "max_tokens": 1000,
            "stream": true,
            "temperature": 0.7
        }'
}

# Test 8: Large Context (Coding)
test_coding_large_context() {
    log_test "Testing coding model with larger context (code review)..."
    curl -s http://$NODE_IP:$CODING_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{
            "model": "qwen2.5-coder-14b",
            "messages": [
                {"role": "user", "content": "Review this Python code and suggest improvements:\n\ndef calculate(x, y, op):\n    if op == \"+\":\n        return x + y\n    elif op == \"-\":\n        return x - y\n    elif op == \"*\":\n        return x * y\n    elif op == \"/\":\n        return x / y\n    else:\n        return None"}
            ],
            "max_tokens": 800,
            "temperature": 0.5
        }' | jq -r '.choices[0].message.content'
}

# Test 9: Performance Test (measure tokens/sec)
test_performance_coding() {
    log_test "Performance test (coding model)..."
    log_info "Generating 500 tokens and measuring time..."

    START=$(date +%s.%N)

    RESPONSE=$(curl -s http://$NODE_IP:$CODING_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{
            "model": "qwen2.5-coder-14b",
            "messages": [
                {"role": "user", "content": "Write a detailed Python script that implements a REST API server using Flask with authentication, database integration, and error handling"}
            ],
            "max_tokens": 500,
            "temperature": 0.7
        }')

    END=$(date +%s.%N)

    DURATION=$(echo "$END - $START" | bc)
    TOKENS=$(echo "$RESPONSE" | jq '.usage.completion_tokens // 0')
    TOKENS_PER_SEC=$(echo "scale=2; $TOKENS / $DURATION" | bc)

    echo ""
    log_info "Performance Results:"
    echo "  Duration: ${DURATION}s"
    echo "  Tokens Generated: $TOKENS"
    echo "  Speed: ${TOKENS_PER_SEC} tokens/sec"
    echo ""
}

# Test 10: Error Handling
test_error_handling() {
    log_test "Testing error handling with invalid request..."
    curl -s http://$NODE_IP:$CODING_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{
            "model": "invalid-model",
            "messages": [{"role": "user", "content": "test"}]
        }' | jq .
}

# Test 11: Context Window Stress Test (32K tokens)
test_large_context_window() {
    log_test "Testing large context window (coding model)..."
    log_warn "This test uses a large prompt to test 32K context handling"

    # Generate a large code file in prompt
    LARGE_CODE=$(printf 'def function_%d():\n    pass\n\n' {1..500})

    curl -s http://$NODE_IP:$CODING_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"qwen2.5-coder-14b\",
            \"messages\": [
                {\"role\": \"user\", \"content\": \"Analyze this code and provide a summary:\n\n$LARGE_CODE\"}
            ],
            \"max_tokens\": 300,
            \"temperature\": 0.5
        }" | jq -r '.choices[0].message.content'
}

# Test 12: JSON Mode (Structured Output)
test_json_mode() {
    log_test "Testing structured JSON output..."
    curl -s http://$NODE_IP:$CODING_PORT/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{
            "model": "qwen2.5-coder-14b",
            "messages": [
                {"role": "user", "content": "Generate a JSON object with 3 popular programming languages and their primary use cases"}
            ],
            "max_tokens": 300,
            "temperature": 0.5
        }' | jq -r '.choices[0].message.content'
}

# Test 13: Metrics Endpoint
test_metrics() {
    log_test "Testing Prometheus metrics endpoint..."
    curl -s http://$NODE_IP:$CODING_PORT/metrics | grep -E "^(llama_|http_)"
}

# All Tests Suite
run_all_tests() {
    log_info "Running comprehensive test suite..."
    echo ""

    test_health_coding
    echo ""
    sleep 1

    test_list_models_coding
    echo ""
    sleep 1

    test_coding_simple
    echo ""
    sleep 2

    test_coding_explain
    echo ""
    sleep 2

    test_chat_simple
    echo ""
    sleep 2

    log_info "All quick tests completed!"
    log_info "Run './test-examples.sh performance' for performance tests"
}

# Main command dispatcher
case "${1:-help}" in
    health-coding)
        test_health_coding
        ;;
    health-chat)
        test_health_chat
        ;;
    models-coding)
        test_list_models_coding
        ;;
    models-chat)
        test_list_models_chat
        ;;
    simple-coding)
        test_coding_simple
        ;;
    explain-coding)
        test_coding_explain
        ;;
    simple-chat)
        test_chat_simple
        ;;
    multiturn-chat)
        test_chat_multiturn
        ;;
    stream-coding)
        test_coding_stream
        ;;
    review-coding)
        test_coding_large_context
        ;;
    performance)
        test_performance_coding
        ;;
    error)
        test_error_handling
        ;;
    large-context)
        test_large_context_window
        ;;
    json)
        test_json_mode
        ;;
    metrics)
        test_metrics
        ;;
    all)
        run_all_tests
        ;;
    help|--help|-h|*)
        cat << EOF
llama.cpp API Test Examples

Usage: $0 <test-name>

Health & Info Tests:
    health-coding       Test coding model health endpoint
    health-chat         Test chat model health endpoint
    models-coding       List available models (coding)
    models-chat         List available models (chat)
    metrics             Show Prometheus metrics

Coding Model Tests:
    simple-coding       Simple Python function request
    explain-coding      Code explanation with example
    review-coding       Code review with suggestions
    stream-coding       Streaming response test
    json                Structured JSON output test

Chat Model Tests:
    simple-chat         Simple conversation
    multiturn-chat      Multi-turn conversation

Performance Tests:
    performance         Measure tokens/sec generation speed
    large-context       Test 32K context window handling

Error Tests:
    error               Test error handling

Test Suites:
    all                 Run all quick tests (excludes performance)

Examples:
    $0 simple-coding    # Test coding model with simple request
    $0 performance      # Run performance benchmark
    $0 all              # Run all quick tests

Requirements:
    - jq (JSON processor): sudo apt install jq
    - bc (calculator): sudo apt install bc
    - curl: sudo apt install curl

Note: Make sure the appropriate model is running before testing.
      Use './manage-llm-deployments.sh use-coding' or 'use-chat' first.
EOF
        ;;
esac
