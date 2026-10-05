# Common Error Patterns & Quick Fixes

Quick reference for diagnosing App Platform errors. Use `validate-infra` in the debug container for automated detection.

---

## Database Connectivity Errors

| Error Message | Likely Cause | Quick Fix |
|---------------|--------------|-----------|
| `SELF_SIGNED_CERT_IN_CHAIN` | Node.js TLS validation rejects DO cert | Set `ssl: { rejectUnauthorized: false }` in Pool config |
| `self-signed certificate in certificate chain` | Same as above | See [SSL reference](./ssl-database-connections.md) |
| `ECONNREFUSED` | Firewall blocking connection | `doctl databases firewalls append <db-id> --rule app:<app-id>` |
| `Connection timed out` | VPC misconfiguration or firewall | Verify app and DB in same VPC, check firewall rules |
| `permission denied for database` | User lacks privileges | Run GRANT statements as `doadmin` |
| `permission denied to create extension` | User not superuser | Extensions must be created by `doadmin` |
| `role "xxx" does not exist` | Wrong user in connection string | Verify `db_user` in app spec matches actual user |
| `database "xxx" does not exist` | Wrong database name | Verify `db_name` in app spec |
| `password authentication failed` | Wrong password or user | Recreate user or reset password via DO Console |
| `too many connections` | Connection pool exhausted | Implement connection pooling, reduce pool size |

---

## Container Startup Errors

| Error Message | Likely Cause | Quick Fix |
|---------------|--------------|-----------|
| `Cannot find module 'xxx'` | Missing in production image | Check Dockerfile COPY commands |
| `Cannot find module 'next'` | Next.js standalone missing node_modules | Add `COPY --from=builder /app/node_modules ./node_modules` |
| `Error: listen EADDRINUSE` | Port already in use | Use `$PORT` env var, don't hardcode |
| `Error: listen EACCES` | Permission denied on port | Use port > 1024, don't run as root on low ports |
| `OOMKilled` | Out of memory | Increase `instance_size_slug` |
| `exec format error` | Wrong architecture | Build for linux/amd64 |
| `no such file or directory` | Entrypoint script not found | Check file paths, permissions, line endings (CRLF→LF) |

---

## Build Errors

| Error Message | Likely Cause | Quick Fix |
|---------------|--------------|-----------|
| `npm ERR! ERESOLVE` | Dependency version conflict | Delete `node_modules`, run `npm install --legacy-peer-deps` |
| `COPY failed: file not found` | Wrong path relative to build context | Verify paths in Dockerfile match repo structure |
| `failed to fetch xxx` | Network issue or private registry | Check registry credentials, retry |
| `RUN npm ci` fails | Lockfile mismatch | Regenerate `package-lock.json` |
| `tsc: command not found` | TypeScript not in prod deps | Move to `dependencies` or build in multi-stage |

---

## Health Check Failures

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| 503 during deploy | Health check failing | Verify `/health` returns 200, increase `initial_delay_seconds` |
| Connection refused | Wrong port or binding | Bind to `0.0.0.0:$PORT`, not `localhost` |
| Timeout | Slow startup | Increase `initial_delay_seconds` and `timeout_seconds` |
| Non-200 response | Health endpoint returning error | Check `/health` implementation |

---

## SSL/TLS Errors

| Error Message | Likely Cause | Quick Fix |
|---------------|--------------|-----------|
| `SELF_SIGNED_CERT_IN_CHAIN` | Node.js validating DO's cert | `ssl: { rejectUnauthorized: false }` |
| `certificate verify failed` | Python/Ruby SSL validation | Use `sslmode=require` in connection string |
| `SSL routines:ssl3_get_server_certificate` | Missing CA cert | Download DO CA cert, configure client |

See [ssl-database-connections.md](./ssl-database-connections.md) for language-specific configurations.

---

## Environment Variable Errors

| Error Message | Likely Cause | Quick Fix |
|---------------|--------------|-----------|
| `Missing required environment variable` | Var not set in app spec | Add to `envs` section with correct scope |
| `${db.DATABASE_URL}` literal in logs | Bindable var not resolved | Check `databases` section name matches reference |
| `undefined` or `null` for expected var | Wrong scope (BUILD vs RUN) | Use `RUN_TIME` for runtime vars |

---

## Networking Errors

| Error Message | Likely Cause | Quick Fix |
|---------------|--------------|-----------|
| `CORS error` | Missing CORS headers | Configure CORS in your framework |
| `blocked by CORS policy` | Preflight failing | Handle OPTIONS requests, add required headers |
| `DNS_PROBE_FINISHED_NXDOMAIN` | Domain not pointing to app | Configure DNS records |
| `ERR_TOO_MANY_REDIRECTS` | Redirect loop | Check HTTPS redirect configuration |

---

## Deployment Errors

| Symptom | Likely Cause | Quick Fix |
|---------|--------------|-----------|
| Deployment stuck in BUILDING | Build taking too long | Check build logs, optimize Dockerfile |
| Deployment stuck in DEPLOYING | Container not becoming healthy | Check health endpoint, view runtime logs |
| Rollback to previous deployment | New deployment crashed | View runtime logs for crash reason |

---

## Quick Diagnosis Commands

```bash
# View build logs
doctl apps logs <app-id> <component> --type build

# View runtime logs
doctl apps logs <app-id> <component> --type run

# View deployment logs
doctl apps logs <app-id> <component> --type deploy

# Check deployment status
doctl apps get-deployment <app-id> <deployment-id> -o json | jq '.phase'

# List recent deployments
doctl apps list-deployments <app-id> --format ID,Phase,Progress,CreatedAt
```

---

## See Also

- [ssl-database-connections.md](./ssl-database-connections.md) — SSL configuration by language
- [troubleshooting skill](../skills/troubleshooting/SKILL.md) — Full troubleshooting guide
