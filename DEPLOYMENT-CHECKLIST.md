# llama.cpp Kubernetes Deployment Checklist

Use this checklist to ensure a successful deployment of your llama.cpp models on Kubernetes.

## Pre-Deployment Checklist

### Hardware Verification

- [ ] NVIDIA RTX 5080 GPU is installed and detected
- [ ] 16GB VRAM available on GPU
- [ ] 64GB system RAM available
- [ ] Sufficient disk space (minimum 30GB free)

**Verify GPU:**

```bash
nvidia-smi
# Should show: RTX 5080, 16GB VRAM
```

### Kubernetes Setup

- [ ] Kubernetes cluster is running
- [ ] kubectl is installed and configured
- [ ] NVIDIA GPU device plugin is installed
- [ ] NVIDIA Container Toolkit is configured
- [ ] Node can schedule GPU workloads

**Verify GPU in Kubernetes:**

```bash
kubectl run gpu-test --image=nvidia/cuda:12.8.0-base-ubuntu20.04 --rm -it --restart=Never -- nvidia-smi
```

Expected output: Should show GPU information from inside container

### Model Files

- [ ] Qwen2.5-Coder-14B-Instruct-Q4_K_M.gguf downloaded (8.4GB)
- [ ] Qwen2.5-14B-Instruct-Q4_K_M.gguf downloaded (8.4GB)
- [ ] Models located at /home/raphi/git/models/
- [ ] Models are readable (not corrupted)

**Verify models:**

```bash
ls -lh /home/raphi/git/models/
# Should show both .gguf files, ~8.4GB each
```

### Storage Configuration

- [ ] local-path storage class exists
- [ ] /home/raphi/git/models directory is accessible from all nodes
- [ ] Directory has proper permissions

**Verify storage class:**

```bash
kubectl get storageclass
# Should show: local-path
```

---

## Deployment Steps

### Step 1: Get GPU Node Hostname

```bash
kubectl get nodes -o wide
```

- [ ] Note the hostname of your GPU node
- [ ] Node has "Ready" status
- [ ] Node has GPU resources available

### Step 2: Update Manifests

Edit `kubernetes-manifests.yaml`:

- [ ] Replace `node-with-gpu` with your actual GPU node hostname (appears 2 times)
- [ ] Verify model paths in args section
- [ ] Verify NodePort values (30080, 30081) don't conflict

**Lines to update:**

```yaml
kubernetes.io/hostname: YOUR-ACTUAL-HOSTNAME  # Update this
```

### Step 3: Deploy Resources

```bash
./manage-llm-deployments.sh deploy
```

- [ ] Namespace created (llm-inference)
- [ ] PersistentVolume created
- [ ] PersistentVolumeClaim bound
- [ ] Deployments created (qwen-coder-14b, qwen-chat-14b)
- [ ] Services created (NodePort 30080, 30081)
- [ ] No errors in output

**Verify:**

```bash
kubectl get all -n llm-inference
```

### Step 4: Check Pod Status

```bash
kubectl get pods -n llm-inference -w
```

- [ ] Pods are in "Running" state (may take 1-2 minutes)
- [ ] No "ImagePullBackOff" errors
- [ ] No "CrashLoopBackOff" errors
- [ ] Readiness probes pass

**Check pod details if stuck:**

```bash
kubectl describe pod -n llm-inference -l app=qwen-coder-14b
```

### Step 5: Verify GPU Allocation

```bash
kubectl describe pod -n llm-inference -l app=qwen-coder-14b | grep -A 5 "Limits"
```

- [ ] nvidia.com/gpu: 1 shown in limits
- [ ] GPU allocated to pod
- [ ] No resource constraint errors

### Step 6: Check Logs

```bash
./manage-llm-deployments.sh logs coding
```

- [ ] Model loaded successfully
- [ ] No CUDA errors
- [ ] GPU layers offloaded (should show 48/48)
- [ ] Server listening on 0.0.0.0:8080
- [ ] Flash Attention enabled

**Look for these log messages:**

```
llm_load_tensors: offloaded 48/48 layers to GPU
system_info: n_gpu_layers = 48
flash_attn = 1
```

---

## Testing Checklist

### Health Check Tests

**Coding Model:**

```bash
curl http://172.22.22.57:30080/health
```

