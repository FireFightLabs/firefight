---
description: Understand how public and private traffic on-ramps to and off-ramps from Cloudflare's global network for security and performance.
title: Traffic flow through Cloudflare
image: https://developers.cloudflare.com/fundamentals/concepts/traffic-flow-cloudflare/og.png?v=1a4233e998cfb6d7
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/fundamentals/llms.txt  
> Use this file to discover all available pages before exploring further.

# Traffic flow through Cloudflare

Last updated Apr 20, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/fundamentals/concepts/traffic-flow-cloudflare/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

Internet traffic is made up of people, services, and agents requesting online resources from wherever they are hosted. Your resources may be publicly available, like a website or application that anyone on the Internet can access. Or your resources may be privately available, like an internal app or network that only your employees and partners should be able to access.

Both public and private resources can be connected to the Cloudflare network to ensure only good actors can access what they are supposed to be able to access with high performance.

For example, you may not always want the direct traffic because it can come from malicious sources, like hackers, or in the form of [DDoS attacks ↗︎](https://www.cloudflare.com/learning/ddos/ddos-attack-tools/how-to-ddos/). Additionally, depending on the location where the request originated, you want to ensure the traffic is [routed through the most efficient and fastest path](https://developers.cloudflare.com/argo-smart-routing/).

## Cloudflare's network

[Cloudflare's global network ↗︎](https://www.cloudflare.com/network/), coupled with [Anycast ↗︎](https://www.cloudflare.com/learning/dns/what-is-anycast-dns/) IP addressing, ensures that requests are handled by a Cloudflare server that is as close to the source as possible.

If you want to protect your traffic and ensure it travels efficiently, you need to configure Cloudflare to be in front of whatever you are trying to protect, such as your application, service, or server. How you put your resources behind Cloudflare's network will depend on the type of traffic and how you want to control it.

Note

Cloudflare supports all HTTP methods, with the exception of `CONNECT`, `TRACE`, and `PURGE`, which are restricted. Requests that use restricted methods are not proxied through Cloudflare's network. Note that other Cloudflare products may apply different restrictions on HTTP methods, and behavior can vary depending on the service.

## On-ramp and off-ramp traffic

Traffic that enters Cloudflare's network is referred to as "on-ramping," and traffic that exits Cloudflare's network is referred to as "off-ramping." You may also know this as ingress and egress or "routing your traffic" through a network.

### On-ramp traffic to Cloudflare

When you on-ramp traffic to Cloudflare, this allows Cloudflare to act on, secure, and increase performance of that traffic.

One example of on-ramping traffic to Cloudflare is updating your public website to use Cloudflare as the primary authoritative [DNS provider](https://developers.cloudflare.com/fundamentals/concepts/how-cloudflare-works/#cloudflare-as-a-dns-provider) for your domain.

However, maybe you need to protect a private application that is not directly available on the Internet. In this scenario, you can:

- Connect your private application to Cloudflare using [secure tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/), and use a [device agent](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/) to connect as a user.
- For users already connected to a private company network, connect the entire network to Cloudflare using secure tunnels, and any request from a user device will access the private application through those tunnels.

With these options, any request from a user device can access internal private applications via the secure private tunnels.

Refer to the list below for products you can use to on-ramp traffic to Cloudflare.

- [Anycast routing ↗︎](https://www.cloudflare.com/learning/cdn/glossary/anycast-network/) uses Anycast IP addressing to route traffic to the nearest Cloudflare data center. Selective routing allows an Anycast network to be resilient in the face of high traffic volume, network congestion, and [ DDoS attacks ↗︎](https://www.cloudflare.com/learning/ddos/what-is-a-ddos-attack/).
- [DNS-based](https://developers.cloudflare.com/fundamentals/concepts/how-cloudflare-works/#cloudflare-as-a-dns-provider) traffic resolves domains onboarded to [Cloudflare's CDN](https://developers.cloudflare.com/fundamentals/concepts/how-cloudflare-works/). Cloudflare's DNS directs traffic to Cloudflare's global network of servers instead of a website's origin server.
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/) connects your resources to Cloudflare without a publicly routable IP address so that your origins can serve traffic through Cloudflare without being vulnerable to attacks that bypass Cloudflare.
- [Magic Transit](https://developers.cloudflare.com/magic-transit/about/) offers DDoS protection, traffic acceleration, and more for on-premise, cloud-hosted, and hybrid networks by accepting IP packets destined for your network, processing them, and outputting the packets to your origin infrastructure.
- The [Cloudflare One Client](https://developers.cloudflare.com/cloudflare-one/team-and-resources/devices/cloudflare-one-client/) securely and privately sends traffic from corporate devices to Cloudflare's global network while also applying advanced Zero Trust policies that check for a device's health before it connects to corporate applications.

### Off-ramp traffic from Cloudflare

If you need to ensure traffic leaves Cloudflare's network in a specific way, you can manage how traffic is off-ramped.

For example, if you need to adhere to [regional laws](https://developers.cloudflare.com/data-localization/regional-services/) that dictate user traffic and require data never leaves your country, you can configure off-ramp and on-ramp traffic on servers in the same geographical area.

Or maybe you want to force traffic to off-ramp in a certain country to maintain your user's experience. For example, if you have employees in India who travel frequently, you can configure the off-ramp traffic to always appear to come from India so websites they visit maintain their language and preferences.

You can also utilize [caching](https://developers.cloudflare.com/cache/) to help with performance. Instead of off-ramp traffic going to a server across the globe, Cloudflare can cache that content locally for the user to reduce the overall time for their request.

Refer to the list below for products you can use to off-ramp traffic from Cloudflare.

- [Argo Smart Routing](https://developers.cloudflare.com/argo-smart-routing/) detects real-time network issues and routes your web traffic across the most efficient network path, avoiding congestion.
- [Cache](https://developers.cloudflare.com/cache/) works with cached content to avoid off-ramping to origin servers and instead serving directly from Cloudflare's global network.
- [Regional services](https://developers.cloudflare.com/data-localization/regional-services/) lets you choose which subset of data centers decrypt and service HTTPS traffic, which can help customers who have to meet regional compliance or have preferences for maintaining regional control over their data.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/fundamentals/concepts/traffic-flow-cloudflare/#page","headline":"Traffic flow through Cloudflare","description":"Understand how public and private traffic on-ramps to and off-ramps from Cloudflare's global network for security and performance.","url":"https://developers.cloudflare.com/fundamentals/concepts/traffic-flow-cloudflare/","inLanguage":"en","image":"https://developers.cloudflare.com/fundamentals/concepts/traffic-flow-cloudflare/og.png?v=1a4233e998cfb6d7","dateModified":"2026-04-20","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
