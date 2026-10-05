---
description: Write expressions that match request characteristics for rule evaluation.
title: Expressions
image: https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/og.png?v=59d1d52c686f56f9
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/ruleset-engine/llms.txt  
> Use this file to discover all available pages before exploring further.

# Expressions

Last updated Oct 1, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

The Rules language supports two kinds of expressions: simple and compound.

## Simple expressions

**Simple expressions** compare a value from an HTTP request to a value defined in the expression. For example, this simple expression matches Microsoft Exchange Autodiscover requests:

```txt
http.request.uri.path matches "/autodiscover\.(xml|src)$"
```

Simple expressions have the following syntax:

```txt
<field> <comparison_operator> <value>
```

Where:

- [Fields](https://developers.cloudflare.com/ruleset-engine/rules-language/fields/) specify properties associated with an HTTP request.
- [Comparison operators](https://developers.cloudflare.com/ruleset-engine/rules-language/operators/#comparison-operators) define how values must relate to actual request data for an expression to return `true`.
- [Values](https://developers.cloudflare.com/ruleset-engine/rules-language/values/) represent the data associated with fields. The right side can contain a [dynamic value](https://developers.cloudflare.com/ruleset-engine/rules-language/operators/#compare-dynamic-values), such as a field or function result.

## Compound expressions

**Compound expressions** use [logical operators](https://developers.cloudflare.com/ruleset-engine/rules-language/operators/#logical-operators) such as `and` to combine two or more expressions into a single expression.

For example, this expression uses the `and` operator to target requests to `www.example.com` that are not on ports 80 or 443:

```txt
http.host eq "www.example.com" and not cf.edge.server_port in {80 443}
```

Compound expressions have the following general syntax:

```txt
<expression> <logical_operator> <expression>
```

Compound expressions allow you to generate sophisticated, highly targeted rules.

## Maximum rule expression length

The maximum length of a rule expression is 4,096 characters.

This limit applies whether you use the visual [Expression Builder](https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/edit-expressions/#expression-builder) to define your expression, or write the expression manually in the [Expression Editor](https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/edit-expressions/#expression-editor).

## Maximum regular expressions per rule

Each rule can contain a maximum of 64 regular expressions in its expression. This limit applies across all rule types that use the [Rules language](https://developers.cloudflare.com/ruleset-engine/rules-language/).

Rules that exceed this limit cannot be created or updated. Existing rules above this limit continue to work but cannot be modified until the expression is simplified.

## Additional features

You can also use the following Rules language features in your expressions:

- [Grouping symbols](https://developers.cloudflare.com/ruleset-engine/rules-language/operators/#grouping-symbols) allow you to explicitly group expressions that should be evaluated together.
- [Functions](https://developers.cloudflare.com/ruleset-engine/rules-language/functions/) allow you to manipulate and validate values in expressions.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/#page","headline":"Expressions","description":"Write expressions that match request characteristics for rule evaluation.","url":"https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/","inLanguage":"en","image":"https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/og.png?v=59d1d52c686f56f9","dateModified":"2026-10-01","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
