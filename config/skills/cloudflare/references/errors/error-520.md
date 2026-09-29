---
description: Troubleshoot HTTP 520 error responses.
title: Error 520
image: https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-520/og.png?v=532c35b2983426f4
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/support/llms.txt  
> Use this file to discover all available pages before exploring further.

# Error 520

Last updated Jun 16, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-520/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

## Error 520: web server returns an unknown error

This error occurs when the origin server returns an empty, unknown, or unexpected response to Cloudflare.

### Common causes

This error is often triggered by:

- Origin server crashes or misconfigurations.
- Firewalls or security plugins blocking [Cloudflare IPs ↗︎](https://www.cloudflare.com/ips) at your origin.
- Headers exceeding 128 KB (often due to excessive cookies).
- Empty or malformed responses lacking an HTTP status code or response body.
- Missing response headers or origin web server not returning [proper HTTP error responses ↗︎](https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml).
- Incorrect HTTP/2 configuration at the origin server.
- Authentication Origin Pull enabled on Cloudflare but the origin is [not configured as expected](https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/set-up/global/#2-configure-origin-to-accept-client-certificates).

Note

`520` errors are prevalent with certain PHP applications that crash the origin web server.

### Resolution

Note

As a temporary workaround, you can set the affected DNS record to [DNS-only](https://developers.cloudflare.com/dns/proxy-status/) in the Cloudflare **DNS** app or [temporarily pause Cloudflare](https://developers.cloudflare.com/fundamentals/manage-domains/pause-cloudflare/).

- Contact your hosting provider or site administrator and share the necessary [error details](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/#required-error-details-for-hosting-provider) to assist with troubleshooting. Request a review of your origin web server error logs for crashes and check for [common causes](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-520/#common-causes) mentioned in the previous section.
- If HTTP/2 is enabled at your origin server, ensure it is correctly set up. Cloudflare connects to servers who announce support of HTTP/2 connections via [ALPN ↗︎](https://blog.cloudflare.com/introducing-http2). If the origin web server accepts the HTTP/2 connection but then does not respect or support the protocol, an HTTP `520` error will be returned. You can disable the [HTTP/2 to Origin](https://developers.cloudflare.com/speed/optimization/protocol/http2-to-origin/#disable-http2-to-origin) in **Speed** > **Settings** > **Protocol Optimization** on the Cloudflare dashboard.
- If `520` errors continue after contacting your hosting provider or site administrator, provide the following information to [Cloudflare Support](https://developers.cloudflare.com/support/contacting-cloudflare-support/):
  - Full URL(s) of the resource requested when the error occurred.
  - Cloudflare [**cf-ray**](https://developers.cloudflare.com/fundamentals/reference/cloudflare-ray-id/) from the `520` error message.
  - Output from `http://<YOUR_DOMAIN>/cdn-cgi/trace`.
  - Two [HAR files](https://developers.cloudflare.com/support/troubleshooting/general-troubleshooting/gathering-information-for-troubleshooting-sites/#generate-a-har-file):
    - One with Cloudflare enabled on your website.
    - Another with [Cloudflare temporarily disabled](https://developers.cloudflare.com/fundamentals/manage-domains/pause-cloudflare/).

## Diagnosing origin connectivity using OriginResponseStatus in logs

When reviewing Cloudflare Logs (via [Logpush](https://developers.cloudflare.com/logs/logpush/) `http_requests` dataset), the `OriginResponseStatus` field shows the HTTP status code returned by your origin.

An `OriginResponseStatus` value of **`0`** has two distinct meanings depending on context:

- **No origin contact (cache hit or revalidated response):** The request was served from cache and Cloudflare did not contact the origin. Filter these out when calculating origin error rates — they do not indicate an origin problem.
- **Failed origin connection:** Cloudflare attempted to contact the origin but received no HTTP response. The origin either dropped the TCP connection before sending response headers, timed out before sending headers, or sent a malformed response that Cloudflare could not parse. Cloudflare generates the error page itself (typically a 520 or 500).

To distinguish between the two, check the `CacheStatus` field in the same log record:

- `CacheStatus` is `hit` or `revalidated` → no origin contact; `OriginResponseStatus = 0` is expected
- `CacheStatus` is `miss` or `expired` → Cloudflare contacted the origin; `OriginResponseStatus = 0` indicates a failed connection

Caution

Do not conclude your origin returned a 5xx error solely because `OriginResponseStatus = 0`. Always check `CacheStatus` first to determine whether Cloudflare contacted the origin at all.

## Diagnose with Origin Analytics

Use [Origin Analytics](https://developers.cloudflare.com/speed/origin-analytics/) to compare what your origin returned (`originResponseStatus`) with what Cloudflare served to the end user (`edgeResponseStatus`). If your origin returned a `200` but Cloudflare served a `520`, the response was likely malformed — for example, oversized headers or an early connection close. The **Top endpoints** table can help you identify which paths are producing `520` errors.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-520/#page","headline":"Error 520","description":"Troubleshoot HTTP 520 error responses.","url":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-520/","inLanguage":"en","image":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-520/og.png?v=532c35b2983426f4","dateModified":"2026-06-16","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
