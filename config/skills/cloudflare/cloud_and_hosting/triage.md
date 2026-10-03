---
name: cloudflare_triage
when: Any question about a domain or zone on Cloudflare, such as checking its configuration or anything wrong with a site behind it, and how to reach the Cloudflare API at all
tools: [search, execute, docs]
references: [mcp/cloudflare-api-mcp.md, errors/cloudflare-5xx-errors.md, origin/traffic-flow.md]
---
How the Cloudflare tools work: `search` runs JavaScript against the Cloudflare API's own specification (spec.paths) to find the endpoint for a task, and `execute` runs JavaScript that calls it with cloudflare.request({ method, path, body }). Always find the endpoint with `search` before calling it, rather than writing a path from memory. When the connection belongs to a person rather than an account, pass `account_id` to `execute`. `docs` searches Cloudflare's documentation. Every call to `execute` asks the person to confirm it, so read before you change anything, and say what a change will do before you make it.

1. Find the zone for the domain the person named, with `execute` calling the endpoint that lists zones. Everything else is per zone, by its zone id.
2. Decide where the failure is. A Cloudflare branded error page with a code such as 520 to 526 means Cloudflare could not get a good answer from the origin. Filtering HTTP traffic analytics by edge status code and by origin status code separates errors Cloudflare returned from errors the origin returned. Then load the skill that fits: cloudflare_origin_errors for 5xx, cloudflare_attack for a traffic spike or attack, cloudflare_block to block or challenge traffic, cloudflare_cache for stale or uncached content, cloudflare_dns for records.
3. When Cloudflare refuses a call for a missing permission, read the permissions that endpoint accepts from its entry in the specification, which lists them under x-api-token-group, and say which one the connection needs. The person grants it by connecting Cloudflare again and picking it on Cloudflare's consent screen.
