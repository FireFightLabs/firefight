---
description: Set the Security Level threshold for challenging suspicious visitors.
title: Security Level
image: https://developers.cloudflare.com/waf/tools/security-level/og.png?v=cb57e42a09c54404
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/waf/llms.txt  
> Use this file to discover all available pages before exploring further.

# Security Level

Last updated Apr 16, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/waf/tools/security-level/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

In the old Cloudflare dashboard, security level has the value *Always protected* and you cannot change this setting. To turn [Under Attack mode](https://developers.cloudflare.com/fundamentals/reference/under-attack-mode/) on or off, use the separate toggle.

In the new security dashboard, the Cloudflare API, and in Terraform, use security level to turn Under Attack mode on or off.

Cloudflare's [Under Attack mode](https://developers.cloudflare.com/fundamentals/reference/under-attack-mode/) performs additional security checks to help mitigate layer 7 DDoS attacks. When you enable Under Attack mode, Cloudflare will present a Managed Challenge page.

Caution

Only use [Under Attack mode](https://developers.cloudflare.com/fundamentals/reference/under-attack-mode/) when a website is under a DDoS attack. Under Attack mode may affect some actions on your domain, such as your API traffic.

To enable or disable Under Attack mode for your API or any other part of your domain, create a [configuration rule](https://developers.cloudflare.com/rules/configuration-rules/).

## Threat score

Previously, a threat score represented a Cloudflare threat score from 0–100, where 0 indicates low risk. Now, the threat score is always `0` (zero).

Recommendation

Currently we do not recommend creating rules based on the threat score, since this score is no longer being populated.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/waf/tools/security-level/#page","headline":"Security Level","description":"Set the Security Level threshold for challenging suspicious visitors.","url":"https://developers.cloudflare.com/waf/tools/security-level/","inLanguage":"en","image":"https://developers.cloudflare.com/waf/tools/security-level/og.png?v=cb57e42a09c54404","dateModified":"2026-04-16","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
