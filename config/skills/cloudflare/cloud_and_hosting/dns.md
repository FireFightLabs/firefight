---
name: cloudflare_dns
when: Checking or changing a DNS record on Cloudflare, such as where a hostname points or whether it goes through Cloudflare
tools: [get_resource_map, resource_status, search, execute, docs]
references: [dns/dns-records.md, dns/create-dns-records.md, origin/protect-your-origin-server.md]
---
Start from the zone on the resource map. `get_resource_map` with the domain names the Cloudflare account that holds it and its id, which is the zone id every endpoint takes, and `resource_status` with the domain reads the zone from Cloudflare. Both only read, so the person is not asked. Find a zone with `execute` only when the map does not have it.

1. Read the zone's records with `execute`, after finding the endpoint with `search`. For each record, note its type, name, content, TTL and proxy status.
2. A proxied record goes through Cloudflare, which hides the origin's address and applies caching and security. A DNS only record sends visitors straight to the origin, and the record shows the origin's address to anyone.
3. For 521 or 522 errors, check that the origin address in the record is still the one the host gives the origin.
4. Before changing a record, say the record, the change, and what visitors will see. Changing where a record points, or turning off the proxy, can take a site down or expose the origin. The person confirms each call.
5. Every plan has a limit on how many records a zone or account may hold, and a new record is refused once the zone is at its limit.
6. When a call is refused for a permission, name the permission the endpoint accepts, from x-api-token-group in its entry in the specification.
