---
name: cloudflare_cache
when: Fixing stale content after a deploy, purging Cloudflare's cache, or finding why a page is never cached
tools: [get_resource_map, resource_status, search, execute, docs]
references: [cache/purge-cache.md, cache/purge-by-single-file.md, cache/purge-by-prefix.md, cache/purge-by-hostname.md, cache/purge-everything.md, cache/investigating-uncached-responses.md]
---
Start from the zone on the resource map. `get_resource_map` with the domain names the Cloudflare account that holds it and its id, which is the zone id every endpoint takes, and `resource_status` with the domain reads the zone from Cloudflare. Both only read, so the person is not asked. Find a zone with `execute` only when the map does not have it.

1. For stale content, purge as narrowly as possible. Cloudflare recommends purging by URL. Purging by prefix or hostname clears a section, and purging everything clears the whole zone at once, which sends every request to the origin until the cache fills again and can overload a busy origin. Name the scope and its effect to the person before they confirm.
2. Find the purge endpoint with `search`, then call it with `execute`. Purge requests are rate limited per account, by plan.
3. A successful purge only means Cloudflare accepted it. Check the next response for the URL: a CF-Cache-Status of MISS shows it was purged.
4. Purging by URL may not clear content when a custom cache key includes headers or cookies, or when a cache rule only matches GET requests. Purge by prefix or tag instead. Purging a URL that redirects clears the redirect, not the page it points to.
5. For a page that is never cached, read its CF-Cache-Status:
   - DYNAMIC: not eligible for cache, such as a file type that is not cached by default, a rule that bypasses cache, a method other than GET or HEAD, or Development Mode on.
   - BYPASS: eligible, but the origin prevented it, such as Cache-Control no-store or private, a Set-Cookie header, or a response over the size limit.
   - MISS on every request: cacheable, but not staying in cache.
6. When a call is refused for a permission, name the permission the endpoint accepts, from x-api-token-group in its entry in the specification.
