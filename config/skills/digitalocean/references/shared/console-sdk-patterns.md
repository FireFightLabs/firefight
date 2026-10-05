# Console SDK for AI Assistants

**CRITICAL**: AI assistants cannot use `doctl apps console` — it opens an interactive WebSocket session that requires human input. Use the `do-app-sandbox` Python package instead for programmatic shell access.

## Installation

```bash
# Install with uv (recommended)
uv pip install do-app-sandbox

# Or with pip
pip install do-app-sandbox

# With Spaces support for large file transfers
pip install "do-app-sandbox[spaces]"
```

---

## Two Use Cases (Same Package, Different Skills)

The `do-app-sandbox` package serves two distinct purposes:

| Use Case | SDK Method | Skill | When to Use |
|----------|------------|-------|-------------|
| Debug EXISTING app | `Sandbox.get_from_id()` | **troubleshooting** | App deployed, something broken |
| Create NEW sandbox | `Sandbox.create()`, `SandboxManager` | **sandbox** | Need isolated execution environment |

**Important distinction:**
- `Sandbox.get_from_id()` connects to an app that already exists and is running
- `Sandbox.create()` provisions a new container from scratch (~30s cold start)
- `SandboxManager` maintains pre-warmed sandboxes for instant acquisition (~50ms)

---

## Troubleshooting Patterns (Debug Existing Apps)

### Connect to Any Running App Platform App

```python
# Get shell access to any component in an existing app
app = Sandbox.get_from_id(app_id="your-app-id", component="component-name")
result = app.exec("command-here")
print(result.stdout)
```

### Deploy and Connect to Debug Container

```python
# For troubleshooting: deploy the pre-built debug container
# Image: ghcr.io/bikramkgupta/do-app-debug-container-python:latest
# Then connect with Sandbox.get_from_id()
```

### Common Diagnostic Commands

```python
# Network diagnostics
app.exec("curl -I http://internal-service:8080/health")
app.exec("nc -zv db-host 5432")

# Environment inspection
app.exec("env | grep -E '^(DATABASE|REDIS|API)'")

# Database connectivity (from debug container)
app.exec("psql $DATABASE_URL -c 'SELECT 1'")
```

## When to Use

| Scenario | SDK Method |
|----------|------------|
| Debug a running app | `Sandbox.get_from_id(app_id, component)` |
| Test database connectivity | Deploy debug container → `Sandbox.get_from_id()` |
| Inspect VPC networking | Deploy debug container in same VPC → run `curl`/`nc` |
| Verify environment variables | `app.exec("env")` |

## Debug Container

For infrastructure validation, deploy the pre-built debug container:

```yaml
workers:
  - name: debug
    image:
      registry_type: GHCR
      registry: ghcr.io
      repository: bikramkgupta/do-app-debug-container-python
      tag: latest
    instance_size_slug: apps-s-1vcpu-2gb
    envs:
      - key: DATABASE_URL
        scope: RUN_TIME
        value: ${db.DATABASE_URL}
```

Then connect:

```python
from do_app_sandbox import Sandbox

app = Sandbox.get_from_id(app_id="<app-id>", component="debug")
app.exec("./validate-infra all")
```

→ See **troubleshooting** skill for complete debug container workflows.

---

## Sandbox Patterns (Create New Isolated Environments)

### Cold Sandbox (Single Use)

```python
from do_app_sandbox import Sandbox

# Create new sandbox (~30s startup)
sandbox = Sandbox.create(image="python", name="my-sandbox")

# Execute code
result = sandbox.exec("python3 -c 'print(2+2)'")
print(result.stdout)

# File operations
sandbox.filesystem.write_file("/tmp/script.py", "print('hello')")
sandbox.exec("python3 /tmp/script.py")

# Clean up
sandbox.delete()
```

### Hot Pool (Pre-warmed for AI Agents)

```python
import asyncio
from do_app_sandbox import SandboxManager, PoolConfig

async def main():
    # Configure pool with pre-warmed sandboxes
    manager = SandboxManager(
        pools={"python": PoolConfig(target_ready=3)},
    )
    await manager.start()

    # Acquire instantly (~50ms)
    sandbox = await manager.acquire(image="python")
    result = sandbox.exec("python3 -c 'print(42)'")

    # DELETE when done - sandboxes are single-use!
    sandbox.delete()

    # Shutdown when done
    await manager.shutdown()

asyncio.run(main())
```

**Note:** Sandboxes are single-use. Always call `delete()` when done. The pool auto-replenishes with new sandboxes.

→ See **sandbox** skill for complete patterns (AI code interpreter, hot pool management, Lambda comparison).
