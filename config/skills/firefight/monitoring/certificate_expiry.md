---
name: certificate_expiry
when: A scheduled check of TLS certificates, or anyone asking when a domain's certificate expires or whether it renews
tools: [list_notices, find_resources, get_resource, resource_status, check_from_outside]
---
1. List the domains and zones on the map with `find_resources`, passing `kind` domain and zone. Each one's `resource_status` reads it from the provider that serves it.
2. Check each hostname as a user's browser reaches it with `check_from_outside`, passing its `url` as https and the hostname. It answers the certificate's issuer, expiry, days left, and whether it is trusted and covers the host. That is the certificate users are actually served, so it wins when the provider says otherwise.
3. Read how it renews from the provider that issued it, as the second source: an edge network's certificate packs, a Kubernetes cluster's cert-manager certificates, or a hosting provider's custom domains. Load that provider's skill for the read. Never take an expiry from memory.
4. A certificate that is not trusted or does not cover the host is high now, whatever its date. One the provider renews on its own is a problem only when renewal is failing, such as a validation record that is missing or a renewal attempt that errored, or when it expires within 14 days anyway. Raise one that does not renew on its own when it expires within 30 days, as high within 7.
5. The day it becomes a problem is the expiry date.
6. Read `list_notices` with `signal` certificate first, and keep the topic and resource of anything raised before.
7. A domain no check could reach from outside and no provider reads is a gap to say, naming the domain and why. The outside check runs from one region, which its answer names.
