# SSL/TLS Database Connections

Canonical reference for configuring SSL connections to DigitalOcean Managed Databases.

---

## The Problem

DigitalOcean Managed Databases use a **Private Certificate Authority (CA)** — not self-signed certificates in the strict sense, but certificates signed by DigitalOcean's own root key. Since this CA is not in the standard trusted root certificate stores (like Let's Encrypt or DigiCert), database clients reject it by default.

**Common error messages:**

| Environment | Error Message |
|-------------|---------------|
| Node.js (`pg`, `mysql2`) | `Error: self signed certificate in certificate chain` |
| Python (`psycopg2`, `sqlalchemy`) | `SSL: CERTIFICATE_VERIFY_FAILED` |
| Go (`lib/pq`) | `x509: certificate signed by unknown authority` |
| CLI (`psql`) | `root certificate file "root.crt" does not exist` |

**Symptom**: Connection works locally (no SSL) but fails on App Platform (SSL required).

---

## Solution Options

### Option 1: Use the CA Certificate (Recommended)

Download the CA certificate from DigitalOcean and configure your client to trust it.

**Step 1: Download CA Certificate**

1. Go to DigitalOcean Control Panel → Databases → Your Cluster
2. Click "Connection Details" → Download CA Certificate
3. Save as `ca-certificate.crt` in your project

**Step 2: Configure Your Client** (see language-specific examples below)

### Option 2: Skip Verification (Development Only)

For local development or quick testing, you can skip certificate verification. **Not recommended for production** as it removes protection against man-in-the-middle attacks.

---

## Configuration by Language

### Node.js (pg library)

**With CA Certificate (Production):**
```javascript
import { Pool } from 'pg';
import fs from 'fs';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: {
    ca: fs.readFileSync('./ca-certificate.crt').toString(),
    rejectUnauthorized: true  // Verify certificate against CA
  }
});
```

**Skip Verification (Development Only):**
```javascript
import { Pool } from 'pg';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: {
    rejectUnauthorized: false  // Skip verification - DEV ONLY
  }
});
```

**The Gotcha**: URL parameters like `?sslmode=require` do NOT control Node.js TLS validation. You must configure SSL in the Pool options.

### Python (psycopg2)

**With CA Certificate (Production):**
```python
import psycopg2

conn = psycopg2.connect(
    dsn=os.environ['DATABASE_URL'],
    sslmode='verify-full',
    sslrootcert='./ca-certificate.crt'
)
```

**Skip Verification (Development Only):**
```python
import psycopg2

conn = psycopg2.connect(
    dsn=os.environ['DATABASE_URL'],
    sslmode='require'  # Encrypts but doesn't verify cert
)
```

### Python (asyncpg)

**With CA Certificate (Production):**
```python
import asyncpg
import ssl

ssl_context = ssl.create_default_context(cafile='./ca-certificate.crt')

conn = await asyncpg.connect(
    dsn=os.environ['DATABASE_URL'],
    ssl=ssl_context
)
```

**Skip Verification (Development Only):**
```python
import asyncpg
import ssl

ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE

conn = await asyncpg.connect(
    dsn=os.environ['DATABASE_URL'],
    ssl=ssl_context
)
```

### Go (lib/pq)

**With CA Certificate (Production):**
```go
// Connection string with sslrootcert
dsn := os.Getenv("DATABASE_URL") + "&sslmode=verify-full&sslrootcert=./ca-certificate.crt"
db, err := sql.Open("postgres", dsn)
```

**Skip Verification (Development Only):**
```go
dsn := os.Getenv("DATABASE_URL")
if !strings.Contains(dsn, "sslmode=") {
    dsn += "?sslmode=require"
}
db, err := sql.Open("postgres", dsn)
```

### Go (pgx)

**With CA Certificate (Production):**
```go
import (
    "context"
    "crypto/tls"
    "crypto/x509"
    "os"
    "github.com/jackc/pgx/v5"
)

caCert, _ := os.ReadFile("./ca-certificate.crt")
caCertPool := x509.NewCertPool()
caCertPool.AppendCertsFromPEM(caCert)

config, _ := pgx.ParseConfig(os.Getenv("DATABASE_URL"))
config.TLSConfig = &tls.Config{
    RootCAs: caCertPool,
}

conn, err := pgx.ConnectConfig(context.Background(), config)
```

