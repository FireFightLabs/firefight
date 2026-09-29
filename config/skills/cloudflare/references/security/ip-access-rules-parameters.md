---
description: Configurable parameters for IP Access rules.
title: IP Access rules parameters
image: https://developers.cloudflare.com/waf/tools/ip-access-rules/parameters/og.png?v=7af807c4b5f360d4
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/waf/llms.txt  
> Use this file to discover all available pages before exploring further.

# IP Access rules parameters

Last updated May 5, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/waf/tools/ip-access-rules/parameters/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

An IP Access rule will apply a certain action to incoming traffic based on the visitor's IP address, IP range, Autonomous System Number (ASN), or country.

## IP address

| Type | Example value |
| --- | --- |
| IPv4 address | `192.0.2.3` |
| IPv6 address | `2001:db8::` |

## IP range

| Type | Example value | Start of range | End of range | Number of addresses |
| --- | --- | --- | --- | --- |
| IPv4 `/24` range | `192.0.2.0/24` | `192.0.2.0` | `192.0.2.255` | 256 |
| IPv4 `/16` range | `192.168.0.0/16` | `192.168.0.0` | `192.168.255.255` | 65,536 |
| IPv6 `/128` range | `2001:db8::/128` | `2001:db8::` | `2001:db8::` | 1 |
| IPv6 `/64` range | `2001:db8::/64` | `2001:db8::` | `2001:db8:0000:0000:ffff:ffff:ffff:ffff` | 18,446,744,073,709,551,616 |
| IPv6 `/48` range | `2001:db8::/48` | `2001:db8::` | `2001:db8:0000:ffff:ffff:ffff:ffff:ffff` | 1,208,925,819,614,629,174,706,176 |
| IPv6 `/32` range | `2001:db8::/32` | `2001:db8::` | `2001:db8:ffff:ffff:ffff:ffff:ffff:ffff` | 79,228,162,514,264,337,593,543,950,336 |

## Autonomous System Number (ASN)

| Type | Example value |
| --- | --- |
| ASN | `AS13335` |

## Country

Specify a country using two-letter [ISO-3166-1 alpha-2 codes ↗︎](https://www.iso.org/iso-3166-country-codes.html). Additionally, the Cloudflare dashboard accepts country names. For example:

- `US`
- `CN`
- `germany` (dashboard only)

Cloudflare uses the following special country alpha-2 codes that are not part of the ISO:

- `T1`: [Tor exit nodes](https://developers.cloudflare.com/network/onion-routing/) (country name: `Tor`)
- `XX`: Unknown/reserved

Notes

Country block is only available on Enterprise plans.

IP addresses globally allowed by Cloudflare will override a country block via IP Access rules, but they will not override a country block via [custom rules](https://developers.cloudflare.com/waf/custom-rules/).

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/waf/tools/ip-access-rules/parameters/#page","headline":"IP Access rules parameters","description":"Configurable parameters for IP Access rules.","url":"https://developers.cloudflare.com/waf/tools/ip-access-rules/parameters/","inLanguage":"en","image":"https://developers.cloudflare.com/waf/tools/ip-access-rules/parameters/og.png?v=7af807c4b5f360d4","dateModified":"2026-05-05","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"},"keywords":["IPv4","IPv6","Geolocation"]}
```
