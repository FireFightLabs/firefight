---
description: Learn about comparison, logical operators, and grouping symbols in Cloudflare's Rules language. Understand precedence and how to structure expressions.
title: Operators and grouping symbols
image: https://developers.cloudflare.com/ruleset-engine/rules-language/operators/og.png?v=6d9b481e4dc42e76
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/ruleset-engine/llms.txt  
> Use this file to discover all available pages before exploring further.

# Operators and grouping symbols

Last updated Oct 1, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/ruleset-engine/rules-language/operators/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

The Cloudflare Rules language supports comparison and logical operators:

- [Comparison operators](#comparison-operators) specify how values defined in an expression must relate to the actual HTTP request value for the expression to return `true`.
- [Logical operators](#logical-operators) combine two expressions to form a compound expression and use order of precedence to determine how an expression is evaluated.

[Grouping symbols](#grouping-symbols) allow you to organize expressions, enforce precedence, and nest expressions.

## Comparison operators

Comparison operators return `true` when a value from an HTTP request matches a value defined in an expression.

This is the general pattern for using comparison operators:

```txt
<field> <comparison_operator> <value>
```

The Rules language supports these comparison operators:

| Name | Operator Notation | | Supported Data Types | | | |
| --- | --- | --- | --- | --- | --- | --- |
|  | English | C-like | String<sup>1</sup> | IP | Number | Example (operator in bold) |
| Equal | `eq` | `==` | ✅ | ✅ | ✅ | `http.request.uri.path **eq** "/articles/2008/"` |
| Not equal | `ne` | `!=` | ✅ | ✅ | ✅ | `ip.src **ne** 203.0.113.0` |
| Less than | `lt` | `<` | ✅ | ❌ | ✅ | `cf.waf.score **lt** 10` |
| Less than<br>or equal | `le` | `<=` | ✅ | ❌ | ✅ | `cf.waf.score **le** 20` |
| Greater than | `gt` | `>` | ✅ | ❌ | ✅ | `cf.waf.score **gt** 25` |
| Greater than<br>or equal | `ge` | `>=` | ✅ | ❌ | ✅ | `cf.waf.score **ge** 60` |
| Contains | `contains` |  | ✅ | ❌ | ❌ | `http.request.uri.path **contains** "/articles/"` |
| [Wildcard](#wildcard-matching)<br>(case-insensitive) | `wildcard` |  | ✅ | ❌ | ❌ | `http.request.uri.path **wildcard** "/articles/*"` |
| [Strict wildcard](#wildcard-matching)<br>(case-sensitive) | `strict wildcard` |  | ✅ | ❌ | ❌ | `http.request.uri.path **strict wildcard** "/AdminTeam/*"` |
| [Matches<br>regex](#regular-expression-matching)<sup>2</sup> | `matches` | `~` | ✅ | ❌ | ❌ | `http.request.uri.path **matches** "^/articles/200[7-8]/$"` |
| Is in set of values / list<sup>3</sup> | `in` |  | ✅ | ✅ | ✅ | `ip.src **in** { 203.0.113.0 203.0.113.1 }`<br>`ip.src.asnum **in** $<LIST>` |

<sup>1</sup> All string operators are case-sensitive unless explicitly stated as case-insensitive, such as the `wildcard` operator.  
<sup>2</sup> Access to the `matches` operator requires a Cloudflare Business or Enterprise plan.  
<sup>3</sup> Currently, not all Cloudflare products support lists in their expressions. For more information on lists, refer to [Inline lists](https://developers.cloudflare.com/ruleset-engine/rules-language/values/#inline-lists) and [Lists](https://developers.cloudflare.com/waf/tools/lists/).

Caution

Comparison operators entered using English notation (such as `eq`, `lt`, and `gt`) must be written in lowercase.

### Compare dynamic values

Equality and ordering operators can compare dynamic values. The right side can be a field, indexed value, or function result. This works with `eq` (`==`), `ne` (`!=`), `lt` (`<`), `le` (`<=`), `gt` (`>`), and `ge` (`>=`). Both values must have the same scalar data type. Supported types vary by operator. Refer to the [comparison operator table](#comparison-operators).

*Examplestxt*

```txt
# Compare the current request path with its original value
http.request.uri.path ne raw.http.request.uri.path

# Compare the lengths of two request values
len(http.request.uri.path) gt len(http.request.uri.query)

# Use a query parameter, or fall back to "/" if it is missing
http.request.uri.path eq coalesce(http.request.uri.args["expected_path"][0], "/")
```

The [`coalesce()` function](https://developers.cloudflare.com/ruleset-engine/rules-language/functions/#coalesce) returns the first value that is not nil.

For comparison results involving nil, refer to [Missing values](https://developers.cloudflare.com/ruleset-engine/rules-language/values/#missing-values).

### Additional operators in the Cloudflare dashboard

The Cloudflare dashboard may show the following additional operators, depending on the exact field and the type of rule:

- *starts with* (corresponding to the [`starts_with()`](https://developers.cloudflare.com/ruleset-engine/rules-language/functions/#starts_with) function): Returns `true` when a string starts with a given substring, and `false` otherwise.
- *ends with* (corresponding to the [`ends_with()`](https://developers.cloudflare.com/ruleset-engine/rules-language/functions/#ends_with) function): Returns `true` when a string ends with a given substring, and `false` otherwise.
- *is in list* (corresponding to `<FIELD> in $<LIST_NAME>`): Returns `true` when the field value is present in the specified [list](https://developers.cloudflare.com/waf/tools/lists/), and `false` otherwise. For more information, refer to [Use lists in expressions](https://developers.cloudflare.com/waf/tools/lists/use-in-expressions/).
- *is not in list* (corresponding to `not <FIELD> in $<LIST_NAME>`): Returns `true` when the field value is not present in the specified [list](https://developers.cloudflare.com/waf/tools/lists/), and `false` otherwise. For more information, refer to [Use lists in expressions](https://developers.cloudflare.com/waf/tools/lists/use-in-expressions/).

Note

When writing your own custom expressions, you must use the `starts_with()` and `ends_with()` functions in function calls, not as operators. For example:

```txt
# Valid function call
ends_with(http.request.uri.path, ".html")

# Invalid use of ends_with function
http.request.uri.path ends_with ".html"
```

### Comparing string values

String comparison in rule expressions is case-sensitive. To account for possible variations of string capitalization in an expression, you can use the [`lower()`](https://developers.cloudflare.com/ruleset-engine/rules-language/functions/#lower) function and compare the result with a lowercased string, like in the following example:

```txt
lower(http.request.uri.path) contains "/wp-login.php"
```

[Wildcard matching](#wildcard-matching) is only supported with the `wildcard` and `strict wildcard` operators, and [regular expression matching](#regular-expression-matching) is only supported with the `matches` operator.

### Wildcard matching

The `wildcard` operator performs a case-insensitive match between a field value and a literal string containing zero or more `*` metacharacters. Each `*` metacharacter represents zero or more characters. The `strict wildcard` operator performs a similar match, but is case-sensitive.

When using the `wildcard`/`strict wildcard` operator, the entire field value must match the literal string with wildcards (the literal after the operator).

*Example Atxt*

```txt
# The following expression:
http.request.full_uri wildcard "http*://example.com/a/*"

# Would match the following URIs:
# - https://example.com/a/           (the '*' matches zero characters)
# - http://example.com/a/
# - https://example.com/a/page.html
# - https://example.com/a/sub/folder/?name=value

# Would NOT match the following URIs:
# - https://example.com/ab/
# - https://example.com/b/page.html
# - https://sub.example.com/a/
```

<details>

<summary>

Example B

</summary>

```txt
# The following expression:
http.request.full_uri wildcard "*.example.com/*/page.html"

# Would match the following URIs:
# - http://sub.example.com/folder/page.html
# - https://admin.example.com/team/page.html
# - https://admin.example.com/team/subteam/page.html

# Would NOT match the following URIs:
# - https://example.com/ab/page.html                   ('*.example.com' matches only subdomains)
# - https://sub.example.com/folder2/page.html?s=value  (http.request.full_uri includes the query string and its full value does not match)
# - https://sub.example.com/a/                         ('page.html' is missing)
```

Slashes (<code>/</code>) have no special meaning in wildcard matches. In this example, the second <code>*</code> metacharacter in the expression <code>http.request.full_uri wildcard "*.example.com/*/page.html"</code> matched <code>folder</code>, <code>team</code>, and <code>team/subteam</code>.

</details>

<details>

<summary>

Example C

</summary>

```txt
# The following expression:
http.request.full_uri wildcard "*.example.com/*" or http.request.full_uri wildcard "http*://example.com/*"

# Would match the following URIs:
# - https://example.com/folder/list.htm
# - https://admin.example.com/folder/team/app1/
# - https://admin.example.com/folder/team/app1/?s=foobar
```

</details>

The matching algorithm used by the `wildcard` operator is case-insensitive. To perform case-sensitive wildcard matching, use the `strict wildcard` operator.

To enter a literal `*` character in a literal string with wildcards you must escape it using `\*`. Additionally, you must also escape `\` using `\\`. Two unescaped `*` characters in a row (`**`) in a wildcard literal string are considered invalid and cannot be used. If you need to perform character escaping, it is recommended that you use the [raw string syntax](https://developers.cloudflare.com/ruleset-engine/rules-language/values/#raw-string-syntax) to specify a literal string with wildcards.

Wildcard matching versus regex matching

The `wildcard`/`strict wildcard` operators always consider the entire field value (left-side operand) when determining if there is a match. The `matches` operator can match a partial value.

### Regular expression matching

Customers on Business and Enterprise plans have access to the `matches` operator. Regular expression matching is performed using the Rust regular expression engine.

If you are using a regular expression, you can test it using a tool like [Regular Expressions 101 ↗︎](https://regex101.com/?flavor=rust&regex=) or [Rustexp ↗︎](https://rustexp.lpil.uk/).

For more information on regular expressions, refer to [String values and regular expressions](https://developers.cloudflare.com/ruleset-engine/rules-language/values/#string-values-and-regular-expressions).

## Logical operators

Logical operators combine two or more expressions into a single compound expression. A compound expression has this general syntax:

```txt
<expression> <logical_operator> <expression>
```

### Supported logical operators

Each logical operator has an [order of precedence](#order-of-precedence). The order of precedence (along with [grouping symbols](#grouping-symbols)) determines the order in which Cloudflare evaluates logical operators in an expression. The `not` operator ranks first in order of precedence.

| Name | English<br>Notation | C-like<br>Notation | Example | Order of Precedence |
| --- | --- | --- | --- | --- |
| Logical NOT | `not` | `!` | `**not** ( http.host eq "www​.cloudflare​.com" and ip.src in {203.0.113.0/24} )` | 1 |
| Logical AND | `and` | `&&` | `http.host eq "www​.cloudflare​.com" **and** ip.src in {203.0.113.0/24}` | 2 |
| Logical XOR<br>(exclusive OR) | `xor` | `^^` | `http.host eq "www​.cloudflare​.com" **xor** ip.src in {203.0.113.0/24}` | 3 |
| Logical OR | `or` | `\|\|` | `http.host eq "www​.cloudflare​.com" **or** ip.src in 203.0.113.0/24` | 4 |

Caution

Logical operators entered using English notation (such as `not`, `and`, and `or`) must be written in lowercase.

### Order of precedence

When writing compound expressions, it is important to be aware of the precedence of logical operators so that your expression is evaluated the way you expect.

For example, consider the following generic expression, which uses `and` and `or` operators:

```java
Expression1 and Expression2 or Expression3
```

If these operators had no order of precedence, it would not be clear which of two interpretations is correct:

1. Match when Expression 1 and Expression 2 are both true **or** when Expression 3 is true.
2. Match when Expression 1 is true **and** either Expression 2 or Expression 3 is true.

Since the logical `and` operator has precedence over logical `or`, the `and` operator must be evaluated first. Interpretation 1 is correct.

To avoid ambiguity when working with logical operators, use grouping symbols so that the order of evaluation is explicit.

## Grouping symbols

The Rules language supports parentheses (`(`,`)`) as grouping symbols. Grouping symbols allow you to organize expressions, enforce precedence, and nest expressions.

Only the [Expression Editor](https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/edit-expressions/#expression-editor) and the [Cloudflare API](https://developers.cloudflare.com/api/) support grouping symbols. The [Expression Builder](https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/edit-expressions/#expression-builder) does not.

### Group expressions

Use parentheses to explicitly group expressions that should be evaluated together. In this example, the parentheses do not alter the evaluation of the expression, but they unambiguously call out which logical operators to evaluate first.

```java
(Expression1 and Expression2) or Expression3
```

Because grouping symbols are so explicit, you are less likely to make errors when you use them to write compound expressions.

### Enforce precedence

Grouping symbols are a powerful tool to enforce precedence for grouped elements of a compound expression. In this example, parentheses force the logical `or` operator to be evaluated before the logical `and`:

```java
Expression1 and (Expression2 or Expression3)
```

Without parentheses, the logical `and` operator would take precedence.

### Nest expressions

You can nest expressions grouped by parentheses inside other groups to create very precise, sophisticated expressions, such as this example for a rule designed to block access to a domain:

```sql
(
 (http.host eq "api.example.com" and http.request.uri.path eq "/api/v2/auth") or
 (http.host matches "^(www|store|blog)\.example\.com" and http.request.uri.path contains "wp-login.php") or
 ip.src.country in {"CN" "TH" "US" "ID" "KR" "MY" "IT" "SG" "GB"} or ip.src.asnum in {12345 54321 11111}
) and not ip.src in {11.22.33.0/24}
```

Note that when evaluating the precedence of logical operators, parentheses inside strings delimited by quotes are ignored, such as those in the following regular expression, drawn from the example above:

```sql
"^(www|store|blog)\.example\.com"
```

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/ruleset-engine/rules-language/operators/#page","headline":"Operators and grouping symbols","description":"Learn about comparison, logical operators, and grouping symbols in Cloudflare's Rules language. Understand precedence and how to structure expressions.","url":"https://developers.cloudflare.com/ruleset-engine/rules-language/operators/","inLanguage":"en","image":"https://developers.cloudflare.com/ruleset-engine/rules-language/operators/og.png?v=6d9b481e4dc42e76","dateModified":"2026-10-01","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
