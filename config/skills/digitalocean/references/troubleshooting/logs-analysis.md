# Logs Analysis

When shell access isn't available or the app is crashing.

## Fetch Logs

```bash
# Runtime logs
doctl apps logs <app_id> <component> --type run

# Follow in real-time
doctl apps logs <app_id> <component> --type run --follow

# Build logs
doctl apps logs <app_id> <component> --type build

# Deploy logs
doctl apps logs <app_id> <component> --type deploy

# Crash logs
doctl apps logs <app_id> --type=run_restarted
doctl apps logs <app_id> <component> --type=run_restarted
```

## Log Pattern Analysis

| Pattern | Likely Cause | Investigation |
|---------|--------------|---------------|
| `bind: address already in use` | Port conflict | Check if app uses PORT env var |
| `ECONNREFUSED 127.0.0.1:5432` | Database not attached | Check DATABASE_URL env |
| `Module not found` | Missing dependency | Check requirements.txt/package.json |
| `Permission denied` | File permissions | Check ownership/chmod |
| `OOMKilled` / exit 137 | Out of memory | Upgrade instance size |
| `Health check failed` | /health returns non-200 | Test health endpoint locally |
| `SIGTERM` / exit 143 | Graceful shutdown | Normal during redeploy |
| `EACCES` | Network permission | localhost vs 0.0.0.0 |
| `SSL SYSCALL error` | DB SSL config | Check sslmode in connection |
| `ETIMEOUT` | Network/DNS timeout | Check VPC configuration |

## Error Codes

### Build Errors

| Error | Cause | Fix |
|-------|-------|-----|
| BuildJobFailed | Build script failed | Check build logs |
| BuildJobExitNonZero | Build command error | Fix dependencies |
| BuildJobTimeout | Build > 60 min | Optimize or split |
| BuildJobOutOfMemory | Build OOM | Reduce dependencies |

### Container Exit Codes

| Code | Signal | Meaning | Action |
|------|--------|---------|--------|
| 0 | - | Clean exit | Check if app should stay running |
| 1 | - | General error | Check logs for exception |
| 2 | - | Shell misuse | Check entrypoint syntax |
| 126 | - | Not executable | chmod +x |
| 127 | - | Command not found | Missing dependency/PATH |
| 134 | SIGABRT | Abort/crash | Check error handling |
| 137 | SIGKILL | OOM killed | Increase memory |
| 139 | SIGSEGV | Segfault | Debug memory access |
| 143 | SIGTERM | Graceful shutdown | Normal during redeploy |
| 217 | - | Python fatal | Check Python logs |
| 255 | - | Unknown | Check logs for exception |

### Deploy Errors

| Error | Cause | Fix |
|-------|-------|-----|
| ContainerCommandNotExecutable | Run command missing | Clear custom run command |
| ContainerExitNonZero | App crashed on start | Fix startup code |
| ContainerHealthChecksFailed | Health endpoint failed | Verify /health returns 200 |
| ContainerOutOfMemory | App OOM on startup | Increase instance size |

## Health Check Debugging

### Configuration

```yaml
health_check:
  http_path: /health
  port: 8080
  initial_delay_seconds: 30  # Delay before first check
  period_seconds: 10
  timeout_seconds: 5
  success_threshold: 1
  failure_threshold: 5

liveness_health_check:
  http_path: /health
  port: 8080
  initial_delay_seconds: 10
  period_seconds: 10
  failure_threshold: 6
```

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| Connection refused | Binding to localhost | Bind to 0.0.0.0 |
| 503 during deploy | Slow startup | Increase initial_delay_seconds |
| Non-200 response | Endpoint error | Ensure /health returns 200 |
| Wrong port | Port mismatch | Use $PORT env var |

### Diagnosis

```python
# Check PORT
result = app.exec("echo $PORT")

# Check listening address
result = app.exec("ss -tlnp | grep ':8080'")
# Should show: 0.0.0.0:8080, NOT 127.0.0.1:8080

# Test endpoint
result = app.exec("curl -v localhost:8080/health")
```
