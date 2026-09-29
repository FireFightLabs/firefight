---
description: Allow traffic only from IP addresses in an allowlist.
title: Allow traffic from IP addresses in allowlist only
image: https://developers.cloudflare.com/waf/custom-rules/use-cases/allow-traffic-from-ips-in-allowlist/og.png?v=971dde0d89bce517
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/waf/llms.txt  
> Use this file to discover all available pages before exploring further.

# Allow traffic from IP addresses in allowlist only

Last updated Apr 16, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/waf/custom-rules/use-cases/allow-traffic-from-ips-in-allowlist/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

This example blocks incoming requests from IP addresses that are not present in an allowlist (defined using an [IP list](https://developers.cloudflare.com/waf/tools/lists/custom-lists/#ip-lists)).

1. [Create an IP list](https://developers.cloudflare.com/waf/tools/lists/create-dashboard/) with the IP addresses for which you want to allow access.  
    For example, create an IP list named `allowed_ips` with one or more IP addresses. For more information on the accepted IP address formats, refer to [IP lists](https://developers.cloudflare.com/waf/tools/lists/custom-lists/#ip-lists).
2. [Create a custom rule](https://developers.cloudflare.com/waf/custom-rules/create-dashboard/) blocking any requests from IPs not present in the list you created ( `allowed_ips` in the current example).
   - **When incoming requests match**:

     | Field | Operator | Value |
     | --- | --- | --- |
     | IP Source Address | is not in list | `allowed_ips` |

     If you are using the expression editor:  
     `(not ip.src in $allowed_ips)`
   - **Then take action**: *Block*
3. (Optional) Update your expression with any extra filters, like blocking non-allowlisted IPs only for specific URI paths:

   | Field | Operator | Value | Logic |
   | --- | --- | --- | --- |
   | IP Source Address | is not in list | `allowed_ips` | And |
   | URI Path | wildcard | `/admin/*` |  |

   If you are using the expression editor:  
   `(not ip.src in $allowed_ips and http.request.uri.path wildcard "/admin/*")`

## Other resources

- [Use case: Require known IP addresses in site admin area](https://developers.cloudflare.com/waf/custom-rules/use-cases/site-admin-only-known-ips/)
- [Available skip options](https://developers.cloudflare.com/waf/custom-rules/skip/options/)

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/waf/custom-rules/use-cases/allow-traffic-from-ips-in-allowlist/#page","headline":"Allow traffic from IP addresses in allowlist only","description":"Allow traffic only from IP addresses in an allowlist.","url":"https://developers.cloudflare.com/waf/custom-rules/use-cases/allow-traffic-from-ips-in-allowlist/","inLanguage":"en","image":"https://developers.cloudflare.com/waf/custom-rules/use-cases/allow-traffic-from-ips-in-allowlist/og.png?v=971dde0d89bce517","dateModified":"2026-04-16","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
