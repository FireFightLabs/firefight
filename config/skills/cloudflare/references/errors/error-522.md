---
description: Troubleshoot HTTP 522 error responses.
title: Error 522
image: https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-522/og.png?v=11988c8bef091bb8
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/support/llms.txt  
> Use this file to discover all available pages before exploring further.

# Error 522

Last updated Jul 31, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-522/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

## Error 522: connection timed out

Error `522` occurs when Cloudflare times out contacting the origin web server.

### Common causes

Two different timeouts cause HTTP error `522` depending on when they occur between Cloudflare and the origin web server:

- Before a TCP connection is established, Cloudflare does not receive a SYN+ACK within 19 seconds after sending a SYN. The SYN retry backoff intervals are 1, 1, 1, 1, 1, 2, 4, and 8 seconds.
- After the TCP connection is established, Cloudflare does not receive an acknowledgment (ACK) of its resource request within 90 seconds.

### Resolution

- Contact your hosting provider and share the [error details](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/#required-error-details-for-hosting-provider) to assist in troubleshooting these common causes:
  - [Cloudflare IP addresses ↗︎](https://www.cloudflare.com/ips/) are rate limited or blocked in .htaccess, iptables, or firewalls. Confirm your hosting provider allows **all Cloudflare IP ranges** (most common cause). You can use a [Cloudflare WAF Custom Rule](https://developers.cloudflare.com/waf/custom-rules/use-cases/block-by-geographical-location/) if you need to restrict traffic from geographical locations.
  - An overloaded or offline origin web server drops incoming requests.
  - [Keepalives ↗︎](http://tldp.org/HOWTO/TCP-Keepalive-HOWTO/overview.html) are disabled at the origin web server.
  - The origin IP address in your Cloudflare **DNS** app does not match the IP address currently provisioned to your origin web server by your hosting provider.
  - Packets were dropped at your origin web server.
- If you are using [Cloudflare Pages](https://developers.cloudflare.com/pages/), verify that you have a custom domain set up and that your CNAME record is pointed to your [custom Pages domain](https://developers.cloudflare.com/pages/configuration/custom-domains/#add-a-custom-domain).
- If you are using [Workers with a Custom Domain](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/), performing a `fetch` to its own hostname will cause a `522` error. Consider using a [Route](https://developers.cloudflare.com/workers/configuration/routing/), targeting another hostname, or enabling the [`global_fetch_strictly_public` compatibility flag](https://developers.cloudflare.com/workers/configuration/compatibility-flags/#global-fetch-strictly-public) instead.
- If you are using [Origin Rules](https://developers.cloudflare.com/rules/origin-rules/), make sure the resulting hostname can be resolved. For example, if your Origin Rule point to a Worker route, a `522` error will be returned if the hostname for this route is an A record pointing to a reserved address such as `100::` or `192.0.2.0`.
- If none of the above leads to a resolution, request the following information from your hosting provider or site administrator before [contacting Cloudflare support](https://developers.cloudflare.com/support/contacting-cloudflare-support/):
  - An [MTR or traceroute](https://developers.cloudflare.com/support/troubleshooting/general-troubleshooting/gathering-information-for-troubleshooting-sites/#perform-a-traceroute) from your origin web server to a [Cloudflare IP address ↗︎](http://www.cloudflare.com/ips) that most commonly connected to your origin web server before the issue occurred. Identify a connecting Cloudflare IP recorded in the origin web server logs.
  - Details from the hosting provider's investigation, such as pertinent logs or conversations with the hosting provider.

### Diagnose with Origin Analytics

Use [Origin Analytics](https://developers.cloudflare.com/speed/origin-analytics/) to check for TCP connection failures to your origin. If the **Top endpoints** table shows a high TCP failure rate for specific paths, the issue may be path-specific rather than a general origin problem. Origin Analytics can also help confirm whether your origin is reachable from Cloudflare's edge.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-522/#page","headline":"Error 522","description":"Troubleshoot HTTP 522 error responses.","url":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-522/","inLanguage":"en","image":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-522/og.png?v=11988c8bef091bb8","dateModified":"2026-07-31","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
