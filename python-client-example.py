#!/usr/bin/env python3
"""
Python client examples for llama.cpp Kubernetes deployment

This script demonstrates how to interact with the deployed models
using Python and the OpenAI-compatible API.

Requirements:
    pip install openai requests

Usage:
    python3 python-client-example.py
"""

import json
import time
from typing import Generator

try:
    from openai import OpenAI
    OPENAI_AVAILABLE = True
except ImportError:
    OPENAI_AVAILABLE = False
    print("OpenAI library not available. Install with: pip install openai")

import requests

# Configuration
NODE_IP = "172.22.22.57"
CODING_PORT = 30080
CHAT_PORT = 30081

CODING_BASE_URL = f"http://{NODE_IP}:{CODING_PORT}/v1"
CHAT_BASE_URL = f"http://{NODE_IP}:{CHAT_PORT}/v1"


def test_health(base_url: str) -> bool:
    """Test if the model server is healthy."""
    try:
        response = requests.get(base_url.replace("/v1", "/health"), timeout=5)
        return response.status_code == 200
    except Exception as e:
        print(f"Health check failed: {e}")
        return False


def list_models(base_url: str) -> None:
    """List available models."""
    try:
        response = requests.get(f"{base_url}/models", timeout=5)
        response.raise_for_status()
        models = response.json()
        print(json.dumps(models, indent=2))
    except Exception as e:
        print(f"Failed to list models: {e}")


def simple_completion_requests(base_url: str, prompt: str, model: str = "model") -> str:
    """Simple completion using requests library."""
    try:
        response = requests.post(
            f"{base_url}/chat/completions",
            headers={"Content-Type": "application/json"},
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": 500,
                "temperature": 0.7,
            },
            timeout=60,
        )
        response.raise_for_status()
        result = response.json()
        return result["choices"][0]["message"]["content"]
    except Exception as e:
        print(f"Completion failed: {e}")
        return ""


def streaming_completion_requests(base_url: str, prompt: str, model: str = "model") -> Generator:
    """Streaming completion using requests library."""
    try:
        response = requests.post(
            f"{base_url}/chat/completions",
            headers={"Content-Type": "application/json"},
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": 1000,
                "temperature": 0.7,
                "stream": True,
            },
            stream=True,
            timeout=120,
        )
        response.raise_for_status()

        for line in response.iter_lines():
            if line:
                line = line.decode("utf-8")
                if line.startswith("data: "):
                    data = line[6:]  # Remove "data: " prefix
                    if data.strip() == "[DONE]":
                        break
                    try:
                        chunk = json.loads(data)
                        if "choices" in chunk and len(chunk["choices"]) > 0:
                            delta = chunk["choices"][0].get("delta", {})
                            if "content" in delta:
                                yield delta["content"]
                    except json.JSONDecodeError:
                        continue
    except Exception as e:
        print(f"Streaming failed: {e}")


def simple_completion_openai(base_url: str, prompt: str, model: str = "model") -> str:
    """Simple completion using OpenAI library."""
    if not OPENAI_AVAILABLE:
        return "OpenAI library not available"

    try:
        client = OpenAI(base_url=base_url, api_key="dummy")  # API key not needed but required by library
        response = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=500,
            temperature=0.7,
        )
        return response.choices[0].message.content
    except Exception as e:
        print(f"OpenAI completion failed: {e}")
        return ""


def streaming_completion_openai(base_url: str, prompt: str, model: str = "model") -> Generator:
    """Streaming completion using OpenAI library."""
    if not OPENAI_AVAILABLE:
        yield "OpenAI library not available"
        return

    try:
        client = OpenAI(base_url=base_url, api_key="dummy")
        stream = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=1000,
            temperature=0.7,
            stream=True,
        )
        for chunk in stream:
            if chunk.choices[0].delta.content:
                yield chunk.choices[0].delta.content
    except Exception as e:
        print(f"OpenAI streaming failed: {e}")


def multi_turn_conversation(base_url: str, model: str = "model") -> None:
    """Multi-turn conversation example."""
    conversation = [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "What is the capital of France?"},
    ]

    print("User: What is the capital of France?")

    try:
        # First response
        response = requests.post(
            f"{base_url}/chat/completions",
            headers={"Content-Type": "application/json"},
            json={
                "model": model,
                "messages": conversation,
                "max_tokens": 200,
                "temperature": 0.7,
            },
            timeout=60,
        )
        response.raise_for_status()
        result = response.json()
        assistant_msg = result["choices"][0]["message"]["content"]
        print(f"Assistant: {assistant_msg}")

        # Add to conversation
        conversation.append({"role": "assistant", "content": assistant_msg})
        conversation.append({"role": "user", "content": "What is the population?"})
        print("\nUser: What is the population?")

        # Second response
        response = requests.post(
            f"{base_url}/chat/completions",
            headers={"Content-Type": "application/json"},
            json={
                "model": model,
                "messages": conversation,
                "max_tokens": 200,
                "temperature": 0.7,
            },
            timeout=60,
        )
        response.raise_for_status()
        result = response.json()
        assistant_msg = result["choices"][0]["message"]["content"]
        print(f"Assistant: {assistant_msg}")

    except Exception as e:
        print(f"Conversation failed: {e}")


