---
description: Purge all cached content for your entire zone.
title: ​Purge everything
image: https://developers.cloudflare.com/cache/how-to/purge-cache/purge-everything/og.png?v=566d209c751d82e0
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/cache/llms.txt  
> Use this file to discover all available pages before exploring further.

# ​Purge everything

Last updated Sep 29, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/cache/how-to/purge-cache/purge-everything/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

To maintain optimal site performance, Cloudflare strongly recommends using single-file (by URL) purging instead of a complete cache purge.

Purging everything instantly clears all resources from your CDN cache in all Cloudflare data centers. Each new request for a purged resource is a cache miss. Cloudflare fetches the full resource from your origin server and caches it again.

To have Cloudflare revalidate cached resources with your origin server instead, [invalidate everything](https://developers.cloudflare.com/cache/guides/invalidate-cache/). If your origin server confirms that a resource has not changed, Cloudflare reuses the cached copy.

Caution

When you purge everything, all cached content for your zone is removed at once. Every subsequent request must be served from your origin until the cache is repopulated. On high-traffic sites with many assets, this can cause a large spike in origin requests and may significantly slow down your site or overload your origin server.

Before using purge everything, consider whether a more targeted method — such as [purge by URL](https://developers.cloudflare.com/cache/how-to/purge-cache/purge-by-single-file/), [purge by prefix](https://developers.cloudflare.com/cache/how-to/purge-cache/purge_by_prefix/), or [purge by tag](https://developers.cloudflare.com/cache/how-to/purge-cache/purge-by-tags/) — can achieve the same result with less impact on your origin. If your zone uses [Tiered Cache](https://developers.cloudflare.com/cache/how-to/tiered-cache/), cache repopulation also propagates across cache tiers, which can further increase origin load during this period.

1. In the Cloudflare dashboard, go to the **Configuration** page. [Go to **Configuration** ↗](https://dash.cloudflare.com/?to=/:account/:zone/caching/configuration)
2. Under **Purge Cache**, select **Purge Everything**. A warning window appears.
3. If you agree, select **Purge Everything**.

Note

When purging everything for a non-production cache environment, all files for that specific cache environment will be purged. However, when purging everything for the production environment, all files will be purged across all environments.

For information on rate limits, refer to the [Availability and limits](https://developers.cloudflare.com/cache/how-to/purge-cache/#availability-and-limits) section.

## Resulting cache status

After you purge everything, the next request for each resource returns a `CF-Cache-Status` header of [`MISS`](https://developers.cloudflare.com/cache/concepts/cache-responses/#miss).

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/cache/how-to/purge-cache/purge-everything/#page","headline":"​Purge everything","description":"Purge all cached content for your entire zone.","url":"https://developers.cloudflare.com/cache/how-to/purge-cache/purge-everything/","inLanguage":"en","image":"https://developers.cloudflare.com/cache/how-to/purge-cache/purge-everything/og.png?v=566d209c751d82e0","dateModified":"2026-09-29","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
