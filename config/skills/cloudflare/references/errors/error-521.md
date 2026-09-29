---
description: Troubleshoot HTTP 521 error responses.
title: Error 521
image: https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-521/og.png?v=978d7a0c32685b96
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/support/llms.txt  
> Use this file to discover all available pages before exploring further.

# Error 521

Last updated Apr 23, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-521/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

## Error 521: web server is down

Error `521` occurs when the origin web server refuses connections from Cloudflare. Security solutions at your origin may block legitimate connections from certain [Cloudflare IP addresses ↗︎](https://www.cloudflare.com/ips).

### Common causes

The two most common causes of `521` errors are:

- Offlined origin web server application.
- Blocked Cloudflare requests.

### Resolution

Contact your hosting provider or site administrator and share the necessary [error details](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/#required-error-details-for-hosting-provider) to assist in troubleshooting these common causes:

- Ensure your origin web server is responsive.
- Review origin web server error logs to identify web server application crashes or outages.
- Confirm [Cloudflare IP addresses ↗︎](https://www.cloudflare.com/ips) are not blocked or rate limited.
- Allow all [Cloudflare IP ranges ↗︎](https://www.cloudflare.com/ips) in your origin web server's firewall or other security software.
- Confirm that — if you have your **SSL/TLS mode** set to **Full** or **Full (Strict**) — your origin supports HTTPS and/or you have installed a [Cloudflare Origin Certificate](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca) or a certificate matching the [requirements for these modes](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/#custom-ssltls).
- Ensure that your origin web server application is actively bound and listening on the port required by your SSL/TLS mode: Port 80 for **Flexible**, or Port 443 for **Full** and **Full (Strict)**.
- Find additional troubleshooting information on the [Cloudflare Community ↗︎](https://community.cloudflare.com/t/community-tip-fixing-error-521-web-server-is-down/42461).

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-521/#page","headline":"Error 521","description":"Troubleshoot HTTP 521 error responses.","url":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-521/","inLanguage":"en","image":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-521/og.png?v=978d7a0c32685b96","dateModified":"2026-04-23","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
