---
description: Troubleshoot Cloudflare 5xx server error codes.
title: Cloudflare 5xx errors
image: https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/og.png?v=8136c131a255594f
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/support/llms.txt  
> Use this file to discover all available pages before exploring further.

# Cloudflare 5xx errors

Last updated Jun 5, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

When troubleshooting most `5XX` errors, the correct course of action is to first contact your hosting provider or site administrator to troubleshoot and gather data. The following sections outline:

- The [information](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/#required-error-details-for-hosting-provider) to provide your hosting provider to help resolve the errors
- The steps to access [error analytics](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/#error-analytics) in the Cloudflare dashboard.

Note

Cloudflare Support only assists the domain owner to resolve issues. If you are a site visitor, report the problem to the site owner.

### Required error details for hosting provider

When contacting your hosting provider, share the following information:

- The specific `5XX` error code and message.
- The time and timezone when the `5XX` error occurred.
- The URL that resulted in the HTTP `5XX` error (for example, `https://www.example.com/images/icons/image1.png`).

The cause of the error is not always found in the origin server's error logs. Be sure to check the logs of any load balancers, caches, proxies, or firewalls between Cloudflare and the origin web server.

Additional details to provide to your hosting provider or site administrator can be found in the error descriptions below. Note that Cloudflare [Custom Errors](https://developers.cloudflare.com/rules/custom-errors/) can alter the appearance of default error pages discussed in this page.

### Error analytics

Error analytics per domain are available within [Zone Analytics](https://developers.cloudflare.com/analytics/account-and-zone-analytics/zone-analytics/). Error analytics provides insights into overall errors by HTTP error code and offers details such as the URLs, source IP addresses, and Cloudflare data centers needed to diagnose and resolve issues. Error Analytics are based on a 1% traffic sample.

To view Error Analytics:

1. In the Cloudflare dashboard, go to the **HTTP Traffic** page. [Go to **HTTP Traffic** ↗](https://dash.cloudflare.com/?to=/:account/:zone/analytics/traffic)
2. Select **Add filter**, select **Edge status code** or **Origin status code** and choose any `5xx` error code that you want to diagnose.

### Log Explorer

[Log Explorer](https://developers.cloudflare.com/log-explorer/) provides access to Cloudflare logs with all the context available within the Cloudflare platform. You can monitor security and performance issues with custom dashboards or investigate and troubleshoot issues with log search. Log explorer [allows you to build queries](https://developers.cloudflare.com/log-explorer/log-search/) filtering for a specific Ray ID, which can be useful to investigate HTTP Errors.

---

## Error 500: internal server error

For a complete description of this error refer to the [Error 500](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-500/) page.

## Error 501: not implemented

For a complete description of this error refer to the [Error 501](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-501/) page.

## Error 502 bad gateway or error 504 gateway timeout

For a complete description of this error refer to the [Error 502/504](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-502-504/) page.

## Error 503: service temporarily unavailable

For a complete description of this error refer to the [Error 503](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-503/) page.

## Error 520: web server returns an unknown error

For a complete description of this error refer to the [Error 520](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-520/) page.

## Error 521: web server is down

For a complete description of this error refer to the [Error 521](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-521/) page.

## Error 522: connection timed out

For a complete description of this error refer to the [Error 522](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-522/) page.

## Error 523: origin is unreachable

For a complete description of this error refer to the [Error 523](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-523/) page.

## Error 524: a timeout occurred

For a complete description of this error refer to the [Error 524](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-524/) page.

## Error 525: SSL handshake failed

For a complete description of this error refer to the [Error 525](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-525/) page.

## Error 526: invalid SSL certificate

For a complete description of this error refer to the [Error 526](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-526/) page.

## Error 530

For a complete description of this error refer to the [Error 530](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-530/) page.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/#page","headline":"Cloudflare 5xx errors","description":"Troubleshoot Cloudflare 5xx server error codes.","url":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/","inLanguage":"en","image":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/og.png?v=8136c131a255594f","dateModified":"2026-06-05","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
