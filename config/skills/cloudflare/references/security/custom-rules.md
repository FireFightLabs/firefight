---
description: Block, challenge, or allow requests matching custom expressions.
title: Custom rules
image: https://developers.cloudflare.com/waf/custom-rules/og.png?v=79e0914871b39ca0
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/waf/llms.txt  
> Use this file to discover all available pages before exploring further.

# Custom rules

Last updated Aug 25, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/waf/custom-rules/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

Custom rules allow you to control incoming traffic by filtering requests to a zone. They work as customized web application firewall (WAF) rules that you can use to perform actions like *Block* or *Managed Challenge* on incoming requests. You can also use the *Skip* action in a custom rule to [skip one or more Cloudflare security features](https://developers.cloudflare.com/waf/custom-rules/skip/).

In the [new security dashboard](https://developers.cloudflare.com/security/), custom rules are one of the available types of [security rules](https://developers.cloudflare.com/security/rules/). Security rules perform security-related actions on incoming requests that match specified filters.

Like other rules evaluated by Cloudflare's [Ruleset Engine](https://developers.cloudflare.com/ruleset-engine/), custom rules have the following basic parameters:

- An [expression](https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/) that specifies the criteria you are matching traffic on using the [Rules language](https://developers.cloudflare.com/ruleset-engine/rules-language/).
- An [action](https://developers.cloudflare.com/ruleset-engine/rules-language/actions/) that specifies what to perform when there is a match for the rule.

Custom rules are evaluated in order, and some actions like *Block* will stop the evaluation of other rules. This means that if an earlier rule blocks a request, later rules will not run for that request. For more details on actions and their behavior, refer to [Actions](https://developers.cloudflare.com/ruleset-engine/rules-language/actions/).

## Custom rulesets

To define sets of custom rules that apply to more than one zone, use [custom rulesets](https://developers.cloudflare.com/waf/account/custom-rulesets/). At the zone level, all customers can create and deploy custom rulesets. Custom rulesets at the account level require an Enterprise plan.

Note

Currently, the Cloudflare dashboard does not support working with custom rulesets at the zone level. You will need to [use the Cloudflare API](https://developers.cloudflare.com/waf/custom-rules/create-api/) to configure or deploy these rulesets.

## Interaction with other app security features

If you are using several app security features like custom rules, Managed Rules, and Super Bot Fight Mode, it is important to understand how these features interact and the order in which they execute. Refer to [Security features interoperability](https://developers.cloudflare.com/waf/feature-interoperability/) for more information.

## Availability

|  | Free | Pro | Business | Enterprise |
| --- | --- | --- | --- | --- |
| Availability | Yes | Yes | Yes | Yes |
| Number of rules | 5 | 20 | 100 | 1,000 |
| Supported actions | All except Log | All except Log | All except Log | All |
| Regex support | No | No | Yes | Yes |
| Number of custom rulesets (zone) | 1 | 2 | 5 | 10 |
| Account-level custom rulesets | No | No | No | Yes |

The maximum number of custom rules applies to all rules in the `http_request_firewall_custom` [phase](https://developers.cloudflare.com/ruleset-engine/about/phases/), which is where custom rules run. Each scope (zone or account) has a separate maximum number of rules, counted in the following way:

- Zone: All custom rules plus all the rules across custom rulesets defined at the zone level.
- Account: All the rules across custom rulesets defined at the account level.

---

## Next steps

Refer to the following pages for instructions on creating custom rules:

- [Create a custom rule in the dashboard](https://developers.cloudflare.com/waf/custom-rules/create-dashboard/)
- [Create a custom rule via API](https://developers.cloudflare.com/waf/custom-rules/create-api/)
- [WAF custom rules configuration using Terraform](https://developers.cloudflare.com/terraform/additional-configurations/waf-custom-rules/)

For examples of using custom rules to address common use cases, refer to [Common use cases](https://developers.cloudflare.com/waf/custom-rules/use-cases/).

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/waf/custom-rules/#page","headline":"Custom rules","description":"Block, challenge, or allow requests matching custom expressions.","url":"https://developers.cloudflare.com/waf/custom-rules/","inLanguage":"en","image":"https://developers.cloudflare.com/waf/custom-rules/og.png?v=79e0914871b39ca0","dateModified":"2026-08-25","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
