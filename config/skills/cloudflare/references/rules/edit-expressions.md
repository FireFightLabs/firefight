---
description: Edit expressions in the Cloudflare dashboard using the Expression Builder, which allows for a visual approach, or using the Expression Editor, in which you type the expression.
title: Edit expressions in the dashboard
image: https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/edit-expressions/og.png?v=ef1a48e45e605d85
---

[Skip to content](#main-content)

> Documentation Index  
> Fetch the complete documentation index at: https://developers.cloudflare.com/ruleset-engine/llms.txt  
> Use this file to discover all available pages before exploring further.

# Edit expressions in the dashboard

Last updated Apr 16, 2026|Copy as Markdown| [View as Markdown](https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/edit-expressions/index.md)| [Agent setup](https://developers.cloudflare.com/agent-setup/)

In the Cloudflare dashboard, there are two options for editing [expressions](https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/):

- [Expression Builder](https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/edit-expressions/#expression-builder): Allows you to create expressions using drop-down lists, emphasizing a visual approach to defining an expression.
- [Expression Editor](https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/edit-expressions/#expression-editor): A text-only interface that supports advanced features, such as grouping symbols and functions for transforming and validating values.

In general, you can switch back and forth between the Expression Builder and the Expression Editor. However, the Expression Builder does not support advanced features like:

- [Nested expressions](#create-nested-expressions)
- [Function calls](https://developers.cloudflare.com/ruleset-engine/rules-language/functions/)

The builder may also not show all the fields you can use in the expression you are editing.

If you use advanced expression features or enter unlisted fields in your expression when using the editor, you may not be able to switch to the Expression Builder. You will get a warning popup stating that the expression is not supported in the builder. To proceed, you may discard any changes made in the editor, or cancel the switch and continue working in the editor.

## Expression Builder

The Expression Builder allows you to visually create rule expressions by using drop-down lists and entering field values to define one or multiple sub-expressions.

![The Expression Builder interface used to visually define expressions](https://developers.cloudflare.com/cdn-cgi/image/onerror=redirect,width=820,height=235,format=webp/_astro/expression-builder.Cg2aqK5m.png)

The **Expression Preview** displays the expression in text:

```sql
(ip.src.country ne "GB")
```

The Expression Builder will [automatically escape](#escape-special-characters) the backslash (`\`) and double quote (`"`) special characters in string literals when using the [quoted string syntax](https://developers.cloudflare.com/ruleset-engine/rules-language/values/#quoted-string-syntax).

## Expression Editor

The **Expression Editor** is a text-only interface for defining rule expressions that supports the entire specification of Cloudflare's [Rules language](https://developers.cloudflare.com/ruleset-engine/rules-language/), including parentheses as grouping symbols.

![The Expression Editor used to enter advanced expressions](https://developers.cloudflare.com/cdn-cgi/image/onerror=redirect,width=840,height=160,format=webp/_astro/expression-editor.CI-o8RRS.png)

To access the Expression Editor, select **Edit expression** next to the **Expression Preview**:

![Selecting Edit expression in the Create custom rule page to switch to the Expression Editor](https://developers.cloudflare.com/cdn-cgi/image/onerror=redirect,width=820,height=235,format=webp/_astro/expression-builder.Cg2aqK5m.png)

To switch back from the Expression Editor to the Expression Builder, select **Use expression builder**.

### Escape special characters

In expressions using the [quoted string syntax](https://developers.cloudflare.com/ruleset-engine/rules-language/values/#quoted-string-syntax), all backslash (`\`) and double quote (`"`) characters in string literals must be escaped. The visual Expression Builder will automatically escape these special characters by prepending a backslash such that `\` and `"` become `\\` and `\"`, respectively.

```txt
# Example of an expression with a " character written using quoted string syntax
http.request.uri.path eq "/foo\"bar"
```

The Expression Builder supports both the [quoted string syntax](https://developers.cloudflare.com/ruleset-engine/rules-language/values/#quoted-string-syntax) and the [raw string syntax](https://developers.cloudflare.com/ruleset-engine/rules-language/values/#raw-string-syntax). In the raw string syntax, there are no special characters or escape sequences, so all characters up to the ending delimiter are interpreted as is.

```txt
# Example of an expression with a " character written using the raw string syntax
http.request.uri.path eq r#"/foo"bar"#
```

When you select *Matches regex* in the **Operator** dropdown in the dashboard, the expression preview will automatically use the raw string syntax. In other situations, you may need to switch to the Expression Editor to manually enter a string using the raw string syntax. In this case, switching back to the Expression Builder will keep the syntax you used in the editor.

When you write a [regular expression](https://developers.cloudflare.com/ruleset-engine/rules-language/operators/#regular-expression-matching) using the quoted string syntax, you may need to perform additional escaping — refer to [Quoted string syntax](https://developers.cloudflare.com/ruleset-engine/rules-language/values/#quoted-string-syntax) for details.

To write complex regular expressions, Cloudflare recommends that you use the [raw string syntax](https://developers.cloudflare.com/ruleset-engine/rules-language/values/#raw-string-syntax), which needs less escaping.

### Create nested expressions

The Expression Editor supports parentheses as [grouping symbols](https://developers.cloudflare.com/ruleset-engine/rules-language/operators/#grouping-symbols). Use parentheses to explicitly group and nest expressions and, in turn, create highly targeted expressions.

The following rule expression will match requests from any visitor who is not from Malaysia and tries to access WordPress URI paths.

```txt
((http.request.uri.path contains "/xmlrpc.php") or (http.request.uri.path
contains "/wp-login.php") or (http.request.uri.path contains "/wp-admin/"
and not http.request.uri.path contains "/wp-admin/admin-ajax.php" and not
http.request.uri.path contains "/wp-admin/theme-editor.php")) and
ip.src.country ne "MY"
```

Only the Expression Editor supports nested expressions such as the one above. If you create a rule with nested expressions in the Expression Editor and try to switch to the Expression Builder, a dialog will warn you that the expression is not supported in the builder. You will be prompted to **Discard changes** and switch to the Expression Builder or **Cancel** and continue working in the editor.

Note

String comparison in rule expressions is case-sensitive. To account for possible variations of string capitalization in an expression, you can use the [`lower()`](https://developers.cloudflare.com/ruleset-engine/rules-language/functions/#lower) function and compare the result with a lowercased string, like in the following example:

```txt
lower(http.request.uri.path) contains "/wp-login.php"
```

## Expression validation

Cloudflare validates all expressions before saving them, so if your expression has errors, you will receive an error message in the Cloudflare dashboard, similar to the following:

```txt
Filter parsing error (1:313): ((http.request.uri.path contains
"/xmlrpc.php") or (http.request.uri.path contains "/wp-login.php") or
(http.request.uri.path contains "/wp-admin/" and not
http.request.uri.path contains "/wp-admin/admin-ajax.php" and not
http.request.uri.path contains "/wp-admin/theme-editor.php")) and
ip.src.country ne "MY") ^ unrecognised input
```

Was this helpful?

YesNo

## On this page

[![](https://developers.cloudflare.com/_astro/logo.te5VL_aD.svg)Docs](https://developers.cloudflare.com/)

```json
{"@context":"https://schema.org","@type":"TechArticle","@id":"https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/edit-expressions/#page","headline":"Edit expressions in the dashboard","description":"Edit expressions in the Cloudflare dashboard using the Expression Builder, which allows for a visual approach, or using the Expression Editor, in which you type the expression.","url":"https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/edit-expressions/","inLanguage":"en","image":"https://developers.cloudflare.com/ruleset-engine/rules-language/expressions/edit-expressions/og.png?v=ef1a48e45e605d85","dateModified":"2026-04-16","publisher":{"@type":"Organization","name":"Cloudflare","description":"One platform for your apps, agents, and workforce. Build, secure, and scale without managing infrastructure","url":"https://www.cloudflare.com/","sameAs":["https://github.com/cloudflare","https://www.linkedin.com/company/cloudflare","https://x.com/cloudflare"],"logo":{"@type":"ImageObject","url":"https://developers.cloudflare.com/logo.svg"},"address":{"@type":"PostalAddress","streetAddress":"101 Townsend St","addressLocality":"San Francisco","addressRegion":"CA","postalCode":"94107","addressCountry":"US"},"contactPoint":[{"@type":"ContactPoint","contactType":"Customer Support","url":"https://support.cloudflare.com/","availableLanguage":["English"]},{"@type":"ContactPoint","contactType":"Sales","url":"https://www.cloudflare.com/contact/","availableLanguage":["English"]}]},"isPartOf":{"@type":"WebSite","@id":"https://developers.cloudflare.com/#website","name":"Cloudflare Docs","url":"https://developers.cloudflare.com/"}}
```