def performance_test(base_url: str, model: str = "model") -> None:
    """Measure tokens per second."""
    prompt = "Write a detailed Python script that implements a REST API server using Flask with authentication, database integration, and error handling."

    print(f"Testing performance with {model}...")
    start_time = time.time()

    try:
        response = requests.post(
            f"{base_url}/chat/completions",
            headers={"Content-Type": "application/json"},
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": 500,
                "temperature": 0.7,
            },
            timeout=120,
        )
        response.raise_for_status()
        result = response.json()

        end_time = time.time()
        duration = end_time - start_time
        tokens = result.get("usage", {}).get("completion_tokens", 0)
        tokens_per_sec = tokens / duration if duration > 0 else 0

        print(f"\nPerformance Results:")
        print(f"  Duration: {duration:.2f}s")
        print(f"  Tokens Generated: {tokens}")
        print(f"  Speed: {tokens_per_sec:.2f} tokens/sec")
        print(f"  Total Tokens (prompt + completion): {result.get('usage', {}).get('total_tokens', 0)}")

    except Exception as e:
        print(f"Performance test failed: {e}")


def code_generation_example() -> None:
    """Example: Generate code with the coding model."""
    print("=" * 80)
    print("Example 1: Code Generation (Coding Model)")
    print("=" * 80)

    if not test_health(CODING_BASE_URL.replace("/v1", "")):
        print("Coding model is not available. Start it with:")
        print("  ./manage-llm-deployments.sh use-coding")
        return

    prompt = "Write a Python function to calculate the Fibonacci sequence using memoization"
    print(f"\nPrompt: {prompt}\n")

    response = simple_completion_requests(CODING_BASE_URL, prompt, "qwen2.5-coder-14b")
    print(f"Response:\n{response}\n")


def code_review_example() -> None:
    """Example: Code review with the coding model."""
    print("=" * 80)
    print("Example 2: Code Review (Coding Model)")
    print("=" * 80)

    if not test_health(CODING_BASE_URL.replace("/v1", "")):
        print("Coding model is not available.")
        return

    code = """
def divide(a, b):
    return a / b

result = divide(10, 0)
print(result)
"""

    prompt = f"Review this Python code and suggest improvements:\n{code}"
    print(f"\nPrompt: {prompt}\n")

    response = simple_completion_requests(CODING_BASE_URL, prompt, "qwen2.5-coder-14b")
    print(f"Response:\n{response}\n")


def chat_example() -> None:
    """Example: Simple chat with the chat model."""
    print("=" * 80)
    print("Example 3: Chat Conversation (Chat Model)")
    print("=" * 80)

    if not test_health(CHAT_BASE_URL.replace("/v1", "")):
        print("Chat model is not available. Start it with:")
        print("  ./manage-llm-deployments.sh use-chat")
        return

    prompt = "Explain the difference between machine learning and deep learning in simple terms"
    print(f"\nPrompt: {prompt}\n")

    response = simple_completion_requests(CHAT_BASE_URL, prompt, "qwen2.5-14b")
    print(f"Response:\n{response}\n")


def streaming_example() -> None:
    """Example: Streaming response."""
    print("=" * 80)
    print("Example 4: Streaming Response (Coding Model)")
    print("=" * 80)

    if not test_health(CODING_BASE_URL.replace("/v1", "")):
        print("Coding model is not available.")
        return

    prompt = "Write a Python class for a simple calculator with add, subtract, multiply, and divide methods"
    print(f"\nPrompt: {prompt}\n")
    print("Response (streaming):")

    for chunk in streaming_completion_requests(CODING_BASE_URL, prompt, "qwen2.5-coder-14b"):
        print(chunk, end="", flush=True)
    print("\n")


def openai_library_example() -> None:
    """Example: Using OpenAI library."""
    if not OPENAI_AVAILABLE:
        print("OpenAI library not available. Install with: pip install openai")
        return

    print("=" * 80)
    print("Example 5: Using OpenAI Library (Coding Model)")
    print("=" * 80)

    if not test_health(CODING_BASE_URL.replace("/v1", "")):
        print("Coding model is not available.")
        return

    prompt = "Write a Python decorator that measures function execution time"
    print(f"\nPrompt: {prompt}\n")

    response = simple_completion_openai(CODING_BASE_URL, prompt, "qwen2.5-coder-14b")
    print(f"Response:\n{response}\n")


def main():
    """Run all examples."""
    print("\nllama.cpp Kubernetes Deployment - Python Client Examples\n")

    # Check which models are available
    print("Checking model availability...")
    coding_available = test_health(CODING_BASE_URL.replace("/v1", ""))
    chat_available = test_health(CHAT_BASE_URL.replace("/v1", ""))

    print(f"  Coding Model (port {CODING_PORT}): {'✓ Available' if coding_available else '✗ Not available'}")
    print(f"  Chat Model (port {CHAT_PORT}): {'✓ Available' if chat_available else '✗ Not available'}")
    print()

    if not coding_available and not chat_available:
        print("No models are available. Start a model with:")
        print("  ./manage-llm-deployments.sh use-coding")
        print("  ./manage-llm-deployments.sh use-chat")
        return

    # Run examples
    try:
        if coding_available:
            code_generation_example()
            code_review_example()
            streaming_example()
            openai_library_example()

            print("=" * 80)
            print("Performance Test (Coding Model)")
            print("=" * 80)
            performance_test(CODING_BASE_URL, "qwen2.5-coder-14b")
            print()

        if chat_available:
            chat_example()

            print("=" * 80)
            print("Multi-turn Conversation (Chat Model)")
            print("=" * 80)
            multi_turn_conversation(CHAT_BASE_URL, "qwen2.5-14b")
            print()

    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
    except Exception as e:
        print(f"\nError running examples: {e}")

    print("\n" + "=" * 80)
    print("Examples completed!")
    print("=" * 80)


if __name__ == "__main__":
    main()
