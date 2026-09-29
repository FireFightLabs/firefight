---
name: cloudflare_block
when: Blocking, challenging or allowing traffic on Cloudflare by IP address, IP range, ASN or country, or undoing a block
tools: [search, execute, docs]
references: [security/ip-access-rules.md, security/ip-access-rules-actions.md, security/ip-access-rules-parameters.md, security/custom-rules.md, security/custom-rules-create-api.md, security/lists.md, security/lists-api-endpoints.md, security/allowlist-only.md, security/block-countries.md, security/security-events.md]
---
1. Look before blocking. Read the zone's security events for the address or network in question, through `execute` and the firewallEventsAdaptive dataset of the GraphQL Analytics API, so the block rests on what the traffic did. Security events are kept for 24 hours on Free and Pro, 3 days on Business and 30 days on Enterprise.
2. Pick the mechanism Cloudflare recommends. Cloudflare recommends a WAF custom rule over an IP Access rule for blocking by IP or by country:
   - Many addresses: put them in an IP list, then one custom rule references the list, such as ip.src in $blocked_ips. Adding to the list later updates every rule using it. A list name uses lowercase letters, numbers and underscores only.
   - A custom rule goes into the zone's http_request_firewall_custom phase entry point ruleset: read that ruleset, then add a rule to it, or create the ruleset with the rule when it does not exist yet.
   - An IP Access rule still works for a single address, range, ASN or country, and is available on every plan. Blocking a country with an IP Access rule needs Enterprise. A custom rule can block a country on any plan.
3. Pick the action. Block stops the visitor. Managed Challenge, Non-Interactive Challenge and Interactive Challenge let people through and stop bots. Allow skips every security check, including custom rules, rate limiting and managed rules, so allowing an address is never a way to fix a block.
4. Find each endpoint with `search`, then tell the person exactly what will be blocked, for which zone, with which action, before calling `execute`. The person confirms each call.
5. Record what you changed: the rule or list item id, so it can be removed later. To undo, delete that rule or remove the address from the list, and say so.
6. When a call is refused for a permission, name the permission the endpoint accepts, from x-api-token-group in its entry in the specification.
