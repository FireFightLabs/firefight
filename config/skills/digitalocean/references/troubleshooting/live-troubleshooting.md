# Live Troubleshooting (Shell Access)

When the container is running, use the SDK for direct access.

## Connect to Running App

```python
from do_app_sandbox import Sandbox

app = Sandbox.get_from_id(
    app_id="ea1525eb-7e39-4fc5-91d4-5c8dc187581f",
    component="web"
)

result = app.exec("whoami")
print(f"Connected as: {result.stdout.strip()}")
```

## Diagnostic Commands

```python
# System overview
app.exec("uname -a")
app.exec("free -m")
app.exec("df -h")
app.exec("ps aux")
app.exec("top -b -n 1 | head -20")

# Environment check
app.exec("env | sort")
app.exec("echo $PORT")
app.exec("echo $DATABASE_URL")

# Network diagnostics
app.exec("netstat -tlnp 2>/dev/null || ss -tlnp")
app.exec("curl -v localhost:8080/health")
app.exec("curl -I localhost:8080")

# Application logs
app.exec("tail -100 /var/log/app.log 2>/dev/null || echo 'No log file'")
app.exec("ls -la /app")
```

## File Operations

```python
# Read file
content = app.filesystem.read_file("/app/config.py")

# List directory
files = app.filesystem.list_dir("/app")
for f in files:
    print(f"  {f.name} ({'dir' if f.is_dir else 'file'})")

# Download file
app.filesystem.download_file("/app/logs/error.log", "./error.log")

# Upload diagnostic script
app.filesystem.upload_file("./diagnostic.sh", "/tmp/diagnostic.sh")
app.exec("chmod +x /tmp/diagnostic.sh && /tmp/diagnostic.sh")
```

## Database Connectivity Testing

```python
# Check DATABASE_URL
result = app.exec("echo $DATABASE_URL")
db_url = result.stdout.strip()
if not db_url:
    print("ERROR: DATABASE_URL not set")

# Test PostgreSQL
result = app.exec("pg_isready -d \"$DATABASE_URL\" 2>&1")
print(result.stdout)

# Python DB test
db_test = '''
import os
try:
    import psycopg2
    conn = psycopg2.connect(os.environ["DATABASE_URL"])
    cur = conn.cursor()
    cur.execute("SELECT version()")
    print(f"Connected: {cur.fetchone()[0][:50]}")
    cur.close()
    conn.close()
except ImportError:
    print("psycopg2 not installed")
except Exception as e:
    print(f"Connection failed: {e}")
'''
app.filesystem.write_file("/tmp/db_test.py", db_test)
result = app.exec("python3 /tmp/db_test.py")
print(result.stdout)
```

## Hot Fix Workflow

**CRITICAL**: Hot fixes are TEMPORARY. Always commit proper fixes.

```python
# 1. Download problematic file
app.filesystem.download_file("/app/src/buggy.py", "./buggy.py")

# 2. Edit locally...

# 3. Upload patched file
app.filesystem.upload_file("./fixed.py", "/app/src/buggy.py")

# 4. Restart application
app.exec("pkill -HUP gunicorn 2>/dev/null || echo 'No gunicorn'")  # Python
app.exec("pkill -HUP node 2>/dev/null || echo 'No node'")          # Node.js

# 5. Verify
import time
time.sleep(2)
result = app.exec("curl -s localhost:8080/health")
print(f"Health: {result.stdout}")

# 6. REMIND TO COMMIT
print("IMPORTANT: Commit fix to repository and deploy properly!")
```

## SDK Prompt Compatibility

The SDK uses `pexpect` to detect command completion. If commands timeout:

**Supported prompts:**
- `sandbox@host:/path$ `
- `devcontainer@host:/path$ `
- `user@host:/path$ ` or `#`

**If your container uses a custom prompt:**

Option 1 - Modify SDK:
```python
# In do_app_sandbox/executor.py
PROMPT_PATTERNS.append(re.compile(rb"myapp> "))
```

Option 2 - Modify container:
```bash
export PS1='\u@\h:\w\$ '
```

## Prerequisites

```bash
# doctl authenticated
doctl account get

# SDK installed
uv pip install do-app-sandbox

# Get app info
doctl apps list --format ID,Spec.Name
doctl apps get <app_id> -o json | jq -r '.[0].spec.services[].name'
```
