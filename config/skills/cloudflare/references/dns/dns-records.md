---
description: Manage DNS records for your Cloudflare zones.
title: DNS records
image: https://developers.cloudflare.com/dns/manage-dns-records/og.png?v=ffb273d81e8354c9
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/dns/llms.txt  
> Use this file to discover all available pages before exploring further.

# DNS records

Last updated Aug 14, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/dns/manage-dns-records/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

DNS records contain information about your domain and are used to make your website or application available to visitors and other web services.

Each DNS record belongs to a different type, and each type serves a different purpose. For background about the different types of DNS records, refer to the [Learning Center ↗︎](https://www.cloudflare.com/learning/dns/dns-records/). To quickly find reference information about a specific type, refer to [DNS record types](https://developers.cloudflare.com/dns/manage-dns-records/reference/dns-record-types/).

Depending on the providers you used to [get your domain name](https://developers.cloudflare.com/fundamentals/manage-domains/#get-a-domain-name) and [host your website or application](https://developers.cloudflare.com/fundamentals/manage-domains/#host-your-domain), it is expected that DNS records were automatically created on your behalf. According to your [setup](https://developers.cloudflare.com/dns/zone-setups/), you can use Cloudflare to manage your DNS records.

## DNS records table

When managing your records at Cloudflare, besides the common record fields described below, you may also find an option for [Proxy status](https://developers.cloudflare.com/dns/proxy-status/) and [CNAME flattening](https://developers.cloudflare.com/dns/cname-flattening/). These are specific features offered by Cloudflare.

<details>

<summary>

Record fields

</summary>

- **Type**: Defines the purpose of a record. Different types of record require different information in their corresponding <code>Content</code> field. - **Name**: Identifies the resource that the record resolves to. Depending on the purpose of the record, the value you want to add to this field will also change. - **Content**: Contains the core value of a record, depending on the record type. - **TTL**: Controls how long each record is cached by DNS resolvers.

</details>

<details>

<summary>

Example

</summary>

DNS management for **example.com**:

| Type | Name | Content | Proxy status | TTL |
| --- | --- | --- | --- | --- |
| A | <code>blog</code> | <code>192.0.2.1</code> | Proxied | Auto |

In this example, an IP address resolution record of type <code>A</code> is indicating that the resources that correspond to the subdomain <code>blog.example.com</code> can be reached on the IPv4 address <code>192.0.2.1</code>.

Also, as this record is <a href="https://developers.cloudflare.com/dns/proxy-status/">proxied</a>, Cloudflare automatically defines for how long this information should be cached by DNS resolvers.

</details>

## DNS records quota

Cloudflare limits the number of DNS records you can create. Depending on your plan, this limit is enforced either per zone or per account — not both.

DNS records that other Cloudflare services create on your behalf — for example, the `TXT` and `MX` records added by [Email Routing](https://developers.cloudflare.com/email-service/) — also count toward your quota. To avoid disrupting those services, they are enforced against your record limit with a small buffer, so a zone may occasionally hold slightly more records than its limit would otherwise allow.

To create new records yourself through the dashboard or API, your zone must still be within its record limit.

### Per-zone quota

By default, there is a limit to the number of records you can create on a single zone.

- Free zones created before `2024-09-01 00:00:00 UTC`: 1,000
- Free zones created on or after `2024-09-01 00:00:00 UTC`: 200
- Pro: 3,500
- Business: 3,500
- Enterprise: falls under the [per-account quota](#per-account-quota) (no separate per-zone limit).

You can retrieve a zone's current quota (if applicable) and usage [via the API](https://developers.cloudflare.com/api/resources/dns/subresources/usage/subresources/zone/methods/get/).

### Per-account quota

Enterprise accounts have a quota on the total number of records across all of their zones, instead of the per-zone limit. This lets you distribute records across your zones however you like, regardless of each zone's plan.

Public zones and [internal zones](https://developers.cloudflare.com/dns/internal-dns/) are counted separately, each with a default account quota of 1,000,000 records.

You can retrieve your current account quota and usage [via the API](https://developers.cloudflare.com/api/resources/dns/subresources/usage/subresources/account/methods/get/).

For more DNS records

If you are an Enterprise customer and require a higher account quota, contact your account team. Cloudflare can support millions of DNS records.

## Resources

### How to

- [Manage DNS records](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/)
- [Create zone apex record](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-zone-apex/)
- [Create subdomain records](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-subdomain/)
- [Set up email records](https://developers.cloudflare.com/dns/manage-dns-records/how-to/email-records/)
- [Set up Google Workspace DNS records](https://developers.cloudflare.com/dns/manage-dns-records/how-to/set-up-google-workspace/)
- [Import and export records](https://developers.cloudflare.com/dns/manage-dns-records/how-to/import-and-export/)
- [Batch record changes](https://developers.cloudflare.com/dns/manage-dns-records/how-to/batch-record-changes/)
- [Dynamically update DNS records](https://developers.cloudflare.com/dns/manage-dns-records/how-to/managing-dynamic-ip-addresses/)
- [Round-robin DNS](https://developers.cloudflare.com/dns/manage-dns-records/how-to/round-robin-dns/)
- [Delegate subdomains](https://developers.cloudflare.com/dns/manage-dns-records/how-to/subdomains-outside-cloudflare/)

### Reference

- [DNS record types](https://developers.cloudflare.com/dns/manage-dns-records/reference/dns-record-types/)
- [Time to Live (TTL)](https://developers.cloudflare.com/dns/manage-dns-records/reference/ttl/)
- [Record attributes](https://developers.cloudflare.com/dns/manage-dns-records/reference/record-attributes/)
- [Wildcard DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/)
- [Shadowed records](https://developers.cloudflare.com/dns/manage-dns-records/reference/shadowed-records/)
- [Vendor-specific DNS records](https://developers.cloudflare.com/dns/manage-dns-records/reference/vendor-specific-records/)

### Troubleshooting

- [Records with the same name](https://developers.cloudflare.com/dns/manage-dns-records/troubleshooting/records-with-same-name/)
- [Unexpected DNS records](https://developers.cloudflare.com/dns/manage-dns-records/troubleshooting/unexpected-dns-records/)
- [Exposed IP addresses](https://developers.cloudflare.com/dns/manage-dns-records/troubleshooting/exposed-ip-address/)
- [Verify a domain with CNAME](https://developers.cloudflare.com/dns/manage-dns-records/troubleshooting/cname-domain-verification/)
- [NS records already exist](https://developers.cloudflare.com/dns/manage-dns-records/troubleshooting/existing-ns-record/)
- [Stale response for upstream DNS resolution](https://developers.cloudflare.com/dns/manage-dns-records/troubleshooting/stale-response/)

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"WebPage","@id":"https://developers.cloudflare.com/dns/manage-dns-records/#page","headline":"DNS records","description":"Manage DNS records for your Cloudflare zones.","url":"https://developers.cloudflare.com/dns/manage-dns-records/","inLanguage":"en","image":"https://developers.cloudflare.com/dns/manage-dns-records/og.png?v=ffb273d81e8354c9","dateModified":"2026-08-14","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
