---
description: Query WAF firewall events via GraphQL.
title: Querying Firewall Events with GraphQL
image: https://developers.cloudflare.com/analytics/graphql-api/tutorials/querying-firewall-events/og.png?v=20f54987574f99dc
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/analytics/llms.txt  
> Use this file to discover all available pages before exploring further.

# Querying Firewall Events with GraphQL

Last updated May 7, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/analytics/graphql-api/tutorials/querying-firewall-events/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

In this example, we are going to use the GraphQL Analytics API to query for Firewall Events over a specified time period.

The following API call will request Firewall Events over a one hour period, and output the requested fields. Be sure to replace `<CLOUDFLARE_ZONE_TAG>`, `<EMAIL>`, and `<API_TOKEN>`<sup>[1](#user-content-fn-1)</sup> with your zone tag and API credentials, and adjust the `datetime_geg` and `datetime_leq` values to your liking.

## API Call

```bash
echo '{ "query":
  "query ListFirewallEvents($zoneTag: string, $filter: FirewallEventsAdaptiveFilter_InputObject) {
    viewer {
      zones(filter: { zoneTag: $zoneTag }) {
        firewallEventsAdaptive(
          filter: $filter
          limit: 10
          orderBy: [datetime_DESC]
        ) {
          action
          clientAsn
          clientCountryName
          clientIP
          clientRequestPath
          clientRequestQuery
          datetime
          source
          userAgent
        }
      }
    }
  }",
  "variables": {
    "zoneTag": "<CLOUDFLARE_ZONE_TAG>",
    "filter": {
      "datetime_geq": "2022-07-24T11:00:00Z",
      "datetime_leq": "2022-07-24T12:00:00Z"
    }
  }
}' | tr -d '\n' | curl --silent \
https://api.cloudflare.com/client/v4/graphql \
--header "Authorization: Bearer <API_TOKEN>" \
--header "Accept: application/json" \
--header "Content-Type: application/json" \
--data @-
```

The results returned will be in JSON (as requested), so piping the output to `jq` will make them easier to read, for example:

```bash
... | curl --silent \
https://api.cloudflare.com/client/v4/graphql \
--header "Authorization: Bearer <API_TOKEN>" \
--header "Accept: application/json" \
--header "Content-Type: application/json" \
--data @- | jq .

#=> {
#=>   "data": {
#=>     "viewer": {
#=>       "zones": [
#=>         {
#=>           "firewallEventsAdaptive": [
#=>             {
#=>               "action": "log",
#=>               "clientAsn": "5089",
#=>               "clientCountryName": "GB",
#=>               "clientIP": "203.0.113.69",
#=>               "clientRequestPath": "/%3Cscript%3Ealert()%3C/script%3E",
#=>               "clientRequestQuery": "",
#=>               "datetime": "2020-04-24T10:11:24Z",
#=>               "source": "waf",
#=>               "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.163 Safari/537.36"
#=>             },
#=>             {
#=>               "action": "log",
#=>               "clientAsn": "5089",
#=>               "clientCountryName": "GB",
#=>               "clientIP": "203.0.113.69",
#=>               "clientRequestPath": "/%3Cscript%3Ealert()%3C/script%3E",
#=>               "clientRequestQuery": "",
#=>               "datetime": "2020-04-24T10:11:24Z",
#=>               "source": "waf",
#=>               "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.163 Safari/537.36"
#=>             },
#=>             {
#=>               "action": "log",
#=>               "clientAsn": "5089",
#=>               "clientCountryName": "GB",
#=>               "clientIP": "203.0.113.69",
#=>               "clientRequestPath": "/%3Cscript%3Ealert()%3C/script%3E",
#=>               "clientRequestQuery": "",
#=>               "datetime": "2020-04-24T10:11:24Z",
#=>               "source": "waf",
#=>               "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.163 Safari/537.36"
#=>             },
#=>             {
#=>               "action": "log",
#=>               "clientAsn": "5089",
#=>               "clientCountryName": "GB",
#=>               "clientIP": "203.0.113.69",
#=>               "clientRequestPath": "/%3Cscript%3Ealert()%3C/script%3E",
#=>               "clientRequestQuery": "",
#=>               "datetime": "2020-04-24T10:11:24Z",
#=>               "source": "waf",
#=>               "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.163 Safari/537.36"
#=>             },
#=>             {
#=>               "action": "log",
#=>               "clientAsn": "5089",
#=>               "clientCountryName": "GB",
#=>               "clientIP": "203.0.113.69",
#=>               "clientRequestPath": "/%3Cscript%3Ealert()%3C/script%3E",
#=>               "clientRequestQuery": "",
#=>               "datetime": "2020-04-24T10:11:24Z",
#=>               "source": "waf",
#=>               "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.163 Safari/537.36"
#=>             },
#=>             {
#=>               "action": "log",
#=>               "clientAsn": "5089",
#=>               "clientCountryName": "GB",
#=>               "clientIP": "203.0.113.69",
#=>               "clientRequestPath": "/%3Cscript%3Ealert()%3C/script%3E",
#=>               "clientRequestQuery": "",
#=>               "datetime": "2020-04-24T10:11:24Z",
#=>               "source": "waf",
#=>               "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.163 Safari/537.36"
#=>             },
#=>             {
#=>               "action": "log",
#=>               "clientAsn": "5089",
#=>               "clientCountryName": "GB",
#=>               "clientIP": "203.0.113.69",
#=>               "clientRequestPath": "/%3Cscript%3Ealert()%3C/script%3E",
#=>               "clientRequestQuery": "",
#=>               "datetime": "2020-04-24T10:11:24Z",
#=>               "source": "waf",
#=>               "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.163 Safari/537.36"
#=>             },
#=>             {
#=>               "action": "block",
#=>               "clientAsn": "5089",
#=>               "clientCountryName": "GB",
#=>               "clientIP": "203.0.113.69",
#=>               "clientRequestPath": "/%3Cscript%3Ealert()%3C/script%3E",
#=>               "clientRequestQuery": "",
#=>               "datetime": "2020-04-24T10:11:24Z",
#=>               "source": "waf",
#=>               "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.163 Safari/537.36"
#=>             },
#=>             {
#=>               "action": "log",
#=>               "clientAsn": "58224",
#=>               "clientCountryName": "IR",
#=>               "clientIP": "2.183.175.37",
#=>               "clientRequestPath": "/api/v2",
#=>               "clientRequestQuery": "",
#=>               "datetime": "2020-04-24T10:00:54Z",
#=>               "source": "waf",
#=>               "userAgent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.169 Safari/537.36"
#=>             },
#=>             {
#=>               "action": "log",
#=>               "clientAsn": "58224",
#=>               "clientCountryName": "IR",
#=>               "clientIP": "2.183.175.37",
#=>               "clientRequestPath": "/api/v2",
#=>               "clientRequestQuery": "",
#=>               "datetime": "2020-04-24T10:00:54Z",
#=>               "source": "waf",
#=>               "userAgent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.169 Safari/537.36"
#=>             }
#=>           ]
#=>         }
#=>       ]
#=>     }
#=>   },
#=>   "errors": null
#=> }
```

## Retention and query window

The `firewallEventsAdaptive` dataset, which powers [Security Events](https://developers.cloudflare.com/waf/analytics/security-events/), has different data retention limits from the datasets used in [Security Analytics](https://developers.cloudflare.com/waf/analytics/security-analytics/#limits). Queries that exceed the data retention window return an error similar to the following:

```txt
cannot request data older than 2678400s
```

For more information on the limits per plan for the `firewallEventsAdaptive` dataset, refer to [Security Events](https://developers.cloudflare.com/waf/analytics/security-events/#availability).

To discover the exact limits for your zone programmatically, query the `settings` node:

```graphql
{
	viewer {
		zones(filter: { zoneTag: "<CLOUDFLARE_ZONE_TAG>" }) {
			settings {
				firewallEventsAdaptive {
					maxDuration
					maxPageSize
					notOlderThan
				}
				httpRequestsAdaptive {
					maxDuration
					maxPageSize
					notOlderThan
				}
			}
		}
	}
}
```

For more on the `settings` node, refer to [Settings node](https://developers.cloudflare.com/analytics/graphql-api/features/discovery/settings/).

## Footnotes

1. Refer to [Configure an Analytics API token](https://developers.cloudflare.com/analytics/graphql-api/getting-started/authentication/api-token-auth/) for more information on configuration and permissions. [↩](#user-content-fnref-1)

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/analytics/graphql-api/tutorials/querying-firewall-events/#page","headline":"Querying Firewall Events with GraphQL","description":"Query WAF firewall events via GraphQL.","url":"https://developers.cloudflare.com/analytics/graphql-api/tutorials/querying-firewall-events/","inLanguage":"en","image":"https://developers.cloudflare.com/analytics/graphql-api/tutorials/querying-firewall-events/og.png?v=20f54987574f99dc","dateModified":"2026-05-07","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
