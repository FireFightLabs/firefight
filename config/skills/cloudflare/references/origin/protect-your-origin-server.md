---
description: Secure your origin server with Cloudflare by hiding its IP address, limiting connections, and monitoring health.
title: Protect your origin server
image: https://developers.cloudflare.com/fundamentals/security/protect-your-origin-server/og.png?v=cde3744df25524ee
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/fundamentals/llms.txt  
> Use this file to discover all available pages before exploring further.

# Protect your origin server

Last updated Oct 2, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/fundamentals/security/protect-your-origin-server/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

Your [origin server ↗︎](https://www.cloudflare.com/learning/cdn/glossary/origin-server) is a physical or virtual machine that is not owned by Cloudflare and hosts your application content (data, webpages, etc.).

Receiving too many requests can be bad for your origin. These requests might increase latency for visitors, incur higher costs — particularly for cloud-based machines — and could knock your application offline.

## Secure origin connections

When you secure origin connections, it prevents attackers from discovering and overloading your origin server with requests.

- **DNS**:
  1. **Proxy records** (when possible): Set up [proxied (orange-clouded) DNS records](https://developers.cloudflare.com/dns/proxy-status/) to hide your origin IP addresses and provide DDoS protection. As part of this, you should [allow Cloudflare IP addresses](https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/) at your origin to prevent requests from being blocked.
  2. **Review DNS-only records**: Audit existing **DNS-only** records ( `SPF`, `TXT`, and more) to make sure they do not contain origin IP information.
  3. **Evaluate mail infrastructure**: If possible, do not host a mail service on the same server as the web resource you want to protect, since emails sent to non-existent addresses get bounced back to the attacker and reveal the mail server IP.
  4. **Rotate origin IPs**: Once [onboarded](https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/#35-verify-changes), rotate your origin IPs, as DNS records are in the public domain. Historical records are kept and would contain IP addresses prior to joining Cloudflare

### Application layer

<details>

<summary>

Cloudflare Tunnel (HTTP / WebSockets)

</summary>

<a href="https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/">Cloudflare Tunnel</a> connects your resources to Cloudflare without a publicly routable IP address, by creating an outbound-only connections to Cloudflare’s global network.

- **Security**: Very secure.
- **Availability**: All customers.
- **Challenges**: Requires installing the <code>cloudflared</code> daemon on origin server or virtual machine.

</details>

<details>

<summary>

HTTP Header Validation

</summary>

Only allow traffic with specific (and secret) HTTP headers.

- **Security**: Moderately secure.
- **Availability**: All customers.
- **Challenges**:
  - Requires more configuration efforts on application- and server-side to accept those headers.
  - Basic authentication is vulnerable to replay attacks. Because basic authentication does not encrypt user credentials, it is important that traffic always be sent over an encrypted SSL session.
  - There might be valid use cases for a mismatch in SNI / Host headers such as through <a href="https://developers.cloudflare.com/rules/origin-rules/features/">Origin or Page Rules</a>, <a href="https://developers.cloudflare.com/load-balancing/additional-options/override-http-host-headers/">Load Balancing</a>, or <a href="https://developers.cloudflare.com/workers/runtime-apis/request/">Workers</a>, which all offer HTTP Host Header overrides.
- **Process**:
  1. Use <a href="https://developers.cloudflare.com/rules/transform/request-header-modification/">Transform rules</a> or <a href="https://developers.cloudflare.com/workers/examples/alter-headers/">Workers</a> to add an HTTP Auth Header.
  2. Configure your origin server to restrict access based on the <a href="https://developers.cloudflare.com/workers/examples/auth-with-headers/">HTTP Auth Header</a> (or perform <a href="https://developers.cloudflare.com/workers/examples/basic-auth/">HTTP Basic Authentication</a>).
  3. Configure your origin server to restrict access based on the <a href="https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Host">HTTP Host Header ↗︎</a>. Specifically, only allow requests which contain expected HTTP Host Header values, and reject all other requests.

</details>

<details>

<summary>

JSON Web Tokens (JWT) Validation

</summary>

Only allow traffic with the appropriate JWT.

- **Security**: Very secure.
- **Availability**: Some customers.
- **Challenges**:
  - Requires either installing incremental software or modifying application code.
  - Lots of manual work.
- **Resources**:
  - <a href="https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/">Validate JWTs for an Access application</a>
  - <a href="https://developers.cloudflare.com/api-shield/security/jwt-validation/">Validate JWTs for an API</a>

</details>

### Transport Layer

<details>

<summary>

Authenticated Origin Pulls

</summary>

<a href="https://developers.cloudflare.com/ssl/origin-configuration/authenticated-origin-pull/">Authenticated Origin Pulls</a> helps ensure requests to your origin server come from the Cloudflare network.

- **Security**: Very secure.
- **Availability**: All customers.
- **Challenges**:
  - Requires <a href="https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full/">Full</a> or <a href="https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/">Full (strict)</a> encryption modes.
  - Requires more configuration efforts for application and server, such as uploading a certificate and configuring the server to use it.
  - For more strict security, you should upload your own certificate. Although Cloudflare provides you a certificate for easy configuration, this certificate only guarantees that a request is coming from the Cloudflare network.
  - Not scalable for large numbers of origin servers.

</details>

<details>

<summary>

Cloudflare Tunnel (SSH / RDP)

</summary>

<a href="https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/">Cloudflare Tunnel</a> connects your resources to Cloudflare without a publicly routable IP address, by creating an outbound-only connections to Cloudflare’s global network.

- **Security**: Very secure.
- **Availability**: All customers.
- **Challenges**: Requires installing the <code>cloudflared</code> daemon on origin server or virtual machine.

</details>

### Network Layer

<details>

<summary>

Allowlist Cloudflare IP addresses

</summary>

Explicitly block all traffic that does not come from <a href="https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/">Cloudflare IP addresses</a> (or the IP addresses of your trusted partners, vendors, or applications).

- **Security**: Moderately secure.
- **Availability**: All customers.
- **Challenges**:
  - Requires allowlisting Cloudflare IP ranges at your origin server.
  - Vulnerable to IP spoofing.

</details>

<details>

<summary>

Cloudflare Magic Transit

</summary>

<a href="https://developers.cloudflare.com/magic-transit/">Cloudflare Magic Transit</a> is a network security and performance solution that offers DDoS protection, traffic acceleration, and more for on-premise, cloud-hosted, and hybrid networks.

- **Security**: Very secure.
- **Availability**: Enterprise-only.
- **Challenges**
  - Client's routers must:
    - Support anycast tunneling.
    - Allow configuration of at least one tunnel per Internet service provider (ISP).
    - Support maximum segment size (MSS) clamping.

</details>

<details>

<summary>

Cloudflare Network Interconnect

</summary>

<a href="https://developers.cloudflare.com/network-interconnect/">Cloudflare Network Interconnect</a> allows you to connect your network infrastructure directly with Cloudflare – rather than using the public Internet – for a more reliable and secure experience.

- **Security**: Very secure.
- **Availability**: Enterprise-only.
- **Challenges**
  - Requires some networking knowledge.
  - Only applies to some customer use cases.

</details>

<details>

<summary>

Dedicated CDN Egress IPs

</summary>

<a href="https://developers.cloudflare.com/smart-shield/get-started/#packages-and-availability">Smart Shield Advanced</a> provides dedicated egress IPs (from Cloudflare to your origin) for your layer 7 <a href="https://developers.cloudflare.com/waf/">WAF</a> and CDN services, as well as <a href="https://developers.cloudflare.com/spectrum/">Spectrum</a>. The egress IPs are reserved exclusively for your account so that you can increase your origin security by only allowing a small list of IP addresses through your layer 3 firewall.

- **Security**: Very secure.
- **Availability**: Enterprise-only.
- **Challenges**: Requires network-level firewall policies.

</details>

## Monitor origin health

For passive monitoring, [create notifications](https://developers.cloudflare.com/notifications/get-started/#create-an-alert) for **Origin Error Rate Alerts** to receive alerts when your origin returns 5xx codes above a configurable threshold and **Passive Origin Monitoring** to see when Cloudflare is unable to reach your origin for a few minutes.

For more active monitoring, set up [standalone health checks](https://developers.cloudflare.com/health-checks/) for your origin.

Note

If you have multiple servers and want to proactively prevent origin problems, [set up load balancing](https://developers.cloudflare.com/load-balancing/) as an add-on service.

### Zero Downtime Failover

If you have another `A` or `AAAA` record in your Cloudflare **DNS** or your Cloudflare **Load Balancer** provides another [endpoint](https://developers.cloudflare.com/load-balancing/understand-basics/load-balancing-components/) in the same pool, **Zero-Downtime Failover** automatically retries requests to your origin even before a Load Balancing decision is made.

Zero-downtime failover will trigger a single retry only if there is another healthy endpoint in the pool and a [521, 522, 523, 525 or 526 error code](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-521/) is occurring. No other error codes will trigger a zero-downtime failover operation.

  

## Reduce origin traffic

### Block traffic

For more details, refer to [Secure your website](https://developers.cloudflare.com/learning-paths/application-security/account-security/).

### Increase caching

The [cache](https://developers.cloudflare.com/cache/) stores data from your application (webpages, etc.) at Cloudflare data centers around the world, which reduces the number of requests sent to your origin server.

### Distribute traffic

To randomly distribute traffic across multiple servers, [set up multiple DNS records](https://developers.cloudflare.com/dns/manage-dns-records/how-to/round-robin-dns/).

For more fine-grained control over traffic distribution — including automatic failover, intelligent routing, and more — set up our [add-on load balancing service](https://developers.cloudflare.com/load-balancing/).

To protect specific endpoints from being overwhelmed by traffic spikes, [set up a waiting room](https://developers.cloudflare.com/waiting-room/).

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/fundamentals/security/protect-your-origin-server/#page","headline":"Protect your origin server","description":"Secure your origin server with Cloudflare by hiding its IP address, limiting connections, and monitoring health.","url":"https://developers.cloudflare.com/fundamentals/security/protect-your-origin-server/","inLanguage":"en","image":"https://developers.cloudflare.com/fundamentals/security/protect-your-origin-server/og.png?v=cde3744df25524ee","dateModified":"2026-10-02","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
