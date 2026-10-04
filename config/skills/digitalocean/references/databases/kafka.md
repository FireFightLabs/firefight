# Kafka Reference

Complete guide for DigitalOcean Managed Kafka on App Platform.

---

## Critical: Trusted Sources Limitation

> **Kafka only supports IP-based trusted source rules (`ip_addr:`), NOT app-based rules (`app:`).**
>
> - **Public network + trusted sources:** NOT SUPPORTED (public egress IPs change on worker migration)
> - **VPC + trusted sources:** SUPPORTED (VPC egress IP is static for app lifetime)
> - **No trusted sources:** Works in both network modes

---

## Create Cluster

```bash
# Create cluster (use General Purpose for Schema Registry support)
doctl databases create my-kafka \
  --engine kafka \
  --region nyc3 \
  --size db-s-2vcpu-4gb \
  --version 3.7

CLUSTER_ID=$(doctl databases list --format ID,Name --no-header | grep my-kafka | awk '{print $1}')

# Create topic
# NOTE: Use --partition-count (not --partitions)
doctl databases topics create $CLUSTER_ID my-topic \
  --partition-count 3 \
  --replication-factor 2

# Trusted sources for Kafka:
# Option A: Disable trusted sources (works for public and VPC)
# Option B: Use VPC + IP-based rule (most secure)
#   doctl databases firewalls append $CLUSTER_ID --rule ip_addr:<vpc-egress-ip>
# NOTE: app:$APP_ID rules do NOT work with Kafka
```

---

## Create Users with Permissions

Kafka user permissions are set at creation time:

```bash
# Create user via Console: Databases → my-kafka → Users & Topics tab
# Available permissions:
# - Admin: Manage Topics + read/write all Topics
# - Produce: Write to all Topics
# - Consume: Read from all Topics
# - Consume and Produce: Read and write all Topics

# Via doctl (creates with default permissions)
doctl databases user create $CLUSTER_ID myappuser
```

---

## App Spec

```yaml
databases:
  - name: kafka
    engine: KAFKA
    production: true
    cluster_name: my-kafka

services:
  - name: api
    envs:
      # Recommended bindable variable pattern
      - key: KAFKA_BROKER
        scope: RUN_TIME
        value: ${kafka.HOSTNAME}:${kafka.PORT}
      - key: KAFKA_USERNAME
        scope: RUN_TIME
        value: ${kafka.USERNAME}
      - key: KAFKA_PASSWORD
        scope: RUN_TIME
        value: ${kafka.PASSWORD}
      - key: KAFKA_CA_CERT
        scope: RUN_TIME
        value: ${kafka.CA_CERT}
```

---

## Bindable Variables

| Variable | Description |
|----------|-------------|
| `${kafka.HOSTNAME}` | Kafka broker hostname |
| `${kafka.PORT}` | Kafka broker port |
| `${kafka.USERNAME}` | Authentication username |
| `${kafka.PASSWORD}` | Authentication password |
| `${kafka.CA_CERT}` | CA certificate for TLS |

**Note**: Combine hostname and port for broker address: `${kafka.HOSTNAME}:${kafka.PORT}`

---

## SASL Authentication

DO Kafka uses SASL/SCRAM-SHA-256:

### Node.js (kafkajs)

```javascript
const kafka = new Kafka({
  brokers: [process.env.KAFKA_BROKER],
  ssl: true,
  sasl: {
    mechanism: 'scram-sha-256',
    username: process.env.KAFKA_USERNAME,
    password: process.env.KAFKA_PASSWORD,
  },
});
```

### Python (confluent-kafka)

```python
from confluent_kafka import Producer

producer = Producer({
    'bootstrap.servers': os.environ['KAFKA_BROKER'],
    'security.protocol': 'SASL_SSL',
    'sasl.mechanism': 'SCRAM-SHA-256',
    'sasl.username': os.environ['KAFKA_USERNAME'],
    'sasl.password': os.environ['KAFKA_PASSWORD'],
})
```

---