**Skip Verification (Development Only):**
```go
config.TLSConfig = &tls.Config{
    InsecureSkipVerify: true,  // DEV ONLY
}
```

### Ruby (pg gem)

**With CA Certificate (Production):**
```ruby
require 'pg'

conn = PG.connect(
  ENV['DATABASE_URL'],
  sslmode: 'verify-full',
  sslrootcert: './ca-certificate.crt'
)
```

**Skip Verification (Development Only):**
```ruby
conn = PG.connect(ENV['DATABASE_URL'], sslmode: 'require')
```

### Rust (tokio-postgres)

**With CA Certificate (Production):**
```rust
use native_tls::{Certificate, TlsConnector};
use postgres_native_tls::MakeTlsConnector;
use std::fs;

let cert = fs::read("./ca-certificate.crt")?;
let cert = Certificate::from_pem(&cert)?;

let connector = TlsConnector::builder()
    .add_root_certificate(cert)
    .build()?;
let connector = MakeTlsConnector::new(connector);

let (client, connection) = config.connect(connector).await?;
```

**Skip Verification (Development Only):**
```rust
let connector = TlsConnector::builder()
    .danger_accept_invalid_certs(true)  // DEV ONLY
    .build()?;
```

---

## URL Parameter Reference

These parameters go in the connection string:

| Parameter | Effect | When to Use |
|-----------|--------|-------------|
| `sslmode=disable` | No SSL | Never in production |
| `sslmode=require` | Encrypt, don't verify cert | Development only |
| `sslmode=verify-ca` | Verify cert against CA | Production (need CA file) |
| `sslmode=verify-full` | Verify cert + hostname | Production (most secure) |
| `sslrootcert=path` | Path to CA certificate | Required for verify-ca/verify-full |

**For Production**: Use `sslmode=verify-full` with `sslrootcert` pointing to DO's CA certificate.

---

## App Platform Deployment

When deploying to App Platform, bundle the CA certificate with your app:

**Option A: Include in repo**
```
your-app/
├── ca-certificate.crt  # Downloaded from DO Console
├── src/
└── ...
```

**Option B: Environment variable**
```yaml
# In app spec
envs:
  - key: DATABASE_CA_CERT
    scope: RUN_TIME
    value: |
      -----BEGIN CERTIFICATE-----
      [paste certificate content]
      -----END CERTIFICATE-----
```

Then in code:
```javascript
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: {
    ca: process.env.DATABASE_CA_CERT,
    rejectUnauthorized: true
  }
});
```

---

## Common Mistakes

### Mistake 1: Assuming URL params control Node.js validation

```javascript
// This does NOT prevent certificate rejection in Node.js!
const url = "postgresql://user:pass@host:25060/db?sslmode=require";
const pool = new Pool({ connectionString: url });  // Still rejects cert!
```

**Fix**: Set `ssl` options in Pool config.

### Mistake 2: Disabling SSL entirely

```javascript
// DON'T do this in production!
const pool = new Pool({
  connectionString: url,
  ssl: false  // No encryption - data sent in plaintext
});
```

**Fix**: Use SSL with CA certificate or `rejectUnauthorized: false` (dev only).

### Mistake 3: Using rejectUnauthorized: false in production

```javascript
// Works but is INSECURE in production
ssl: { rejectUnauthorized: false }
```

**Fix**: Download and use the CA certificate for production.

---

## Testing SSL Configuration

### Verify Certificate Chain

```bash
# Check what certificate the database presents
openssl s_client -connect your-db-host:25060 -servername your-db-host

# Verify against DO's CA
openssl verify -CAfile ca-certificate.crt server-cert.pem
```

### In Debug Container

```bash
# Connect to debug container
python -m do_app_sandbox.cli exec <app-id> debug

# Test with psql (with CA cert)
psql "$DATABASE_URL?sslmode=verify-full&sslrootcert=/path/to/ca-certificate.crt" -c "SELECT 1"

# Test with psql (skip verification)
psql "$DATABASE_URL?sslmode=require" -c "SELECT 1"
```

---

## See Also

- [error-patterns.md](./error-patterns.md) — Quick error lookup
- [postgres skill](../skills/postgres/SKILL.md) — Full Postgres configuration
- [DigitalOcean Docs: Secure Connections](https://docs.digitalocean.com/products/databases/postgresql/how-to/connect/#secure-connections)
