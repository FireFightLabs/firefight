---
description: Troubleshoot HTTP 526 error responses.
title: Error 526
image: https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-526/og.png?v=c43fb5fd2bf95279
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/support/llms.txt  
> Use this file to discover all available pages before exploring further.

# Error 526

Last updated Apr 23, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-526/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

## Error 526: invalid SSL certificate

This error indicates that Cloudflare is unable to verify the SSL certificate on your origin server, preventing a secure connection from being established.

### Common causes

This error occurs when these two conditions are true:

- Cloudflare cannot validate the SSL certificate at your origin web server.
- [*Full SSL (Strict)*](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/) **SSL** is set in the **Overview** tab of your Cloudflare **SSL/TLS** app.

#### Resolution

Here are some options to fix or workaround this issue:

- For a potential quick fix, set **SSL** to *Full* instead of *Full (strict)* in the **Overview** tab of your Cloudflare **SSL/TLS** app for the domain.
- Add your self-signed SSL certificate to the [Custom Origin Trust Store](https://developers.cloudflare.com/ssl/origin-configuration/custom-origin-trust-store/). This allows the Cloudflare edge to recognize your self-signed SSL certificate as valid.
- Use a [Cloudflare Origin CA certificate](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/) at your origin.
- Request your server administrator or hosting provider to review the origin web server's SSL certificates and verify that:
  - Certificate is not expired.
  - Certificate is not revoked.
  - Certificate is signed by a [Certificate Authority ↗︎](https://en.wikipedia.org/wiki/Certificate_authority) (not self-signed).
  - The requested or target domain name and hostname are in the certificate's **Common Name** or **Subject Alternative Name**.
  - The certificate chain is complete - the origin server must serve the leaf certificate along with any required intermediate CA certificates so that Cloudflare can build a trusted chain to a root CA.
  - Your origin web server accepts connections over port SSL port `443`.
  - [Temporarily pause Cloudflare](https://developers.cloudflare.com/fundamentals/manage-domains/pause-cloudflare/) and visit [https://www.sslshopper.com/ssl-checker.html#hostname=www.example.com ↗︎](https://www.sslshopper.com/ssl-checker.html#hostname=www.example.com) (replace `www.example.com` with your hostname and domain) to verify no issues exists with the origin SSL certificate:![Screen showing an SSL certificate with no errors.](https://developers.cloudflare.com/cdn-cgi/image/onerror=redirect,width=702,height=560,format=webp/_astro/hc-import-troubleshooting_5xx_errors_sslshopper_output.B54TP_B1.png)

### Error 526 in the Zero Trust context

When using [Cloudflare Gateway](https://developers.cloudflare.com/cloudflare-one/traffic-policies/), an HTTP Error `526` might be returned in the [following cases](https://developers.cloudflare.com/cloudflare-one/traffic-policies/troubleshooting/#error-526-invalid-ssl-certificate):

- **An untrusted certificate is presented from the origin to Gateway.** Gateway will consider a certificate is untrusted if any of these conditions are true:
  - The server certificate issuer is unknown or is not trusted by the service.
  - The server certificate is revoked and fails a CRL check.
  - There is at least one expired certificate in the certificate chain for the server certificate.
  - The common name on the certificate does not match the URL you are trying to reach.
  - The common name on the certificate contains invalid characters (such as underscores). Gateway uses [BoringSSL ↗︎](https://csrc.nist.gov/projects/cryptographic-module-validation-program/validated-modules/search?SearchMode=Basic&Vendor=Google&CertificateStatus=Active&ValidationYear=0) to validate certificates. Chrome's [validation logic ↗︎](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/net/cert/x509_certificate.cc#429) allows non-RFC 1305 compliant certificates, which is why the website may load when you turn off WARP.
- **The connection from Gateway to the origin is insecure.** Gateway does not trust origins which:
  - Only offer insecure cipher suites (such as RC4, RC4-MD5, or 3DES). You can use the [SSL Server Test tool ↗︎](https://www.ssllabs.com/ssltest/index.html) to check which ciphers are supported by the origin.
  - Do not support [FIPS-compliant ciphers](https://developers.cloudflare.com/cloudflare-one/traffic-policies/http-policies/tls-decryption/#cipher-suites) (if you have enabled [FIPS compliance mode](https://developers.cloudflare.com/cloudflare-one/traffic-policies/http-policies/tls-decryption/#fips-compliance)). In order to load the page, you can either disable FIPS mode or create a Do Not Inspect policy for this host (which has the effect of disabling FIPS compliance for this origin).
  - Redirect all HTTPS requests to HTTP.

### Error 526 in the Workers context

Workers subrequests to any hostname outside your Cloudflare zone that is not proxied by Cloudflare are always made using the **[Full (strict)](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/)** SSL mode, regardless of the Workers zone configuration.

#### Resolution

- Make sure the SSL certificate configured at the origin is valid.
- Add your self-signed SSL certificate to the [Custom Origin Trust Store](https://developers.cloudflare.com/ssl/origin-configuration/custom-origin-trust-store/) and enable the [`cots_on_external_fetch` compatibility flag](https://developers.cloudflare.com/workers/configuration/compatibility-flags/#do-not-use-the-custom-origin-trust-store-for-external-subrequests) in your Worker's configuration. This flag enables the use of the [Custom Origin Trust Store](https://developers.cloudflare.com/ssl/origin-configuration/custom-origin-trust-store/) when making external (grey-clouded) subrequests from a Cloudflare Worker.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-526/#page","headline":"Error 526","description":"Troubleshoot HTTP 526 error responses.","url":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-526/","inLanguage":"en","image":"https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-5xx-errors/error-526/og.png?v=c43fb5fd2bf95279","dateModified":"2026-04-23","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
