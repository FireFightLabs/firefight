---
description: Understand Cloudflare API rate limits, rate-limiting headers, and how to handle throttled requests.
title: Rate limits
image: https://developers.cloudflare.com/fundamentals/api/reference/limits/og.png?v=59449a1fef851e76
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/fundamentals/llms.txt  
> Use this file to discover all available pages before exploring further.

# Rate limits

Last updated Aug 25, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/fundamentals/api/reference/limits/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

## API token limits

| Type | Limit |
| --- | --- |
| Client API per user/account token | 1200/5 minutes |
| Client API per IP | 200/second |
| GraphQL | Varies by query cost. Max 320/5 min |
| User API tokens per user | 50 |
| Account API tokens per account | 500 |

Note

The global rate limit for the Cloudflare API is 1,200 requests per five minute period per user, and applies cumulatively regardless of whether the request is made via the dashboard, API key, or API token.

If you exceed this limit, all API calls for the next five minutes will be blocked, receiving a `HTTP 429 - Too Many Requests` response.

Some specific API calls have their own limits and are documented separately, such as the following:

- [Cache Purge APIs](https://developers.cloudflare.com/cache/how-to/purge-cache/#availability-and-limits)
- [GraphQL APIs](https://developers.cloudflare.com/analytics/graphql-api/limits/)
- [Rulesets APIs](https://developers.cloudflare.com/ruleset-engine/rulesets-api/#limits)
- [Lists API](https://developers.cloudflare.com/waf/tools/lists/lists-api/#rate-limiting-for-lists-api-requests)
- [Gateway Lists API](https://developers.cloudflare.com/cloudflare-one/reusable-components/lists/#api-rate-limit)

Enterprise customers can also [contact Cloudflare Support](https://developers.cloudflare.com/support/contacting-cloudflare-support/) to raise the Client API per user, GraphQL, or API token limits to a higher value.

## Rate limiting headers

The following headers are returned when calling REST APIs:

- `Ratelimit`: List of service limit items, composed of the limit name, the remaining quota ( `r`) and the time next window resets ( `t`). For example: `"default";r=50;t=30`
- `Ratelimit-Policy`: List of quota policy items, composed of the policy name, the total quota ( `q`) and the time window the quota applies to ( `w`). For example: `"burst";q=100;w=60`
- `retry-after`: The number of seconds, rounded up, until more capacity is available. Note, this header is only returned when the request has exceeded the rate limit.

[Cloudflare's SDKs](https://developers.cloudflare.com/fundamentals/api/reference/sdks/) will also automatically work with the headers and back off in response to rate limits.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/fundamentals/api/reference/limits/#page","headline":"Rate limits","description":"Understand Cloudflare API rate limits, rate-limiting headers, and how to handle throttled requests.","url":"https://developers.cloudflare.com/fundamentals/api/reference/limits/","inLanguage":"en","image":"https://developers.cloudflare.com/fundamentals/api/reference/limits/og.png?v=59449a1fef851e76","dateModified":"2026-08-25","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
