---
description: Turn on Cloudflare Under Attack mode to mitigate layer 7 DDoS attacks by challenging suspicious visitors with an interstitial page.
title: Under Attack mode
image: https://developers.cloudflare.com/fundamentals/reference/under-attack-mode/og.png?v=0c4b44ccab2849b6
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/fundamentals/llms.txt  
> Use this file to discover all available pages before exploring further.

# Under Attack mode

Last updated Apr 20, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/fundamentals/reference/under-attack-mode/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

Cloudflare's Under Attack mode performs additional security checks to help mitigate layer 7 DDoS attacks. Validated users access your website and suspicious traffic is blocked. It is designed to be used as one of the last resorts when a zone is under attack (and will temporarily pause access to your site and impact your site analytics).

When enabled, visitors receive an interstitial page.

## Turn on Under Attack mode

Under Attack mode is turned off by default for your zone.

### Globally

To put your entire zone in Under Attack mode:

1. In the Cloudflare dashboard, select your account and zone from the **Account home** page. [Go to **Account home** ↗](https://dash.cloudflare.com/?to=/:account/home)
2. In the zone overview page, turn on **Under Attack Mode** in the **Quick Actions** sidebar.

### Selectively

To enable Under Attack mode for specific pages or sections of your site, use a [configuration rule](https://developers.cloudflare.com/rules/configuration-rules/) to adjust the **Security Level**.

**When incoming requests match**

- **Field:** *URI Path*
- **Operator:** *starts with*
- **Value:** `/admin`

If you are using the Expression Editor, enter the following expression:  
`(starts_with(http.request.uri.path, "/admin"))`

**Then the settings are**

1. For **I'm Under Attack**, select **Add**.
2. Switch the toggle to **On**.

To turn it on for specific ASNs (hosts/ISPs that own IP addresses), countries, or IP ranges, use [IP Access Rules](https://developers.cloudflare.com/waf/tools/ip-access-rules/).

---

## Preview Under Attack mode

To preview what Under Attack mode looks like for your visitors:

1. In the Cloudflare dashboard, go to the **Configurations** page. [Go to **Configurations** ↗](https://dash.cloudflare.com/?to=/:account/configurations)
2. Go to **Custom Pages**.
3. For **Managed Challenge / I'm Under Attack Mode™**, select **Custom Pages** > **View default**.

The `Checking your browser before accessing...` challenge determines whether to block or allow a visitor within five seconds. After passing the challenge, the visitor does not observe another challenge until the duration configured in [Challenge Passage](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/challenge-passage/).

---

## Potential issues

Since the Under Attack mode requires your browser to support JavaScript to display and pass the interstitial page, it is expected to observe impact on third party analytics tools.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/fundamentals/reference/under-attack-mode/#page","headline":"Under Attack mode","description":"Turn on Cloudflare Under Attack mode to mitigate layer 7 DDoS attacks by challenging suspicious visitors with an interstitial page.","url":"https://developers.cloudflare.com/fundamentals/reference/under-attack-mode/","inLanguage":"en","image":"https://developers.cloudflare.com/fundamentals/reference/under-attack-mode/og.png?v=0c4b44ccab2849b6","dateModified":"2026-04-20","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
