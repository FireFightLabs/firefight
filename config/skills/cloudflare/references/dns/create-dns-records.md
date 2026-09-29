---
description: Create, edit, and delete DNS records for your zone.
title: Manage DNS records
image: https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/og.png?v=e83a8766ec47be93
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/dns/llms.txt  
> Use this file to discover all available pages before exploring further.

# Manage DNS records

Last updated May 6, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

Consider the sections below for step-by-step instructions on managing DNS records at Cloudflare.

To better understand what DNS records are, refer to [Overview](https://developers.cloudflare.com/dns/manage-dns-records/). For context around common records you want to review when getting started at Cloudflare, refer to [review DNS records](https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/#2-review-your-dns-records).

Note

If your domain is added to Cloudflare by a hosting partner, manage your DNS records via the hosting partner.

---

## Basic operations

### Create DNS records

To create a DNS record in the dashboard:

1. In the Cloudflare dashboard, go to the **DNS Records** page. [Go to **Records** ↗](https://dash.cloudflare.com/?to=/:account/:zone/dns/records)
2. Select **Add record**.
3. Choose a record [**Type**](https://developers.cloudflare.com/dns/manage-dns-records/reference/dns-record-types/).
4. Complete the required fields, which vary per record. Particularly important fields (for some records) include:
   - **Proxy status**: For `A`, `AAAA`, and `CNAME` records, decide whether hostname traffic is [proxied through Cloudflare](https://developers.cloudflare.com/dns/proxy-status/).
   - **TTL**: Short for [*Time to Live*](https://developers.cloudflare.com/dns/manage-dns-records/reference/ttl/), this field controls how long each record is valid and — as a result — how long it takes for record updates to reach your end users.
   - **Comment** and **Tag**: [Record attributes](https://developers.cloudflare.com/dns/manage-dns-records/reference/record-attributes/) meant for your reference.
   - **Private network routing**: Some Enterprise customers also have access to [private network routing](https://developers.cloudflare.com/dns/private-origins/private-network-routing/). For `A` and `AAAA` records, this feature allows you to proxy HTTP/HTTPS traffic from public hostnames to origins in your private network.
5. Select **Save**.

To create records with the API, use a [POST request](https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/create/). For field definitions, select a record type under the request body specification.

For specific API examples, refer to [DNS record types](https://developers.cloudflare.com/dns/manage-dns-records/reference/dns-record-types/).

### Edit DNS records

To edit DNS records in the dashboard:

1. In the Cloudflare dashboard, go to the **DNS Records** page. [Go to **Records** ↗](https://dash.cloudflare.com/?to=/:account/:zone/dns/records)
2. On a specific record, select **Edit**.
3. Make any necessary changes.
4. Select **Save**.

To update part of a record with the API, use a [PATCH request](https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/edit/). If you want to overwrite the entire existing record, use a [PUT request](https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/update/).

### Delete DNS records

To delete DNS records in the dashboard:

1. In the Cloudflare dashboard, go to the **DNS Records** page. [Go to **Records** ↗](https://dash.cloudflare.com/?to=/:account/:zone/dns/records)
2. On a specific record, select **Edit**.
3. Select **Delete**.
4. Select **Delete** again to confirm.

To delete records with the API, use a [DELETE request](https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/delete/).

---

## Use cases

### Update an origin IP address

If your hosting provider changes or your origin IP address changes, update the **Content** value of the relevant DNS records (usually `A` or `AAAA` records).

If you are not sure which IP address to use, refer to your hosting provider's documentation.

### Originless setups

If you need a placeholder address for an originless setup (also referred to as parked domain or redirect-only), you can use the reserved IPv6 address `100::` or the reserved IPv4 address `192.0.2.0` in a [proxied](https://developers.cloudflare.com/dns/proxy-status/) DNS record.

This allows you to route requests using products such as [Redirect Rules](https://developers.cloudflare.com/rules/url-forwarding/), [Page Rules](https://developers.cloudflare.com/rules/page-rules/), or [Workers](https://developers.cloudflare.com/workers/).

Note

The address `192.0.2.0` comes from an IPv4 range reserved for documentation ([RFC 5737 ↗︎](https://www.rfc-editor.org/rfc/rfc5737)), and `100::` comes from the IPv6 discard prefix `0100::/64` ([RFC 6666 ↗︎](https://www.rfc-editor.org/rfc/rfc6666)). Neither address is expected to route to a real server on properly configured networks, which makes them safe to use as placeholder values. Because the DNS record is proxied, Cloudflare intercepts the request before it reaches the origin address.

---

## Further guidance

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

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/#page","headline":"Manage DNS records","description":"Create, edit, and delete DNS records for your zone.","url":"https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/","inLanguage":"en","image":"https://developers.cloudflare.com/dns/manage-dns-records/how-to/create-dns-records/og.png?v=e83a8766ec47be93","dateModified":"2026-05-06","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
