# Static IP Addresses and Egress

## Ingress IPs (Free)

Shared public IPs for incoming traffic:

| Type | Address |
|------|---------|
| IPv4 | `162.159.140.98` |
| IPv4 | `172.66.0.96` |
| IPv6 | `2606:4700:7::60` |
| IPv6 | `2a06:98c1:58::60` |

Use for DNS A/AAAA records when self-managing DNS.

## Dedicated Egress IPs (Paid)

Route outbound traffic through dedicated IPs.

**Use cases:**
- Firewall allowlisting
- IP-based authentication
- Audit/compliance

**Enable:**
```yaml
egress:
  type: DEDICATED_IP
```

**Via Control Panel:**
Apps → Settings → Dedicated Egress IP Addresses → Add

**Get IPs:**
```bash
doctl apps get <app_id> -o json | jq '.[] | .dedicated_ips'
```

## Egress Limitations

| Limitation | Details |
|------------|---------|
| App-level only | All components except functions |
| Functions excluded | Cannot use dedicated egress |
| Log forwarding | Separate routing |
| No IPv6 | IPv4 only |
| Permanent release | Cannot recover released IPs |

## Edge Settings

Requires custom domain.

| Setting | Field | Default |
|---------|-------|---------|
| CDN Cache | `disable_edge_cache` | false (enabled) |
| Email Obfuscation | `disable_email_obfuscation` | false |
| DDoS Protection | `enhanced_threat_control_enabled` | false |

```yaml
disable_edge_cache: true
enhanced_threat_control_enabled: true
```

## HTTP/2

```yaml
services:
  - name: grpc-service
    http_port: 50051
    protocol: HTTP2
```

| Use Case | Protocol |
|----------|----------|
| gRPC | HTTP2 (required) |
| SSE | HTTP2 (recommended) |
| Standard web | HTTP/1.1 (default) |

## Internal Service Communication

**Placeholders:**
| Placeholder | Resolves To |
|-------------|-------------|
| `${service.PRIVATE_URL}` | Internal URL |
| `${service.PUBLIC_URL}` | External URL |
| `${APP_URL}` | App default URL |

**Example:**
```yaml
services:
  - name: api
    envs:
      - key: AUTH_URL
        value: ${auth.PRIVATE_URL}
```

**Internal DNS:**
Services reachable by name: `http://service-name:port`

**Internal Ports:**
```yaml
services:
  - name: api
    http_port: 8080
    internal_ports:
      - 9090  # Internal only
```

## When to Use PRIVATE vs PUBLIC

| Scenario | Use |
|----------|-----|
| Backend-to-backend | PRIVATE_URL |
| Worker jobs | PRIVATE_URL |
| Frontend build | PUBLIC_URL |
| External webhooks | PUBLIC_URL |