- [ ] Returns HTTP 200
- [ ] Response is valid JSON
- [ ] Status indicates healthy

**Chat Model:**

```bash
curl http://172.22.22.57:30081/health
```

- [ ] Returns HTTP 200
- [ ] Response is valid JSON
- [ ] Status indicates healthy

### API Tests

**List Models (Coding):**

```bash
curl http://172.22.22.57:30080/v1/models
```

- [ ] Returns list of available models
- [ ] Model ID is present

**Simple Completion:**

```bash
./manage-llm-deployments.sh test coding
```

- [ ] Returns valid response
- [ ] Response is relevant to prompt
- [ ] No timeout errors
- [ ] Generation speed seems reasonable (30-50 tokens/sec)

### Performance Tests

**Token Generation Speed:**

```bash
./test-examples.sh performance
```

- [ ] Completes without errors
- [ ] Speed is 30-50 tokens/sec (full GPU)
- [ ] No CUDA out of memory errors

**GPU Usage:**

```bash
./manage-llm-deployments.sh gpu
```

- [ ] Shows GPU memory usage
- [ ] VRAM usage is approximately 10-12GB for coding model
- [ ] No memory leaks over time

---

## Operational Checklist

### Model Switching

**Switch to Coding Model:**

```bash
./manage-llm-deployments.sh use-coding
```

- [ ] Chat model scales down to 0 replicas
- [ ] Coding model scales up to 1 replica
- [ ] Pod becomes ready within 60 seconds
- [ ] Health check passes

**Switch to Chat Model:**

```bash
./manage-llm-deployments.sh use-chat
```

- [ ] Coding model scales down to 0 replicas
- [ ] Chat model scales up to 1 replica
- [ ] Pod becomes ready within 60 seconds
- [ ] Health check passes

### Monitoring

**Check Status:**

```bash
./manage-llm-deployments.sh status
```

- [ ] Shows current replica counts
- [ ] Shows service endpoints
- [ ] Matches expected state

**View Metrics:**

```bash
curl http://172.22.22.57:30080/metrics
```

- [ ] Returns Prometheus metrics
- [ ] Includes llama_* metrics
- [ ] Includes http_* metrics

---

## Troubleshooting Checklist

### Issue: Pod Stuck in Pending

**Check:**

- [ ] GPU resources available: `kubectl describe node | grep nvidia.com/gpu`
- [ ] Pod events: `kubectl describe pod -n llm-inference`
- [ ] Storage bound: `kubectl get pvc -n llm-inference`

**Common Causes:**

- GPU already allocated to another pod
- Storage PVC not bound
- Node selector mismatch

### Issue: CUDA Out of Memory

**Check:**

- [ ] Only one model running: `kubectl get pods -n llm-inference`
- [ ] Context size not too large (check deployment args)
- [ ] GPU memory usage: `nvidia-smi`

**Solutions:**

- Reduce --ctx-size from 32768 to 16384
- Reduce --n-gpu-layers from 48 to 40
- Stop other GPU workloads

### Issue: Slow Inference

**Check:**

- [ ] All 48 layers on GPU: `kubectl logs ... | grep "offload"`
- [ ] Flash Attention enabled: `kubectl logs ... | grep "flash"`
- [ ] GPU utilization high: `nvidia-smi`

**Solutions:**

- Verify --n-gpu-layers 48 in deployment
- Ensure --flash-attn 1 is set
- Check for CPU throttling

### Issue: Connection Refused

**Check:**

- [ ] Service exists: `kubectl get svc -n llm-inference`
- [ ] Pod is ready: `kubectl get pods -n llm-inference`
- [ ] NodePort is correct (30080 or 30081)
- [ ] Firewall allows NodePort

**Solutions:**

- Port forward for debugging: `kubectl port-forward ...`
- Check node IP is correct (172.22.22.57)
- Verify NodePort range is allowed

---

## Performance Verification Checklist

### Expected Performance (Full GPU)

**Coding Model:**

- [ ] Prompt processing: 500-800 tokens/sec
- [ ] Text generation: 30-50 tokens/sec
- [ ] First token latency: <100ms
- [ ] VRAM usage: 10-13GB

**Chat Model:**

- [ ] Prompt processing: 500-800 tokens/sec
- [ ] Text generation: 30-50 tokens/sec
- [ ] First token latency: <100ms
- [ ] VRAM usage: 9-11GB

