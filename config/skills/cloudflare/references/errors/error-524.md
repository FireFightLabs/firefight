---
description: Troubleshoot HTTP 524 error responses.
title: Error 524
image: https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-524/og.png?v=3ebab54abd6fa1ff
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/support/llms.txt  
> Use this file to discover all available pages before exploring further.

# Error 524

Last updated Jul 23, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-524/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

## Error 524: a timeout occurred

Error `524` indicates that Cloudflare successfully connected to the origin web server, but the origin did not provide an HTTP response before the default 125 seconds [Proxy Read Timeout](https://developers.cloudflare.com/fundamentals/reference/connection-limits/).

### Common causes

This can happen if the origin server is taking too long because it has too much work to do, for example, a large data query, or because the server is struggling for resources and cannot return any data in time. The error `524` occurs if the origin web server acknowledges (ACK) the resource request after the connection has been established, but does not send a timely response (within the [Proxy Read Timeout](https://developers.cloudflare.com/fundamentals/reference/connection-limits/) delay, 125 seconds by default).

Error `524` can also indicate that Cloudflare successfully connected to the origin web server to write data, but the write did not complete before the 30 seconds [Proxy Write Timeout](https://developers.cloudflare.com/fundamentals/reference/connection-limits/) (or 6.5 seconds in the case of [Cloudflare Images](https://developers.cloudflare.com/images/)). This timeout cannot be adjusted.

### Resolution at your origin

Here are the options we suggest to work around this issue:

- [Contact your hosting provider](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/#required-error-details-for-hosting-provider) to exclude the following common causes at your origin web server:
  - A long-running process on the origin web server.
  - An overloaded origin web server.
- Implement status polling of large HTTP processes to avoid hitting this error.

Note

Logging request response time at your origin web server may help identify the cause of resource slowness. Contact your hosting provider or site administrator for assistance in adjusting log formats or search for related logging documentation for your brand of web server such as [Apache ↗︎](http://httpd.apache.org/docs/current/mod/mod_log_config.html) or [Nginx ↗︎](http://nginx.org/en/docs/http/ngx_http_log_module.html#log_format).

### Resolution on Cloudflare

Here are some other actions you can take on the Cloudflare side:

- If you regularly run HTTP requests that take over 125 seconds to complete (for example, large data exports), move those processes behind a [subdomain not proxied (DNS-only, grey clouded)](https://developers.cloudflare.com/dns/proxy-status/#dns-only-records) in the Cloudflare **DNS** app.
- Enterprise customers can increase the `524` timeout up to 6,000 seconds:
  - If your content can be cached, you can create a [Cache Rule](https://developers.cloudflare.com/cache/how-to/cache-rules/settings/#proxy-read-timeout-enterprise-only) with the `Proxy Read Timeout` setting. The content needs to be cacheable for the rule to be triggered, but does not need to be cached.
  - You can increase the `proxy_read_timeout` setting for the whole zone using the [Edit zone setting API endpoint](https://developers.cloudflare.com/api/resources/zones/subresources/settings/methods/edit/).

Note

Note that you may observe a 1 second difference between the timeout you have set and the actual time at which the Error `524` is returned. This is expected, it is due to the current work on implementing our proxy - [Pingora ↗︎](https://blog.cloudflare.com/how-we-built-pingora-the-proxy-that-connects-cloudflare-to-the-internet/). As a workaround, you can simply set the timeout to one second more (126 seconds instead of 125 seconds, for example).

### Diagnose with Origin Analytics

Use [Origin Analytics](https://developers.cloudflare.com/speed/origin-analytics/) to monitor origin response times and catch requests approaching your timeout threshold before they result in `524` errors. If P95 response times are near the [Proxy Read Timeout](https://developers.cloudflare.com/fundamentals/reference/connection-limits/), identify the slow paths in the **Top endpoints** table and optimize them — or increase the timeout for Enterprise zones.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-524/#page","headline":"Error 524","description":"Troubleshoot HTTP 524 error responses.","url":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-524/","inLanguage":"en","image":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-524/og.png?v=3ebab54abd6fa1ff","dateModified":"2026-07-23","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