## SSL Certificate Handling

The `KAFKA_CA_CERT` bindable variable contains the certificate content as a string, but Kafka clients (librdkafka, KafkaJS, kcat) typically expect a **file path**.

### Solution 1: Write cert in entrypoint script

```bash
#!/bin/bash
# entrypoint.sh
if [ -n "$KAFKA_CA_CERT" ]; then
  echo "$KAFKA_CA_CERT" > /tmp/kafka-ca.crt
  export KAFKA_CA_LOCATION=/tmp/kafka-ca.crt
fi
exec "$@"
```

### Solution 2: Write cert in application code (Node.js)

```javascript
const fs = require('fs');

if (process.env.KAFKA_CA_CERT) {
  fs.writeFileSync('/tmp/kafka-ca.crt', process.env.KAFKA_CA_CERT);
}

const kafka = new Kafka({
  brokers: [process.env.KAFKA_BROKER],
  ssl: {
    ca: [fs.readFileSync('/tmp/kafka-ca.crt')],
  },
  sasl: {
    mechanism: 'scram-sha-256',
    username: process.env.KAFKA_USERNAME,
    password: process.env.KAFKA_PASSWORD,
  },
});
```

### Solution 3: Write cert in application code (Python)

```python
import os

if os.environ.get('KAFKA_CA_CERT'):
    with open('/tmp/kafka-ca.crt', 'w') as f:
        f.write(os.environ['KAFKA_CA_CERT'])

producer = Producer({
    'bootstrap.servers': os.environ['KAFKA_BROKER'],
    'security.protocol': 'SASL_SSL',
    'sasl.mechanism': 'SCRAM-SHA-256',
    'sasl.username': os.environ['KAFKA_USERNAME'],
    'sasl.password': os.environ['KAFKA_PASSWORD'],
    'ssl.ca.location': '/tmp/kafka-ca.crt',  # File path, not content
})
```

> **Note**: This applies to both production apps and debug containers using `kcat`.

---

## Schema Registry (General Purpose Plans Only)

Schema Registry validates message structures and prevents data corruption.

### Requirements

- Only available on General Purpose plans (not shared CPU)
- Must be enabled via Console: Databases → Settings → Schema Registry
- Available on port 25065 using same hostname
- If downscaling to shared CPU, must disable Schema Registry first

**Enable via Console**: Databases → my-kafka → Settings → Schema Registry → Toggle On

**Schema Registry URL**: `https://<kafka-hostname>:25065`

---

## Constraints and Defaults

| Constraint | Details |
|------------|---------|
| Minimum size | `db-s-2vcpu-4gb` (Kafka requires more resources) |
| Trusted sources | IP-based only (`ip_addr:`); app-based (`app:`) NOT supported |
| Public + TS | **NOT SUPPORTED** — use VPC or disable trusted sources |
| VPC + TS | Supported — use VPC egress IP |
| Authentication | SASL/SCRAM-SHA-256 required |
| Default retention | 7 days |
| Topic management | `doctl databases topics` commands |
| Schema Registry | General Purpose plans only, port 25065 |
| Default user | `doadmin` (cannot be deleted) |

---

## Troubleshooting

### "Connection refused" with trusted sources

Kafka doesn't support `app:` rules. Either:
1. Disable trusted sources, or
2. Use VPC with IP-based rule: `doctl databases firewalls append $CLUSTER_ID --rule ip_addr:<vpc-egress-ip>`

### SASL authentication failed

Ensure mechanism is `SCRAM-SHA-256` (not PLAIN or other):

```python
'sasl.mechanism': 'SCRAM-SHA-256'
```

### SSL certificate errors

Write the CA cert to a file and reference the path, not the content:

```python
'ssl.ca.location': '/tmp/kafka-ca.crt'  # File path
```

---

## Documentation Links

- [Kafka on DigitalOcean](https://docs.digitalocean.com/products/databases/kafka/)
- [doctl databases reference](https://docs.digitalocean.com/reference/doctl/reference/databases/)
