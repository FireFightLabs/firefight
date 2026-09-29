---
description: API endpoints for managing lists and list items.
title: Lists API endpoints
image: https://developers.cloudflare.com/waf/tools/lists/lists-api/endpoints/og.png?v=a967f57d1a56fefa
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/waf/llms.txt  
> Use this file to discover all available pages before exploring further.

# Lists API endpoints

Last updated Apr 16, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/waf/tools/lists/lists-api/endpoints/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

To invoke a [Lists API](https://developers.cloudflare.com/api/resources/rules/subresources/lists/) operation, append the endpoint to the Cloudflare API base URL:

`https://api.cloudflare.com/client/v4/`

For authentication instructions, refer to the Cloudflare API's [Get started](https://developers.cloudflare.com/fundamentals/api/get-started/) page.

For help with making API calls and paginating results, refer to [Make API calls](https://developers.cloudflare.com/fundamentals/api/how-to/make-api-calls/).

Note

The Lists API endpoints require a value for `{account_id}`.

To retrieve a list of accounts to which you have access, use the [List Accounts](https://developers.cloudflare.com/api/resources/accounts/methods/list/) operation and note the IDs of the accounts you want to manage.

The Lists API supports the operations outlined below. Visit the associated links for examples.

## Manage lists

### Create a list

- **Operation**: [Create a list](https://developers.cloudflare.com/api/resources/rules/subresources/lists/methods/create/)
- **Method and endpoint**: `POST accounts/{account_id}/rules/lists`
- **Notes**: Creates an empty list.

### Get lists

- **Operation**: [Get lists](https://developers.cloudflare.com/api/resources/rules/subresources/lists/methods/list/)
- **Method and endpoint**: `GET accounts/{account_id}/rules/lists`
- **Notes**:
  - Fetches all lists for the account.
  - This request does not fetch the items in the lists.

### Get a list

- **Operation**: [Get a list](https://developers.cloudflare.com/api/resources/rules/subresources/lists/methods/get/)
- **Method and endpoint**: `GET accounts/{account_id}/rules/lists/{list_id}`
- **Notes**:
  - Fetches a list by its ID.
  - This request does not display the items in the list.

### Update a list

- **Operation**: [Update a list](https://developers.cloudflare.com/api/resources/rules/subresources/lists/methods/update/)
- **Method and endpoint**: `PUT accounts/{account_id}/rules/lists/{list_id}`
- **Notes**:
  - Updates the `description` of a list.
  - You cannot edit the `name` or `kind`, and you cannot update items in a list. To update an item in a list, use the [Update all list items](#update-all-list-items) operation.

### Delete a list

- **Operation**: [Delete a list](https://developers.cloudflare.com/api/resources/rules/subresources/lists/methods/delete/)
- **Method and endpoint**: `DELETE accounts/{account_id}/rules/lists/{list_id}`
- **Notes**: Deletes the list, but only when no [filters](https://developers.cloudflare.com/firewall/api/cf-filters/) reference it.

## Manage items in a list

Nearly all the operations for managing items in a list are asynchronous. When you add or delete a large amount of items to or from a list, there may be a delay before the bulk operation is complete.

Asynchronous list operations return an `operation_id`, which you can use to monitor the status of an API operation. To monitor the status of an asynchronous operation, use the [Get bulk operation status](https://developers.cloudflare.com/api/resources/rules/subresources/lists/subresources/bulk_operations/methods/get/) endpoint and specify the ID of the operation you want to monitor.

When you make requests to a list while a bulk operation on that list is in progress, the requests are queued and processed in sequence (first in, first out). Requests for successful asynchronous operations return an `HTTP 201` status code.

### Get list items

- **Operation**: [Get list items](https://developers.cloudflare.com/api/resources/rules/subresources/lists/subresources/items/methods/list/)
- **Method and endpoint**: `GET accounts/{account_id}/rules/lists/{list_id}/items[?search={query}]`
- **Notes**:
  - Fetches items in a list (all items, by default).
  - Items are sorted in ascending order.
  - In the case of IP lists, CIDRs are sorted by IP address, then by the subnet mask.
  - To filter returned items, use the optional `search` query string parameter. For more information, refer to the [Get list items](https://developers.cloudflare.com/api/resources/rules/subresources/lists/subresources/items/methods/list/) API operation.

### Get a list item

- **Operation**: [Get a list item](https://developers.cloudflare.com/api/resources/rules/subresources/lists/subresources/items/methods/get/)
- **Method and endpoint**: `GET accounts/{account_id}/rules/lists/{list_id}/items/{item_id}`
- **Notes**: Fetches an item from a list by ID

### Create list items

- **Operation**: [Create list items](https://developers.cloudflare.com/api/resources/rules/subresources/lists/subresources/items/methods/create/)
- **Method and endpoint**: `POST accounts/{account_id}/rules/lists/{list_id}/items`
- **Notes**:
  - Appends a new item or items to a list.
  - Replaces entries that already exist in the list, does not delete any items.
  - Overwrites the `comment` of the original item.
  - The response includes an `operation_id`.

### Update all list items

- **Operation**: [Update all list items](https://developers.cloudflare.com/api/resources/rules/subresources/lists/subresources/items/methods/update/)
- **Method and endpoint**: `PUT accounts/{account_id}/rules/lists/{list_id}/items`
- **Notes**:
  - Deletes all current items in the list and replaces them with `items`.
  - When `items` is empty, deletes **all** items in the list.
  - The response includes an `operation_id`.

### Delete list items

- **Operation**: [Delete list items](https://developers.cloudflare.com/api/resources/rules/subresources/lists/subresources/items/methods/delete/)
- **Method and endpoint**: `DELETE accounts/{account_id}/rules/lists/{list_id}/items`
- **Notes**:
  - Deletes specified list items.
  - The response includes an `operation_id`.

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/waf/tools/lists/lists-api/endpoints/#page","headline":"Lists API endpoints","description":"API endpoints for managing lists and list items.","url":"https://developers.cloudflare.com/waf/tools/lists/lists-api/endpoints/","inLanguage":"en","image":"https://developers.cloudflare.com/waf/tools/lists/lists-api/endpoints/og.png?v=a967f57d1a56fefa","dateModified":"2026-04-16","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
