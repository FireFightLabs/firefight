# Diagnostic Scripts

Scripts for health checks and connectivity testing.

## General Health Check

```bash
#!/bin/bash
# Save as diagnostic.sh

echo "=== System Info ==="
uname -a

echo "=== Memory ==="
free -m

echo "=== Disk ==="
df -h

echo "=== Environment (filtered) ==="
env | grep -E 'PORT|DATABASE|REDIS|NODE_ENV|PYTHON' | sort

echo "=== Processes ==="
ps aux --sort=-%mem | head -15

echo "=== Network Listeners ==="
netstat -tlnp 2>/dev/null || ss -tlnp

echo "=== Health Check ==="
curl -s -o /dev/null -w "%{http_code}" localhost:${PORT:-8080}/health 2>/dev/null || echo "FAILED"
```

## Database Connectivity (Python)

```python
#!/usr/bin/env python3
import os
import sys

def check_postgres():
    db_url = os.environ.get("DATABASE_URL")
    if not db_url:
        print("DATABASE_URL not set")
        return False

    try:
        import psycopg2
        conn = psycopg2.connect(db_url)
        cur = conn.cursor()
        cur.execute("SELECT version()")
        version = cur.fetchone()[0]
        print(f"PostgreSQL: {version[:60]}...")

        cur.execute("SELECT count(*) FROM pg_stat_activity WHERE datname = current_database()")
        connections = cur.fetchone()[0]
        print(f"Active connections: {connections}")

        cur.close()
        conn.close()
        return True
    except ImportError:
        print("psycopg2 not installed")
        return False
    except Exception as e:
        print(f"Connection failed: {e}")
        return False

if __name__ == "__main__":
    success = check_postgres()
    sys.exit(0 if success else 1)
```

## Memory and Performance

```python
# Memory overview
result = app.exec("free -m")

# Top memory consumers
result = app.exec("ps aux --sort=-%mem | head -10")

# Top CPU consumers
result = app.exec("ps aux --sort=-%cpu | head -10")

# Node.js heap
result = app.exec("node -e \"console.log(process.memoryUsage())\" 2>/dev/null")
```

| Issue | Signs | Fix |
|-------|-------|-----|
| Memory leak | Gradual increase, eventual OOM | Profile, fix leaks |
| Insufficient memory | Immediate OOM | Upgrade instance |
| Pool exhaustion | DB errors, high connections | Configure pool limits |
| High CPU on idle | Busy loops | Profile and optimize |

## Testing Strategy

### Capture Baseline

```python
def capture_baseline(app):
    return {
        "health": app.exec("curl -s localhost:8080/health").stdout,
        "processes": app.exec("ps aux").stdout,
        "env": app.exec("env | sort").stdout,
        "disk": app.exec("df -h").stdout,
    }

baseline = capture_baseline(app)
```

### Verify After Fix

```python
def verify_fix(app, baseline, expected):
    current = capture_baseline(app)
    health_ok = "200" in current["health"] or "ok" in current["health"].lower()
    process_ok = expected.get("process") in current["processes"]
    return {"health_check": health_ok, "process_running": process_ok}
```

### Rollback Strategy

```python
# Save original
original = app.filesystem.read_file("/app/config.py")

# Make changes
app.filesystem.write_file("/app/config.py", new_content)

# Rollback if needed
app.filesystem.write_file("/app/config.py", original)
```

## Kafka Certificate Validation

```bash
# Check CA cert is valid PEM
echo "$KAFKA_CA_CERT" | openssl x509 -noout -text > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "CA certificate is valid"
else
  echo "CA certificate is INVALID"
fi

# Verify cert matches broker
echo "$KAFKA_CA_CERT" | openssl x509 -noout -issuer -subject

# Test with kcat
echo "" | kcat -b "$KAFKA_BROKERS" -L \
  -X security.protocol=SASL_SSL \
  -X sasl.mechanisms=SCRAM-SHA-256 \
  -X sasl.username="$KAFKA_USERNAME" \
  -X sasl.password="$KAFKA_PASSWORD" \
  -X ssl.ca.location=/dev/stdin <<< "$KAFKA_CA_CERT"
```

| Symptom | Cause | Fix |
|---------|-------|-----|
| SSL handshake failed | CA cert missing | Use ${kafka.CA_CERT} |
| SASL auth failed | Wrong credentials | Use bindable vars |
| Unknown topic | Topic doesn't exist | Create in DO Console |
| Connection hangs | Trusted sources | Use private broker URL |

## Restart and Rebuild

```bash
# Restart all components
doctl apps restart <app_id>

# Restart specific component
doctl apps restart <app_id> --components web

# Redeploy
doctl apps create-deployment <app_id>

# Force full rebuild
doctl apps create-deployment <app_id> --force-rebuild
```

## Deployment Cycle

Standard deploys: 5-7 minutes. Poll every 30 seconds.

```python
import time
import subprocess
import json

def wait_for_deployment(app_id, timeout=420):
    start = time.time()
    while time.time() - start < timeout:
        result = subprocess.run(
            ["doctl", "apps", "get", app_id, "-o", "json"],
            capture_output=True, text=True
        )
        data = json.loads(result.stdout)
        phase = data[0]["active_deployment"]["phase"]

        if phase == "ACTIVE":
            return True
        elif phase in ("ERROR", "CANCELED"):
            return False

        time.sleep(30)
    return False
```
