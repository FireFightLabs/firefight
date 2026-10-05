# Domains and DNS

## Domain Types

| Type | Purpose |
|------|---------|
| `PRIMARY` | Main domain (one per app) |
| `ALIAS` | Additional domains |

```yaml
domains:
  - domain: example.com
    type: PRIMARY
  - domain: www.example.com
    type: ALIAS
```

## Starter vs Custom Domain

| Aspect | Starter | Custom |
|--------|---------|--------|
| URL | `*.ondigitalocean.app` | Your domain |
| SSL | Automatic | Automatic |
| Edge features | No | Yes |
| Wildcard | No | Yes |

## DNS Setup Options

### Option 1: DigitalOcean-Managed DNS (Recommended)

```yaml
domains:
  - domain: example.com
    type: PRIMARY
    zone: example.com  # DO manages DNS
```

Point registrar nameservers to:
- `ns1.digitalocean.com`
- `ns2.digitalocean.com`
- `ns3.digitalocean.com`

### Option 2: CNAME (Self-Managed DNS)

```
CNAME  app.example.com  →  your-app.ondigitalocean.app
```

For apex domains, use A records:
- `162.159.140.98` (IPv4)
- `172.66.0.96` (IPv4)
- `2606:4700:7::60` (IPv6)
- `2a06:98c1:58::60` (IPv6)

## Wildcard Domains

```yaml
domains:
  - domain: example.com
    type: PRIMARY
    wildcard: true
    zone: example.com
```

**Validation:**
- Requires TXT record validation
- Re-validate every 30 days

**Limitations:**
- Must add root domain first
- Some TLDs not supported

## TLS/SSL

```yaml
domains:
  - domain: example.com
    minimum_tls_version: "1.3"  # or "1.2"
```

## CAA Records

If using CAA, add both CAs:

```
CAA 0 issue "letsencrypt.org"
CAA 0 issue "pki.goog"
```

App Platform uses LetsEncrypt and Google Trust.
