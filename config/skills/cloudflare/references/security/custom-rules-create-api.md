---
description: Create WAF custom rules using the Rulesets API.
title: Create a custom rule via API
image: https://developers.cloudflare.com/waf/custom-rules/create-api/og.png?v=9b8bef602046ca43
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/waf/llms.txt  
> Use this file to discover all available pages before exploring further.

# Create a custom rule via API

Last updated Apr 16, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/waf/custom-rules/create-api/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

Use the [Rulesets API](https://developers.cloudflare.com/ruleset-engine/rulesets-api/) to create a custom rule via API at the zone level.

You must deploy custom rules to the `http_request_firewall_custom` [phase entry point ruleset](https://developers.cloudflare.com/ruleset-engine/about/rulesets/#entry-point-ruleset).

If you are using Terraform, refer to [WAF custom rules configuration using Terraform](https://developers.cloudflare.com/terraform/additional-configurations/waf-custom-rules/).

## Create a custom rule

To create a custom rule for a zone, add a rule to the `http_request_firewall_custom` phase entry point ruleset.

1. Invoke the [Get a zone entry point ruleset](https://developers.cloudflare.com/api/resources/rulesets/subresources/phases/methods/get/) operation to obtain the definition of the entry point ruleset for the `http_request_firewall_custom` phase. You will need the [zone ID](https://developers.cloudflare.com/fundamentals/account/find-account-and-zone-ids/) for this task.
2. If the entry point ruleset already exists (that is, if you received a `200 OK` status code and the ruleset definition), take note of the ruleset ID in the response. Then, invoke the [Create a zone ruleset rule](https://developers.cloudflare.com/api/resources/rulesets/subresources/rules/methods/create/) operation to add a custom rule to the existing ruleset. Refer to the examples below for details.
3. If the entry point ruleset does not exist (that is, if you received a `404 Not Found` status code in step 1), create it using the [Create a zone ruleset](https://developers.cloudflare.com/api/resources/rulesets/methods/create/) operation. Include your custom rule in the `rules` array. Refer to [Create ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/create/#example---create-a-zone-level-phase-entry-point-ruleset) for an example.

### Example A

This example request adds a rule to the `http_request_firewall_custom` phase entry point ruleset for the zone with ID `$ZONE_ID`. The entry point ruleset already exists, with ID `$RULESET_ID`.

The new rule, which will be the last rule in the ruleset, will challenge requests from the United Kingdom or France with an attack score lower than `20`.

*Create a zone ruleset rulebash*

```bash
curl "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$RULESET_ID/rules" \
	--request POST \
	--header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
	--json '{
		"description": "My custom rule",
		"expression": "(ip.src.country eq \"GB\" or ip.src.country eq \"FR\") and cf.waf.score lt 20",
		"action": "challenge"
	}'
```

To define a specific position for the new rule, include a `position` object in the request body according to the guidelines in [Change the order of a rule in a ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/update-rule/#change-the-order-of-a-rule-in-a-ruleset).

For instructions on creating an entry point ruleset and defining its rules using a single API call, refer to [Add rules to phase entry point rulesets](https://developers.cloudflare.com/ruleset-engine/basic-operations/add-rule-phase-rulesets/).

### Example B

This example request adds a rule to the `http_request_firewall_custom` phase entry point ruleset for the zone with ID `$ZONE_ID`. The entry point ruleset already exists, with ID `$RULESET_ID`.

The new rule, which will be the last rule in the ruleset, includes the definition of a [custom response](https://developers.cloudflare.com/waf/custom-rules/create-dashboard/#configure-a-custom-response-for-blocked-requests) for blocked requests.

*Create a zone ruleset rulebash*

```bash
curl "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$RULESET_ID/rules" \
	--request POST \
	--header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
	--json '{
		"description": "My custom rule with plain text response",
		"expression": "(ip.src.country eq \"GB\" or ip.src.country eq \"FR\") and cf.waf.score lt 20",
		"action": "block",
		"action_parameters": {
				"response": {
						"status_code": 403,
						"content": "Your request was blocked.",
						"content_type": "text/plain"
				}
		}
	}'
```

To define a specific position for the new rule, include a `position` object in the request body according to the guidelines in [Change the order of a rule in a ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/update-rule/#change-the-order-of-a-rule-in-a-ruleset).

For instructions on creating an entry point ruleset and defining its rules using a single API call, refer to [Add rules to phase entry point rulesets](https://developers.cloudflare.com/ruleset-engine/basic-operations/add-rule-phase-rulesets/).

---

## Next steps

Use the different operations in the [Rulesets API](https://developers.cloudflare.com/ruleset-engine/rulesets-api/) to work with the rule you just created. The following table has a list of common tasks:

| Task | Procedure |
| --- | --- |
| List all rules in ruleset | Use the [Get a zone entry point ruleset](https://developers.cloudflare.com/api/resources/rulesets/subresources/phases/methods/get/) operation with the `http_request_firewall_custom` phase name to obtain the list of configured custom rules and their IDs. For more information, refer to [View a specific ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/view/#view-a-specific-ruleset). |
| Update a rule | Use the [Update a zone ruleset rule](https://developers.cloudflare.com/api/resources/rulesets/methods/update/) operation. You will need to provide the ruleset ID and the rule ID. To obtain these IDs, you can use the [Get a zone entry point ruleset](https://developers.cloudflare.com/api/resources/rulesets/subresources/phases/methods/get/) operation with the `http_request_firewall_custom` phase name. For more information, refer to [Update a rule in a ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/update-rule/). |
| Delete a rule | Use the [Delete a zone ruleset rule](https://developers.cloudflare.com/api/resources/rulesets/methods/delete/) operation. You will need to provide the ruleset ID and the rule ID. To obtain these IDs, you can use the [Get a zone entry point ruleset](https://developers.cloudflare.com/api/resources/rulesets/subresources/phases/methods/get/) operation with the `http_request_firewall_custom` phase name. For more information, refer to [Delete a rule in a ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/delete-rule/). |

These operations are covered in the Ruleset Engine documentation. The Ruleset Engine powers different Cloudflare products, including custom rules.

## More resources

For instructions on deploying custom rules at the account level via API, refer to [Create a custom ruleset using the API](https://developers.cloudflare.com/waf/account/custom-rulesets/create-api/).

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/waf/custom-rules/create-api/#page","headline":"Create a custom rule via API","description":"Create WAF custom rules using the Rulesets API.","url":"https://developers.cloudflare.com/waf/custom-rules/create-api/","inLanguage":"en","image":"https://developers.cloudflare.com/waf/custom-rules/create-api/og.png?v=9b8bef602046ca43","dateModified":"2026-04-16","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
