---
name: cloudflare_attack
when: Handling a traffic spike, a DDoS attack or abusive traffic hitting a site behind Cloudflare
tools: [search, execute, docs]
references: [security/under-ddos-attack.md, security/under-attack-mode.md, security/security-level.md, security/security-events.md, security/querying-firewall-events.md, security/rate-limiting-rules.md, security/rate-limiting-rules-create-api.md, security/custom-rules-create-api.md, origin/protect-your-origin-server.md]
---
1. Confirm it is an attack. Cloudflare's signs are a site that is offline or slow, unexpected spikes in requests or bandwidth, and strange requests in the origin's logs. Compare the zone's traffic now with its normal level, through `execute` and the GraphQL Analytics API.
2. Find who, with the firewallEventsAdaptive dataset: the top client IPs, ASNs, countries, paths and user agents, and what Cloudflare already did about them. Security events are sampled for large volumes, so narrow the time window when the numbers look incomplete.
3. Stop it with the narrowest tool that works, and say what each one costs before the person confirms:
   - A rate limiting rule for a path being hammered, such as a login or an API. It goes into the zone's http_ratelimit phase entry point ruleset, with a ratelimit object naming what to count by (for example ip.src), the period, the number of requests allowed and how long to block. Rate limiting rules must come last in that ruleset.
   - A custom rule that challenges or blocks the traffic the events point at. Use the cloudflare_block skill for addresses, networks and countries.
   - Under Attack mode, as a last resort. Cloudflare says to use it only under a DDoS attack, since every visitor gets a challenge page and it can break API traffic and third party analytics. Through the API it is the zone's security level. A configuration rule can turn it on for only part of the site, such as the login page.
4. Find every endpoint with `search` before `execute`. The person confirms each call.
5. Afterwards, say what was changed, and offer to undo each change once traffic is back to normal, such as setting the security level back.
6. When the origin itself is being hit directly, point to Cloudflare's guidance on protecting the origin, such as proxying its DNS records and only allowing Cloudflare's IP ranges.
