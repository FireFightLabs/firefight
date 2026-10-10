---
name: certificate_expiry
when: A scheduled check of TLS certificates, or anyone asking when a domain's certificate expires or whether it renews
tools: [list_notices, find_resources, get_resource, resource_status]
---
1. List the domains and zones on the map with `find_resources`, passing `kind` domain and zone. Each one's `resource_status` reads it from the provider that serves it.
2. Read each certificate's expiry and how it renews from the provider that issued it: an edge network's certificate packs, a Kubernetes cluster's cert-manager certificates, or a hosting provider's custom domains. Load that provider's skill for the read. Never take an expiry from memory.
3. A certificate the provider renews on its own is a problem only when renewal is failing, such as a validation record that is missing or a renewal attempt that errored, or when it expires within 14 days anyway. Raise one that does not renew on its own when it expires within 30 days, as high within 7.
4. The day it becomes a problem is the expiry date.
5. Read `list_notices` with `signal` certificate first, and keep the topic and resource of anything raised before.
6. A domain whose certificate you could not read is a gap to say, naming the domain and what would read it.
