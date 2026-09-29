---
description: Purge all cached resources for a specific hostname.
title: ​Purge cache by hostname
image: https://developers.cloudflare.com/cache/how-to/purge-cache/purge-by-hostname/og.png?v=d029c877b2a8fd25
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/cache/llms.txt  
> Use this file to discover all available pages before exploring further.

# ​Purge cache by hostname

Last updated Aug 21, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/cache/how-to/purge-cache/purge-by-hostname/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

Purging by hostname means that all assets at URLs with a host that matches one of the provided values will be instantly purged from the cache.

1. In the Cloudflare dashboard, go to the **Configuration** page. [Go to **Configuration** ↗](https://dash.cloudflare.com/?to=/:account/:zone/caching/configuration)
2. Under **Purge Cache**, select **Custom Purge**. The **Custom Purge** window appears.
3. Under **Purge by**, select **Hostname**.
4. Follow the syntax instructions:
   - One hostname per line.
   - Separated by commas.
   - You can purge up to 100 hostnames at a time.
5. Enter the appropriate value(s) in the text field using the format shown in the example.
6. Select **Purge**.

For information on rate limits, refer to the [Availability and limits](https://developers.cloudflare.com/cache/how-to/purge-cache/#availability-and-limits) section.

## Resulting cache status

Purging by hostname deletes the resource, resulting in the `CF-Cache-Status` header being set to [`MISS`](https://developers.cloudflare.com/cache/concepts/cache-responses/#miss) for subsequent requests.

If [tiered cache](https://developers.cloudflare.com/cache/how-to/tiered-cache/) is used, purging by hostname may return `EXPIRED`, as the lower tier tries to revalidate with the upper tier to reduce load on the latter. Depending on whether the upper tier has the resource or not, and whether the end user is reaching the lower tier or the upper tier, `EXPIRED` or `MISS` are returned.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/cache/how-to/purge-cache/purge-by-hostname/#page","headline":"​Purge cache by hostname","description":"Purge all cached resources for a specific hostname.","url":"https://developers.cloudflare.com/cache/how-to/purge-cache/purge-by-hostname/","inLanguage":"en","image":"https://developers.cloudflare.com/cache/how-to/purge-cache/purge-by-hostname/og.png?v=d029c877b2a8fd25","dateModified":"2026-08-21","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
