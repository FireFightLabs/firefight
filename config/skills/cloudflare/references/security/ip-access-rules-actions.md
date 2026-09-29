---
description: Available actions for IP Access rules.
title: IP Access rules actions
image: https://developers.cloudflare.com/waf/tools/ip-access-rules/actions/og.png?v=91fc775d738f2cc6
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/waf/llms.txt  
> Use this file to discover all available pages before exploring further.

# IP Access rules actions

Last updated Apr 16, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/waf/tools/ip-access-rules/actions/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

An IP Access rule can perform one of the following actions:

- **Block**: Prevents a visitor from visiting your site.
- **Allow**: Excludes visitors from all security checks, including [Browser Integrity Check](https://developers.cloudflare.com/waf/tools/browser-integrity-check/), [Under Attack mode](https://developers.cloudflare.com/fundamentals/reference/under-attack-mode/), and the WAF. Use this option when a trusted visitor is being blocked by Cloudflare's default security features. The *Allow* action takes precedence over the *Block* action.  
  Allowing a given country code will not bypass WAF managed rules (previous and new versions). Refer to [Important remarks about allowing/blocking by country](https://developers.cloudflare.com/waf/tools/ip-access-rules/#important-remarks-about-allowingblocking-by-country) for more information.
- **Managed Challenge**: Depending on the characteristics of a request, Cloudflare will dynamically choose the appropriate type of challenge from a list of possible actions. For more information, refer to [Interstitial Challenge Pages](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/#managed-challenge).
- **Non-Interactive Challenge**: Presents a non-interactive challenge page to visitors. Prevents bots from accessing the site.
- **Interactive Challenge**: Requires the visitor to complete an interactive challenge before visiting your site. Prevents bots from accessing the site.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/waf/tools/ip-access-rules/actions/#page","headline":"IP Access rules actions","description":"Available actions for IP Access rules.","url":"https://developers.cloudflare.com/waf/tools/ip-access-rules/actions/","inLanguage":"en","image":"https://developers.cloudflare.com/waf/tools/ip-access-rules/actions/og.png?v=91fc775d738f2cc6","dateModified":"2026-04-16","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