### Resource Utilization

- [ ] GPU utilization: 80-100% during generation
- [ ] VRAM usage: Stable (no leaks)
- [ ] CPU usage: Low (mostly idle)
- [ ] System RAM usage: <10GB per model

---

## Security Checklist

### Network Security

- [ ] NodePort services only accessible from trusted networks
- [ ] Consider using Ingress with authentication
- [ ] Rate limiting configured (if needed)
- [ ] TLS termination at ingress (if exposed externally)

### Resource Security

- [ ] Resource limits set (prevent resource exhaustion)
- [ ] Pod Security Standards applied
- [ ] Service account has minimal permissions
- [ ] Secrets used for sensitive data (if any)

### Model Security

- [ ] Model files have read-only access
- [ ] Models from trusted sources
- [ ] Model checksums verified
- [ ] Regular security updates applied

---

## Maintenance Checklist

### Daily

- [ ] Check pod health: `kubectl get pods -n llm-inference`
- [ ] Monitor VRAM usage: `nvidia-smi`
- [ ] Check for errors in logs

### Weekly

- [ ] Review Prometheus metrics
- [ ] Check for image updates: `docker pull ghcr.io/ggml-org/llama.cpp:server-cuda`
- [ ] Verify disk space: `df -h`
- [ ] Check Kubernetes node health

### Monthly

- [ ] Review and optimize context sizes
- [ ] Update llama.cpp container image
- [ ] Review resource requests/limits
- [ ] Clean up old logs

### Quarterly

- [ ] Evaluate new model versions (Qwen updates)
- [ ] Review and update Kubernetes manifests
- [ ] Performance benchmarking
- [ ] Disaster recovery test

---

## Rollback Checklist

### If Deployment Fails

**Immediate Actions:**

- [ ] Stop deployment: `./manage-llm-deployments.sh stop`
- [ ] Check logs: `kubectl logs -n llm-inference ...`
- [ ] Document error messages
- [ ] Capture pod state: `kubectl describe pod ...`

**Rollback Steps:**

- [ ] Delete failed deployment: `./manage-llm-deployments.sh delete`
- [ ] Verify resources cleaned up: `kubectl get all -n llm-inference`
- [ ] Revert to previous manifest version (if available)
- [ ] Redeploy: `./manage-llm-deployments.sh deploy`

**Post-Rollback:**

- [ ] Verify services are healthy
- [ ] Run test suite: `./test-examples.sh all`
- [ ] Investigate root cause
- [ ] Document lessons learned

---

## Production Readiness Checklist

### Before Going Live

**Infrastructure:**

- [ ] Redundant storage for models
- [ ] Backup strategy defined
- [ ] Monitoring alerts configured
- [ ] Log aggregation setup
- [ ] Disaster recovery plan documented

**Performance:**

- [ ] Load testing completed
- [ ] Latency requirements met
- [ ] Throughput requirements met
- [ ] Resource scaling strategy defined

**Operations:**

- [ ] Runbook created for common issues
- [ ] On-call rotation defined
- [ ] Escalation procedures documented
- [ ] SLA/SLO defined

**Security:**

- [ ] Security audit completed
- [ ] Access controls implemented
- [ ] Compliance requirements met
- [ ] Incident response plan ready

---

## Success Criteria

Your deployment is successful when:

- [ ] Both models can be deployed and scaled
- [ ] Health checks pass consistently
- [ ] API endpoints respond correctly
- [ ] Performance meets expectations (30-50 tokens/sec)
- [ ] GPU memory usage is stable (no leaks)
- [ ] Models can be switched without issues
- [ ] Logs show no errors or warnings
- [ ] Test suite passes completely
- [ ] Documentation is complete and accurate

**Congratulations! Your llama.cpp deployment is ready for use.**

---

## Next Steps

After successful deployment:

1. Integrate with your applications using the API endpoints
2. Set up monitoring and alerting
3. Create automated scaling policies (if needed)
4. Document your specific use cases
5. Train your team on operations

**For ongoing support, refer to:**

- DEPLOYMENT-GUIDE.md - Comprehensive documentation
- QUICK-REFERENCE.md - Common commands and examples
- README.md - Overview and quick start
- SUMMARY.md - Executive summary and key findings
