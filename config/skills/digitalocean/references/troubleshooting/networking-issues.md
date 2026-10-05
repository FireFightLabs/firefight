# Networking Issues

> For comprehensive networking documentation, see the [networking skill](../../networking/SKILL.md).

## DNS Issues

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Domain not resolving | `dig example.com` | Check CNAME/A at registrar, wait 72h |
| SSL certificate error | `dig example.com CAA` | Add letsencrypt.org + pki.goog to CAA |
| Wildcard not working | Check TXT in DO console | Add TXT record, re-validate |
| Domain shows "pending" | DNS not propagated | Verify records, wait |

**Diagnosis**:
```bash
dig example.com
dig example.com CAA
dig example.com NS

# From container
nslookup example.com
curl -I https://example.com
```

## CORS Errors

| Error | Cause | Fix |
|-------|-------|-----|
| No Access-Control-Allow-Origin | Origin not in allow_origins | Add exact or regex pattern |
| Method not allowed | Method not in allow_methods | Add method (PUT, DELETE) |
| Preflight fails | OPTIONS not allowed | Add OPTIONS to allow_methods |
| Credentials not supported | Regex with allow_credentials | Use exact origins only |
| Header not allowed | Custom header not listed | Add to allow_headers |

**Debug**:
```bash
# Test preflight
curl -X OPTIONS https://api.example.com/endpoint \
  -H "Origin: https://app.example.com" \
  -H "Access-Control-Request-Method: POST" \
  -v
```

**Config**:
```yaml
cors:
  allow_origins:
    - exact: https://app.example.com
  allow_methods:
    - GET
    - POST
    - OPTIONS
  allow_headers:
    - Content-Type
    - Authorization
  allow_credentials: true
```

## Routing Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Wrong component serves | Rule order | Put specific rules first |
| Path rewrite not working | Wrong syntax | Use component.rewrite field |
| Subdomain not routing | Missing authority | Add match.authority.exact |
| 404 on valid path | Missing rule | Add ingress rule |

**Correct order**:
```yaml
ingress:
  rules:
    - component: { name: api }
      match: { path: { prefix: /api } }   # Specific first
    - component: { name: frontend }
      match: { path: { prefix: / } }      # Catch-all last
```

## VPC Issues

| Issue | Symptom | Fix |
|-------|---------|-----|
| App not in VPC | Can't reach managed DB | Add vpc.id to app spec |
| Trusted sources blocking | Connection refused | Add VPC CIDR to trusted sources |
| Wrong rule type | Refused with app rule | Use ip_addr rule, not app rule |
| Wrong connection string | Timeout | Use private hostname |

**VPC CIDR Whitelisting (Recommended)**:
```bash
# Get VPC CIDR
doctl vpcs get $VPC_ID --format IPRange
# Example: 10.126.0.0/20

# Add to database
doctl databases firewalls append <cluster-id> --rule ip_addr:10.126.0.0/20
```

**Per-App Whitelisting**:
```bash
VPC_EGRESS_IP=$(doctl apps get <app-id> -o json | jq -r '.. | .egress_ips? // empty | .[0].ip // empty' | head -1)
doctl databases firewalls append <cluster-id> --rule ip_addr:$VPC_EGRESS_IP
```

**Diagnosis**:
```python
# Test private hostname
result = app.exec("dig +short private-mydb-xxx.db.ondigitalocean.com")
# Should return 10.x.x.x

# Test connectivity
result = app.exec("nc -zv private-mydb-xxx.db.ondigitalocean.com 25060 2>&1")
```

## Static IP / Egress

| Issue | Symptom | Fix |
|-------|---------|-----|
| External API blocks | 403 from third-party | Enable dedicated egress |
| Functions egress | Functions use shared IPs | Functions don't support dedicated |

```bash
# Get egress IPs
doctl apps get <app_id> -o json | jq '.[] | .dedicated_ips'
```

## Internal Service Communication

| Issue | Symptom | Fix |
|-------|---------|-----|
| Service-to-service fails | Connection refused | Use ${service.PRIVATE_URL} |
| Internal port not reachable | Timeout | Add to internal_ports |
| Worker can't reach service | Timeout | Workers only make outbound |

```python
# Test internal communication
result = app.exec("curl -v http://api:8080/health")
result = app.exec("env | grep PRIVATE_URL")
```
