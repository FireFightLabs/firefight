---
name: cloudflare_origin_errors
when: Finding why visitors get a 5xx error such as 502, 504, 520, 521, 522, 524, 525 or 526 from a site behind Cloudflare
tools: [search, execute, docs]
references: [errors/cloudflare-5xx-errors.md, errors/error-502-504.md, errors/error-520.md, errors/error-521.md, errors/error-522.md, errors/error-524.md, errors/error-525.md, errors/error-526.md]
---
1. Get the exact code, the URL and the time. Cloudflare's own guidance is that most 5xx errors are resolved at the origin, and the cause is not always in the origin's logs, so check any load balancer, cache, proxy or firewall between Cloudflare and the origin too.
2. Read what the code means, from Cloudflare's pages:
   - 520: the origin returned an empty, unknown or unexpected response, such as a crash, a firewall blocking Cloudflare's IPs, headers over 128 KB, or a broken HTTP/2 setup.
   - 521: the origin refused Cloudflare's connection, because the web server is down or Cloudflare's IPs are blocked.
   - 522: Cloudflare timed out reaching the origin, most often because Cloudflare's IP ranges are blocked or rate limited at the origin, or the origin is overloaded, or the IP in DNS is no longer the origin's.
   - 524: Cloudflare connected, but the origin sent no response within 125 seconds, usually a long running request or an overloaded origin.
   - 525: the TLS handshake with the origin failed while SSL is Full or Full (Strict), such as no certificate, port 443 closed, or no matching cipher.
   - 526: SSL is Full (Strict) and Cloudflare cannot validate the origin's certificate, such as expired, self signed or missing its intermediate certificates.
   - 502 or 504: a Cloudflare branded page means the origin returned it. A blank page without Cloudflare branding means it came from Cloudflare.
3. Check the zone's side with `execute`: the SSL/TLS mode for 525 and 526, and the DNS record's origin address for 521 and 522. Find each endpoint with `search` first.
4. Look at the origin itself with whatever else is connected, such as its logs and metrics, since that is where these errors usually start.
5. Cloudflare's temporary workaround for 520 is setting the record to DNS only, which sends visitors straight to the origin and exposes its address. Offer it as a choice for the person, never make it on your own.
6. Say which code, what it means, the evidence for the cause, and whether the fix is at the origin or in Cloudflare.
