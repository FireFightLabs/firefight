---
description: Create zone-level rate limiting rules using the Rulesets API.
title: Create a rate limiting rule via API
image: https://developers.cloudflare.com/waf/rate-limiting-rules/create-api/og.png?v=826ea4630ff8d408
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/waf/llms.txt  
> Use this file to discover all available pages before exploring further.

# Create a rate limiting rule via API

Last updated Apr 16, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/waf/rate-limiting-rules/create-api/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

Use the [Rulesets API](https://developers.cloudflare.com/ruleset-engine/rulesets-api/) to create a rate limiting rule via API at the zone level.

A rate limiting rule is similar to a regular rule handled by the Ruleset Engine, but contains an additional `ratelimit` object with the rate limiting configuration. Refer to [Rate limiting parameters](https://developers.cloudflare.com/waf/rate-limiting-rules/parameters/) for more information on this field and its parameters.

You must deploy rate limiting rules to the `http_ratelimit` [phase entry point ruleset](https://developers.cloudflare.com/ruleset-engine/about/rulesets/#entry-point-ruleset).

Rate limiting rules must appear at the end of the rules list.

If you are using Terraform, refer to [Rate limiting rules configuration using Terraform](https://developers.cloudflare.com/terraform/additional-configurations/rate-limiting-rules/).

## Create a rate limiting rule

To create a rate limiting rule for a zone, add a rule with a `ratelimit` object to the `http_ratelimit` phase entry point ruleset.

1. Invoke the [Get a zone entry point ruleset](https://developers.cloudflare.com/api/resources/rulesets/subresources/phases/methods/get/) operation to obtain the definition of the entry point ruleset for the `http_ratelimit` phase. You will need the [zone ID](https://developers.cloudflare.com/fundamentals/account/find-account-and-zone-ids/) for this task.
2. If the entry point ruleset already exists (that is, if you received a `200 OK` status code and the ruleset definition), take note of the ruleset ID in the response. Then, invoke the [Create a zone ruleset rule](https://developers.cloudflare.com/api/resources/rulesets/subresources/rules/methods/create/) operation to add a rate limiting rule to the existing ruleset. Refer to the examples below for details.
3. If the entry point ruleset does not exist (that is, if you received a `404 Not Found` status code in step 1), create it using the [Create a zone ruleset](https://developers.cloudflare.com/api/resources/rulesets/methods/create/) operation. Include your rate limiting rule in the `rules` array. Refer to [Create ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/create/#example---create-a-zone-level-phase-entry-point-ruleset) for an example.

### Example A - Rate limiting based on request properties

This example adds a rate limiting rule to the `http_ratelimit` phase entry point ruleset for the zone with ID `$ZONE_ID`. The phase entry point ruleset already exists, with ID `$RULESET_ID`.

*Create a zone ruleset rulebash*

```bash
curl "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$RULESET_ID/rules" \
	--request POST \
	--header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
	--json '{
		"description": "My rate limiting rule",
		"expression": "(http.request.uri.path matches \"^/api/\")",
		"action": "block",
		"ratelimit": {
				"characteristics": [
						"cf.colo.id",
						"ip.src",
						"http.request.headers[\"x-api-key\"]"
				],
				"period": 60,
				"requests_per_period": 100,
				"mitigation_timeout": 600
		}
	}'
```

To define a specific position for the new rule, include a `position` object in the request body according to the guidelines in [Change the order of a rule in a ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/update-rule/#change-the-order-of-a-rule-in-a-ruleset).

For instructions on creating an entry point ruleset and defining its rules using a single API call, refer to [Add rules to phase entry point rulesets](https://developers.cloudflare.com/ruleset-engine/basic-operations/add-rule-phase-rulesets/).

### Example B - Rate limiting with a custom response

This example adds a rate limiting rule to the `http_ratelimit` phase entry point ruleset for the zone with ID `$ZONE_ID`. The phase entry point ruleset already exists, with ID `$RULESET_ID`.

The new rule defines a [custom response](https://developers.cloudflare.com/waf/rate-limiting-rules/create-zone-dashboard/#configure-a-custom-response-for-blocked-requests) for requests blocked due to rate limiting.

*Create a zone ruleset rulebash*

```bash
curl "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$RULESET_ID/rules" \
	--request POST \
	--header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
	--json '{
		"description": "My rate limiting rule",
		"expression": "(http.request.uri.path matches \"^/api/\")",
		"action": "block",
		"action_parameters": {
				"response": {
						"status_code": 403,
						"content": "You have been rate limited.",
						"content_type": "text/plain"
				}
		},
		"ratelimit": {
				"characteristics": [
						"cf.colo.id",
						"ip.src",
						"http.request.headers[\"x-api-key\"]"
				],
				"period": 60,
				"requests_per_period": 100,
				"mitigation_timeout": 600
		}
	}'
```

To define a specific position for the new rule, include a `position` object in the request body according to the guidelines in [Change the order of a rule in a ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/update-rule/#change-the-order-of-a-rule-in-a-ruleset).

For instructions on creating an entry point ruleset and defining its rules using a single API call, refer to [Add rules to phase entry point rulesets](https://developers.cloudflare.com/ruleset-engine/basic-operations/add-rule-phase-rulesets/).

### Example C - Rate limiting ignoring cached assets

This example adds a rate limiting rule to the `http_ratelimit` phase entry point ruleset for the zone with ID `$ZONE_ID`. The phase entry point ruleset already exists, with ID `$RULESET_ID`.

The new rule does not consider requests for cached assets when calculating the rate (`"requests_to_origin": true`).

*Create a zone ruleset rulebash*

```bash
curl "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$RULESET_ID/rules" \
	--request POST \
	--header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
	--json '{
		"description": "My rate limiting rule",
		"expression": "(http.request.uri.path matches \"^/api/\")",
		"action": "block",
		"ratelimit": {
				"characteristics": [
						"cf.colo.id",
						"ip.src",
						"http.request.headers[\"x-api-key\"]"
				],
				"period": 60,
				"requests_per_period": 100,
				"mitigation_timeout": 600,
				"requests_to_origin": true
		}
	}'
```

To define a specific position for the new rule, include a `position` object in the request body according to the guidelines in [Change the order of a rule in a ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/update-rule/#change-the-order-of-a-rule-in-a-ruleset).

For instructions on creating an entry point ruleset and defining its rules using a single API call, refer to [Add rules to phase entry point rulesets](https://developers.cloudflare.com/ruleset-engine/basic-operations/add-rule-phase-rulesets/).

### Example D - Complexity-based rate limiting rule

Note

[Complexity-based rate limiting](https://developers.cloudflare.com/waf/rate-limiting-rules/request-rate/#complexity-based-rate-limiting) is only available to Enterprise customers with Advanced Rate Limiting.

This example adds a rate limiting rule to the `http_ratelimit` phase entry point ruleset for the zone with ID `$ZONE_ID`. The phase entry point ruleset already exists, with ID `$RULESET_ID`.

The new rule is a complexity-based rate limiting rule that takes the `my-score` HTTP response header into account to calculate a total complexity score for the client. The counter with the total score is updated when there is a match for the rate limiting rule's counting expression (in this case, the same as the rule expression since `counting_expression` is an empty string). When this total score becomes larger than `400` during a period of `60` seconds (one minute), any later client requests will be blocked for a period of `600` seconds (10 minutes).

*Create a zone ruleset rulebash*

```bash
curl "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$RULESET_ID/rules" \
	--request POST \
	--header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
	--json '{
		"description": "My complexity-based rate limiting rule",
		"expression": "(http.request.uri.path wildcard \"/graphql/*\")",
		"action": "block",
		"ratelimit": {
				"characteristics": [
						"cf.colo.id",
						"http.request.headers[\"x-api-key\"]"
				],
				"score_response_header_name": "my-score",
				"score_per_period": 400,
				"period": 60,
				"mitigation_timeout": 600,
				"counting_expression": ""
		}
	}'
```

To define a specific position for the new rule, include a `position` object in the request body according to the guidelines in [Change the order of a rule in a ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/update-rule/#change-the-order-of-a-rule-in-a-ruleset).

For instructions on creating an entry point ruleset and defining its rules using a single API call, refer to [Add rules to phase entry point rulesets](https://developers.cloudflare.com/ruleset-engine/basic-operations/add-rule-phase-rulesets/).

---

## Next steps

Use the different operations in the [Rulesets API](https://developers.cloudflare.com/ruleset-engine/rulesets-api/) to work with the rule you just created. The following table has a list of common tasks for working with rate limiting rules at the zone level:

| Task | Procedure |
| --- | --- |
| List all rules in ruleset | Use the [Get a zone entry point ruleset](https://developers.cloudflare.com/api/resources/rulesets/subresources/phases/methods/get/) operation with the `http_ratelimit` phase name to obtain the list of configured rate limiting rules and their IDs. For more information, refer to [View a specific ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/view/#view-a-specific-ruleset). |
| Update a rule | Use the [Update a zone ruleset rule](https://developers.cloudflare.com/api/resources/rulesets/methods/update/) operation. You will need to provide the ruleset ID and the rule ID. To obtain these IDs, you can use the [Get a zone entry point ruleset](https://developers.cloudflare.com/api/resources/rulesets/subresources/phases/methods/get/) operation with the `http_ratelimit` phase name. For more information, refer to [Update a rule in a ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/update-rule/). |
| Delete a rule | Use the [Delete a zone ruleset rule](https://developers.cloudflare.com/api/resources/rulesets/methods/delete/) operation. You will need to provide the ruleset ID and the rule ID. To obtain these IDs, you can use the [Get a zone entry point ruleset](https://developers.cloudflare.com/api/resources/rulesets/subresources/phases/methods/get/) operation with the `http_ratelimit` phase name. For more information, refer to [Delete a rule in a ruleset](https://developers.cloudflare.com/ruleset-engine/rulesets-api/delete-rule/). |

These operations are covered in the Ruleset Engine documentation. The Ruleset Engine powers different Cloudflare products, including rate limiting rules.

## More resources

For instructions on deploying rate limiting rules at the account level via API, refer to [Create a rate limiting ruleset via API](https://developers.cloudflare.com/waf/account/rate-limiting-rulesets/create-api/).

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/waf/rate-limiting-rules/create-api/#page","headline":"Create a rate limiting rule via API","description":"Create zone-level rate limiting rules using the Rulesets API.","url":"https://developers.cloudflare.com/waf/rate-limiting-rules/create-api/","inLanguage":"en","image":"https://developers.cloudflare.com/waf/rate-limiting-rules/create-api/og.png?v=826ea4630ff8d408","dateModified":"2026-04-16","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
