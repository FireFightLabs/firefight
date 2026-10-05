This document describes, at a high level, the Logging query language that
you use to query and filter Cloud Logging data.

For in-depth information about the Logging query language design, see
the [Google API formal specifications for filtering](https://google.aip.dev/160).

For examples of common queries you might want to use, see
[Sample queries using the Logs Explorer](https://docs.cloud.google.com/logging/docs/view/query-library).

## Overview

You can use the Logging query language in the Logs Explorer in the
Google Cloud console, the
[Logging API](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/entries/list),
or the
[command-line interface](https://docs.cloud.google.com/logging/docs/api/gcloud-logging#v2_api_commands).
You can use the Logging query language to query data and to write filters to
create [sinks](https://docs.cloud.google.com/logging/docs/routing/overview#sinks) and
[log-based metrics](https://docs.cloud.google.com/logging/docs/logs-based-metrics).

A query is a Boolean expression that specifies a subset of all the log entries
in your selected Google Cloud resource, such as a Google Cloud project
or folder.

You can build queries based on the [`LogEntry`](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)
[indexed field](https://docs.cloud.google.com/logging/docs/view/logging-query-language#indexed-fields) using the logical operators `AND` and `OR`.
Using the `resource.type` field in the following examples, the
Logging query language grammar looks like this:

- Simple restriction: `resource.type = "k8s_cluster"`

- Conjunctive restriction: `resource.type = "k8s_cluster" AND severity = "ERROR"`

  > [!NOTE]
  > **Note:** When a query contains multiple statements, you can either specify how those statements are joined or rely on Cloud Logging implicitly adding the conjunctive restriction, `AND`, between the statements. For example, suppose a query or filter dialog contains two statements, `resource.type = "gce_instance"` and `severity >= "ERROR"`. The actual query is `resource.type = "gce_instance" AND severity >= "ERROR"`. Cloud Logging supports both disjunctive restrictions, `OR`, and conjunctive restrictions, `AND`. When you use `OR` statements, we recommend that you group the clauses with parentheses.

- Disjunctive restriction: `resource.type = "k8s_cluster" OR resource.type = "gce_instance"`

  - Alternatively: `resource.type = ("k8s_cluster" OR "gce_instance")`
- Complex conjunctive/disjunctive expression: `resource.type = "k8s_cluster" AND (severity = "ERROR" OR "error")`

The following is an example of a query:

```
resource.type = "gce_instance" AND
severity >= "ERROR" AND
NOT textPayload:robot
```

This query matches log entries from Compute Engine that have severity values
of at least `ERROR` and whose `textPayload` field doesn't contain the string
`robot` anywhere inside it. String comparisons aren't case sensitive. The names
`resource`, `severity`, and `textPayload` are defined in the
[`LogEntry`](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry) type.

## Syntax notation

The following sections provide an overview of the Logging query language
syntax, and discuss in detail how queries are structured and how matching is
performed. Some of the examples use [comments](https://docs.cloud.google.com/logging/docs/view/logging-query-language#comments) to provide explanatory
text.

Note the following:

- The length of a query can't exceed 20,000 characters.

- The Logging query language is case-insensitive, with the exception
  of regular expressions and logical operators, like `AND` and `OR`.
  Logical operators must be capitalized.

### Syntax summary

The Logging query language syntax can be thought of in terms of *queries*
and *comparisons*.

A *query* is a string containing an *expression*:

```
expression = ["NOT"] comparison { ("AND" | "OR") ["NOT"] comparison }
```

A *comparison* is either a single value or a Boolean expression:

```
"The cat in the hat"
resource.type = "k8s_cluster"
```

The first line is an example of a comparison that is a single value. These
types of comparisons are *global restrictions* . Each field of a log entry is
compared to the value by implicitly using the **has** operator. For this
example, if any field in a `LogEntry`, or if its payload, contains the phrase
"The cat in the hat", then the comparison is successful.

The second line is an example of a comparison that is a Boolean expression of
the form `[FIELD_NAME] [OP] [VALUE]`. A comparison has three components:

- `[FIELD_NAME]` is a field in a log entry. For example, `resource.type`.

- `[OP]` is a comparison operator. For example, `=`.

- `[VALUE]` is a number, string, function, or parenthesized expression.
  For example, `"k8s_cluster"`. For JSON null values, use
  [`NULL_VALUE`](https://developers.google.com/protocol-buffers/docs/reference/google.protobuf#nullvalue).

### Boolean operators

The Boolean operators `AND` and `OR` are
[short-circuit operators](https://en.wikipedia.org/wiki/Short-circuit_evaluation).
The `NOT` operator has the highest precedence, followed by `OR` and `AND`
in that order. For example, the following two expressions are equivalent:

```
"a" OR NOT "b" AND NOT "c" OR "d"
("a" OR (NOT "b")) AND ((NOT "c") OR "d")
```

You can omit the `AND` operator between comparisons. You can also replace
the `NOT` operator with the `-` (minus) operator. For example, the
following two queries are the same:

```
a="b" AND c="d" AND NOT e="f"
a="b" c="d" -e="f"
```

This documentation always uses `AND` and `NOT`.

For all filters except filters used by [log views](https://docs.cloud.google.com/logging/docs/logs-views),
you can use `AND`, `OR`, and `NOT` operators. Log views only support `AND` and
`NOT` operations.

To combine `AND` and `OR` rules in the same expression, you must nest the
rules using parentheses. If you don't use parentheses, your query might not
work as intended.

Boolean operators always need to be capitalized. Lowercase `and`, `or`,
and `not` are parsed as search terms.

### Comparisons

Comparisons have the following form:

```
[FIELD_NAME] [OP] [VALUE]
```

A comparison has three components:

- **\[FIELD_NAME\]**: is the field path identifier of a field in a log entry.
  The following are examples of these identifiers:

  ```
  resource.type
  resource.labels.zone
  resource.labels.project_id
  insertId
  jsonPayload.httpRequest.protocol
  labels."compute.googleapis.com/resource_id"
  ```

  If a component of a field path identifier has special characters,
  then the component needs to be double-quoted. For example,
  `compute.googleapis.com/resource_id` must be double quoted because
  it contains a forward slash `/`.

  For details, see [field path identifiers](https://docs.cloud.google.com/logging/docs/view/logging-query-language#field_path_identifiers)
  in this document.
- **\[OP\]**: is a comparison operator, one of the following:

  ```
  =           -- equal
  !=          -- not equal
  > < >= <=   -- numeric ordering
  :           -- "has" matches any substring in the log entry field
  =~          -- regular expression search for a pattern
  !~          -- regular expression search not for a pattern
  ```

To learn how to search log entries using regular expressions, see
[Using regular expressions](https://docs.cloud.google.com/logging/docs/view/logging-query-language#regular-expressions).

- **\[VALUE\]** : is a number, string, function, or *parenthesized* expression. Strings are used to represent arbitrary text, plus Boolean, enumeration, and byte-string values. The `[VALUE]` is converted to the field's type prior to the comparison. For JSON null values, use [`NULL_VALUE`](https://developers.google.com/protocol-buffers/docs/reference/google.protobuf#nullvalue).

To filter for a JSON null value, use the following syntax:

```
jsonPayload.field = NULL_VALUE      -- includes "field" with null value
NOT jsonPayload.field = NULL_VALUE  -- excludes "field" with null value
```

If `[VALUE]` is a parenthesized Boolean combination of comparisons,
then the field name and the comparison operator are applied to each element.
For example:

```
jsonPayload.cat = ("longhair" OR "shorthair")
jsonPayload.animal : ("nice" AND "pet")
```

The first comparison checks that the field `cat` has the value "longhair" or
"shorthair". The second checks that the value of the field `animal` contains
both of the words "nice" and "pet", in any order.

> [!NOTE]
> **Note:** If a query is written with comparisons on multiple lines, as in the previous example, the comparisons are joined together using the Boolean `AND` operator.

#### Field path identifiers

All log entries are instances of type `LogEntry`. The
identifier that is (or begins) the left-hand side of a comparison must be a
field defined in the `LogEntry` type. For details on the possible identifiers
and their values, see the [`LogEntry`](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry) type.

Here is the current list of log entry fields. Each field is followed by the
next level of names for that field, if applicable:

- `httpRequest`: { `cacheFillBytes`, `cacheHit`, `cacheLookup`, `cacheValidatedWithOriginServer`, `latency`, `protocol`, `referer`, `remoteIp`, `requestMethod`, `requestSize`, `requestUrl`, `responseSize`, `serverIp`, `status`, `userAgent` }
- `insertId`
- `jsonPayload` { *variable* }
- `labels` { *variable* }
- `logName`
- `metadata` { `systemLabels`, `userLabels` }
- `operation`{ `id`, `producer`, `first`, `last` }
- `protoPayload` { `@type`, *variable* }
- `receiveTimestamp`
- `resource` { `type`, `labels` }
- `severity`
- `sourceLocation`: { `file`, `line`, `function` }
- `spanId`
- `textPayload`
- `timestamp`
- `trace`

Following are examples of field path identifiers you can use in your
comparisons:

- **resource.type** : If your first path identifier is `resource`, then the next
  identifier must be a field in the
  [`MonitoredResource`](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/MonitoredResource)type.

- **httpRequest.latency** : If your first path identifier is `httpRequest`,
  then the next identifier must be a field in the [`HttpRequest`](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#HttpRequest)
  type.

- **labels.\[KEY\]** If your first path identifier is `labels`, then the next
  identifier, `[KEY]`, must be one of the keys from the key-value pairs
  appearing in the `labels` field.

- **logName** : Since the `logName` field is a string, you can't follow it by
  any subfield names.

When you query [map](https://developers.google.com/protocol-buffers/docs/reference/proto3-spec#map_field) or [struct](https://developers.google.com/protocol-buffers/docs/reference/google.protobuf#google.protobuf.Struct) fields, you must preserve their
keys' letter case and formatting in your expression.

For example, `jsonPayload` is a struct field, so a field name nested inside
`jsonPayload` like `jsonPayload.end_time` differs from
`jsonPayload.endTime`. Similarly, for a map field like `labels`, the label key
`labels.env_name` is different than `labels.envName`. In contrast, when
querying the regular protocol buffer field
[protoPayload](https://docs.cloud.google.com/logging/docs/reference/v2/rpc/google.logging.v2#logentry), you
don't need to preserve case.

For information on the `LogEntry` field types, see the
[google.logging.v2](https://docs.cloud.google.com/logging/docs/reference/v2/rpc/google.logging.v2) reference.

#### Special characters

If a `LogEntry` field contains special characters, the log field must be quoted.
For example:

```
jsonPayload.":name":apple

jsonPayload."foo.bar":apple

jsonPayload."\"foo\"":apple
```

For the list of special characters, see the `string` section in
[Values and conversions](https://docs.cloud.google.com/logging/docs/view/logging-query-language#values_conversions).

For more information on using field path identifiers that reference objects or
arrays, see [Object and array types](https://docs.cloud.google.com/logging/docs/view/logging-query-language#object_array_types) in this document.

#### Monitored resource types

For faster queries, specify a monitored resource type. For a list of resource
types, see [Monitored resource types](https://docs.cloud.google.com/logging/docs/api/v2/resource-list).

For example, Compute Engine VMs use the resource type `gce_instance`
and Amazon EC2 instances use `aws_ec2_instance`. The following example shows
how to limit your queries to both type of VMs:

```
resource.type = ("gce_instance" OR "aws_ec2_instance")
```

The monitored resource type values in logs are indexed. Using substring matches
for them results in slower queries.

#### Missing fields

If you use a field name in a query, and that field doesn't appear in a log
entry, then the field is **missing** , **undefined** , or **defaulted**:

- If the field is part of the log entry's payload (`jsonPayload`
  or `protoPayload`), or if it is in a label in the `labels` section of
  the log entry, then the field is **missing**. Using a missing field
  won't display an error, but all comparisons using missing fields fail
  silently.

  Examples: `jsonPayload.nearest_store`, `protoPayload.name.nickname`
- If the field is defined in the [`LogEntry`](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)
  type, then the field is **defaulted**. Comparisons are performed as if
  the field were present and had its default value.

  Examples: `httpRequest.remoteIp`, `trace`, `operation.producer`
- Otherwise, the field is **undefined**, which is an error that is detected
  before the query is used.

  Examples: `thud`, `operation.thud`, `textPayload.thud`

To test if a missing or defaulted field exists without testing for a particular
value in the field, use the `:*` comparison. For example, the following
comparison succeeds if the field `operation.id` is explicitly present in a log
entry:

```
operation.id:*
```

Note the behavior of the following queries:

- When you use the Boolean `NOT` operator on a missing field, the result is
  `TRUE`:

  ```
  -- Returns TRUE
  NOT missingField=foo
  ```
- When you use the not equal comparison operator `!=` on a missing field, the
  result is `FALSE`:

  ```
  -- Returns FALSE
  missingField!=foo
  ```

#### Object and array types

Each log entry field can hold a *scalar* , *object* , or *array*.

- A [scalar](https://developers.google.com/protocol-buffers/docs/proto3#scalar) field stores a single value, like `174.4` or `-1`.
  A `string` is also considered a scalar. Fields that can be converted to (or
  from) a string, such as `Duration` and `Timestamp` are also scalar types.

- An object type stores a collection of named values, like the following
  JSON value:

  ```
  {"age": 24, "height": 67}
  ```

  You can refer to value inside an object. For example, if `jsonPayload.x`
  contained the preceding value, then `jsonPayload.x.age` would have the
  value `24`.
- An array field stores a list of values---all of the same
  type. For example, a field holding measurements might have an array
  of numbers:

  ```
  {8.5, 9, 6}
  ```

  When comparisons are performed and `[FIELD_NAME]` is an array field, each
  member of the array is compared to `[VALUE]` and the results are joined
  together using the `OR` operator. For example, if `jsonPayload.shoeSize`
  is an array field that stores `{8.5, 9, 6}`, the comparison:

      jsonPayload.shoeSize < 7

  is equivalent to:

      8.5 < 7 OR 9 < 7 OR 6 < 7

  In this example, the overall comparison evaluates to successful.

#### Values and conversions

The first step in evaluating a comparison is to convert the right-hand side
value to the type of the log entry field. Scalar field types are permitted in
comparisons, along with two additional types whose values are represented as
strings: `Duration` and `Timestamp`. For a list of scalar types, see the
[scalar protocol buffer types](https://developers.google.com/protocol-buffers/docs/proto3#scalar) list. The following table explains
what values can be converted to the log field types:

| Field type | Permitted query value |
|---|---|
| `bool` | "True" or "false" in any letter case. Examples: "True", "true" |
| `bytes` | A string containing any sequence of bytes. Example: "\\377\\377". |
| `Duration` | A string containing a signed decimal number followed by one of the units "ns", "us", "ms", "s", "m", or "h". Durations are accurate to nanoseconds. Example: "3.2s". |
| `enum` | The name of an enumeration type literal, case-insensitive. Examples: "WARNING", which is a value of type [LogSeverity](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#logseverity). |
| `double` | Any number, with or without a sign and an exponent part, or the special value strings "NaN", "-Infinity", and "Infinity" (either capitalized or not). Examples: "-3.2e-8", "nan". |
| `intNN` | Any signed integer that doesn't exceed the size of the type. Example: "-3". |
| `string` | Any string that contains UTF-8 encoded or 7-bit ASCII text. Embedded quotation marks must be escaped with a backslash. String values must be double-quoted to escape the following special characters: - Strings starting with `+` (plus), `-` (minus), or `.` (period). - Strings with `\~` (tilde), `=` (equals), `()` (parentheses), `:` (colon), `\>` (greater than), `\<` (less than), `,` (comma), `.` (period), or `\*` (asterisk). - Any escape sequence, for example `\t`. |
| `Timestamp` | A string in [RFC 3339](https://www.ietf.org/rfc/rfc3339.txt) or [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601) format. Examples: "2024-08-02T15:01:23.045Z" (RFC 3339), "2024-08-02" (ISO 8601). In query expressions, timestamps in RFC 3339 format can specify a timezone with "Z" or `±hh:mm`. Timestamps are represented to nanosecond accuracy. |
| `uintNN` | Any unsigned integer that doesn't exceed the size of the type. Example: "1234". |

If an attempted conversion fails, then the comparison fails.

When a conversion requires a string, you can also use a number or unquoted text
if they don't contain special characters such as spaces and operators.
Similarly, when a conversion requires a number, you can use a string whose
content is a number.

The types `intNN` and `uintNN` represent integer types of various sizes, such as
`int32` and `uint64`. When writing a value to be converted to a 64-bit integer
type, you write the value as a string, such as "9223372036854775807".

### Types of log fields

Here is how the type of a log entry field is determined:

- Log fields defined in the type [`LogEntry`](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry), and in the component
  type are [protocol buffer fields](https://developers.google.com/protocol-buffers/docs/proto3#scalar). Protocol
  buffer fields have explicit types.

- Log fields that are part of `protoPayload` objects are also
  [protocol buffer](https://developers.google.com/protocol-buffers/docs/proto3)
  fields and have explicit types. The name of the protocol buffer type is
  stored in the field `"@type"` of `protoPayload`. For more information,
  see the
  [JSON mapping](https://developers.google.com/protocol-buffers/docs/proto3#json).

  When you are filtering on a field that is associated with the
  [`Any`](https://github.com/protocolbuffers/protobuf/blob/main/src/google/protobuf/any.proto)
  message type, the `value` field is automatically traversed. Therefore,
  don't include it in the query. For more information, see
  [Troubleshooting](https://docs.cloud.google.com/logging/docs/view/logging-query-language#filter-on-any).
- Log fields inside of `jsonPayload` have types that are inferred from the
  field's value when the log entry is received:

  - Fields whose values are unquoted numbers have type `double`.
  - Fields whose values are `true` or `false` have type `bool`.
  - Fields whose values are strings have type `string`.

  Long (64-bit) integers are stored in string fields, because they can't be
  represented exactly as `double` values.
- The `Duration` and `Timestamp` types are recognized only in
  [protocol buffer fields](https://developers.google.com/protocol-buffers/docs/proto3).
  Elsewhere, those values are stored in string fields.

### Comments

Comments start with two dashes (`--`), and any text following the dashes is
ignored until the end of the line. Comments can be placed at the beginning of a
filter, in between terms, and at the end of a filter.

You might use comments for the following cases:

- To annotate your complex filters with information about what a clause does:

  <br />

  ```
   -- All of our target users are emitted by Compute Engine instances.
   resource.type = "gce_instance"
   -- Looking for logs from "alex".
   jsonPayload.targetUser = "alex"
  ```

  <br />

- To quickly enable or disable a clause by adding or removing the comment
  prefix:

  <br />

  ```
   resource.type = "gce_instance"
   -- jsonPayload.targetUser = "alex"
   jsonPayload.targetUser = "kiran"
   -- jsonPayload.targetUser = "sasha"
  ```

  <br />

> [!NOTE]
> **Note:** Comments count towards the maximum filter character limit of 20,000 characters.

### Comparison operators

The meaning of the equality (`=`, `!=`) and inequality (`<`, `<=`, `>`, `>=`)
operators depends on the underlying type of the left-hand field name.

- All numeric types: Equality and inequality have their normal meaning for numbers.
- `bool`: Equality means the same Boolean value. Inequality is defined by `true`\>`false`.
- `enum`: Equality means the same enumeration value. Inequality uses the underlying numeric values of the enumeration literals.
- `Duration`: Equality means the same duration length. Inequality is based on the length of the duration. Example: as durations, `"1s"`\>`"999ms"`.
- `Timestamp`: Equality means the same instant in time. If *a* and *b* are `Timestamp` values, *a* \< *b* means *a* is earlier in time than *b*.
- `bytes`: Operands are compared byte by byte, left-to-right.
- `string`: Comparisons ignore letter case. Specifically, both operands are first normalized using [NFKC_CF Unicode normalization](http://unicode.org/reports/tr44/#NFKC_Casefold) and then use lexicographic comparisons. However, regular expression searches aren't normalized. For more information on searching log entries using regular expressions, see [Using regular expressions](https://docs.cloud.google.com/logging/docs/view/logging-query-language#regular-expressions).

The substring operator (`:`) is applicable to `string` and `bytes`, and is
handled like equality except that the right-hand operand need only equal some
part of the left-hand field. Substring matches on indexed fields don't take
advantage of log indexes.

### Global restrictions

If the comparison consists of a single value, it is called a
*global restriction* . Logging uses the **has** (`:`) operator to determine
if any field in a log entry, or if its payload, contains the global restriction.
If it does, then the comparison succeeds.

The simplest query written in terms of a global restriction is a
single value:

```
"The Cat in The Hat"
```

You can combine global restrictions using the `AND` and `OR` operators for a
more interesting query. For example, if you want to display all log entries
that have a field that contains `cat` and a field that contains either `hat`
or `bat`, write the query as:

```
("cat" AND ("hat" OR "bat"))
```

In this case, there are three global restrictions: `cat`, `hat` and `bat`. These
global restrictions are applied separately and the results are combined, just
as if the expression had been written without parentheses.

A global restriction is one way to query your logs for a particular value.
For example, if you are looking in your activity log for entries containing any
mention of `GCE_OPERATION_DONE`, you can use the following query:

```
logName = "projects/my-project-id/logs/compute.googleapis.com%2Factivity_log" AND
"GCE_OPERATION_DONE"
```

Instead of using global restrictions, which can be slow, we recommend that
you use the
[built-in `SEARCH` function](https://docs.cloud.google.com/logging/docs/view/logging-query-language#search-functions)
and query indexed fields. For more information,
see [Finding log entries quickly](https://docs.cloud.google.com/logging/docs/view/logging-query-language#finding-quickly) in this document.

### Functions

You can use built-in functions as global restrictions in queries:

```
function = identifier ( [ argument { , argument } ] )
```

where `argument` is a value, field name, or a *parenthesized* expression.
The functions are described in the following sections.

#### log_id

The `log_id` function is useful when creating a custom
[log view](https://docs.cloud.google.com/logging/docs/logs-views) on a
[log bucket](https://docs.cloud.google.com/logging/docs/store-log-entries) that contains log entries from
many Google Cloud projects, folders, or organizations.

The single argument to the `log_id` function is a non-URL-encoded log ID:

```
log_id(non-URL-encoded log ID)
```

For example, the following query returns all activity audit logs:

```
log_id("cloudaudit.googleapis.com/activity")
```

In the previous query, the argument consists only of
alphanumeric characters and special characters, (`/`, `_`, `-`, `.`).

> [!NOTE]
> **Note:** Don't URL-encode the argument of the `log_id` function. A query statement that uses URL-encoding of the argument, like `log_id("cloudaudit.googleapis.com%2Factivity")`, won't match any log entries.

#### cast

The `cast` function accepts two parameters; the [`LogEntry`](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry) field to
be casted, and the data type in which the field is converted to:

```
cast([FIELD], [TYPE][, OPTION])
```

The parameters of the previous expression are defined as follows:

- `[FIELD]`: The name of a field in the log entry, such as `logName` or
  `jsonPayload.a_field`.

- `[TYPE]`: The data type, such as `STRING`, `INT64`, `FLOAT64`, `BOOL`.

  - `TIMESTAMP`, or `DURATION`: Some data types offer additional options, such as specifying an [IANA Timezone Database](https://www.iana.org/time-zones) timezone for the `TIMESTAMP` data type.

For example, the following query casts the `timestamp` field into a STRING
and specifies the `America/New_York` timezone:

```
cast(timestamp, STRING, TIME_ZONE("America/New_York")) =~ "^2025-04-02.*"
```

#### regexp_extract

Use the `regexp_extract` function to find the first substring that matches a
regular expression:

```
REGEXP_EXTRACT([FIELD], [REGULAR_EXPRESSION])
```

In the previous expression, the fields are defined as follows:

- `[FIELD]`: The name of a field in the log entry, such as `logName` or `jsonPayload.a_field`.
- `[REGULAR_EXPRESSION]`: The [RE2 regular expression](https://github.com/google/re2/wiki/Syntax) that must contain one capture group (`(...)`). A non-capturing group `(?:...)` must be used if additional grouping is required for the regular expression. Multiple capture groups or no capture groups result in an error.

You can chain the `cast` and `regexp_extract` functions:

```
CAST(REGEXP_EXTRACT(CAST(timestamp, STRING), "\\d+:\\d+:(\\d+)"), INT64) < 30
```

The previous example casts the `timestamp` field as a string. The regular
expression captures the value of the seconds field from the `timestamp` string,
and then casts it into an integer to perform a numeric comparison. The query
result lists a log entry when the seconds field of its timestamp is less than
30.

#### source

The `source` function matches log entries from a particular resource in
the organizations, folders, and Google Cloud projects hierarchy.

The `source` function doesn't match child resources. For example, using
`source(folders/folder_123)` matches logs from the `folder_123` resource,
and not logs from the Google Cloud project resources within `folder_123`.

To query for logs at a particular resource level, use the following syntax:

    source(RESOURCE_TYPE/RESOURCE_ID)

| Resource | Example query |
|---|---|
| Organization | `source(organizations/`<var translate="no">ORGANIZATION_ID</var>`)` |
| Folder | `source(folders/`<var translate="no">FOLDER_ID</var>`)` |
| Google Cloud projects | `source(projects/`<var translate="no">PROJECT_ID</var>`)` |

> [!NOTE]
> **Note:** The `source` function is useful when creating a custom [log view](https://docs.cloud.google.com/logging/docs/logs-views) on a [log bucket](https://docs.cloud.google.com/logging/docs/store-log-entries) that contains log entries from many Google Cloud projects, folders, or organizations.

#### sample

The `sample` function selects a fraction of the total number of log entries:

```
sample([FIELD], [FRACTION])
```

`[FIELD]` is the name of a field in the log entry, such as `logName` or
`jsonPayload.a_field`. The value of the field determines whether the log entry
is in the sample. The field type must be a string or numeric value.
Setting `[FIELD]` to `insertId` is a good choice, because every log entry has
a different value for that field.

`[FRACTION]` is the fraction of log entries that have values for `[FIELD]` to
include. It is a number greater than 0.0 and no greater than 1.0. For example,
if you specify `0.01`, then the sample contains roughly one percent of all log
entries that have values for `[FIELD]`. If `[FRACTION]` is 1, then all the log
entries that have values for `[FIELD]` are chosen.

**Example** : The following query returns 25 percent of the log entries
from log `syslog`:

```
logName = "projects/my-project/logs/syslog" AND sample(insertId, 0.25)
```

**Details** :
A deterministic algorithm, based on hashing, is used to determine if a log entry
is included, or excluded, from the sample. The accuracy
of the resulting sample is dependent on the distribution of the hashed values.
If the hashed values aren't uniformly distributed,
then the resulting sample can be skewed. Additionally, if
`[FIELD]` always contains the same value, then
the resulting sample contains either all log entries or no log entries.

If `[FIELD]` does appear in a log entry, then:

- A hash of the value is computed.
- The hashed value, which is a number, is divided by the maximum possible hashed value.
- If the resulting fraction is less than or equal to `[FRACTION]`, the log entry is included in the sample; otherwise it is excluded from the sample.

If `[FIELD]` doesn't appear in a log entry, then:

- If `[FIELD]` is part of the log entry's payload or `labels` sections, the log entry isn't selected for the sample, even if `[FRACTION]` is 1.
- Otherwise, the log entry is treated as if `[FIELD]` is in the log entry and the value of `[FIELD]` is the default value. The default value is determined by the [`LogEntry`](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry) type. For more information on missing and defaulted fields, see [Missing fields](https://docs.cloud.google.com/logging/docs/view/logging-query-language#missing_fields) in this document.

To exclude log entries with defaulted fields from the sample, use the
field-exists operator, `:*`. The following query produces a 1 percent sample of
log entries that have explicitly supplied a value for `field`:

```
field:* AND sample(field, 0.01)
```

#### ip_in_net

The `ip_in_net` function determines if an IP address in a log entry is contained
in a subnet. You might use this to tell if a request comes from an internal or
external source. For example:

```
ip_in_net([FIELD], [SUBNET])
```

`[FIELD]` is a string-valued field in the log entry that contains an IP address
or range. The field can be repeating, in which case only one of the repeated
fields has to have an address or range contained in the subnet.

`[SUBNET]` is a string constant for an IP address or range. It is an error if
`[SUBNET]` isn't a legal IP address or range, as described later in this
section.

**Example** : The following query tests an IP address in the payload of log
entries from the log `my_log`:

```
logName = "projects/my_project/logs/my_log" AND
ip_in_net(jsonPayload.realClientIP, "10.1.2.0/24")
```

**Details** : If, in a log entry, `[FIELD]` is missing, defaulted, or it does not
contain a legal IP address or range, then the function returns false. For more
information on missing and defaulted fields, see
[Missing fields](https://docs.cloud.google.com/logging/docs/view/logging-query-language#missing_fields) in this document.

Examples of the supported IP addresses and ranges follow:

- IPv4: `10.1.2.3`
- IPv4 subnet: `10.1.2.0/24`
- CIDR IPv6: `1234:5678:90ab:cdef:1234:5678:90ab:cdef`
- CIDR IPv6 subnet: `1:2::/48`

### `SEARCH` function

> [!NOTE]
> **Note:** If you use the search bar to perform text searches and if you don't wrap your search terms in double quotes, then the `SEARCH` function is used. For example, if you enter `world` in the search bar, then Logging runs the query `SEARCH("world")`.

You can use the built-in `SEARCH` function to find strings in your log data:

```
SEARCH([query])
SEARCH([field], [query])
```

Both forms of the `SEARCH` function contain a `query` argument, which must
be formatted as a string literal. In the first form, the entire log entry is
searched. In the second form, you specify the field in the log entry to search.

You must specify the `query` field. If this field isn't specified, then an
error is returned.

When the `SEARCH` function is processed, the `query` string is processed by
a text analyzer that splits the string into tokens. Cloud Logging always
performs case-insensitive comparisons, even for tokens
wrapped with backticks. This behavior differs from that of BigQuery,
which preserves case in tokens wrapped with backticks.
For information about the analyzer rules, see the BigQuery document
[Text analyzer rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/text-analysis).

When constructing a search, consider the following:

- Tokens are case-insensitive. The following functions produce the same
  results:

  ```
  SEARCH("world")
  SEARCH("World")
  ```

  The previous functions match a log entry when a single field contains the
  token "world". Because `SEARCH` performs exact matches and not substring
  matches, the previous functions don't match a field whose value is
  "worldwide".
- If you don't specify the field to search, then the `SEARCH` function
  matches a log entry when that log entry contains all tokens. However,
  the order of tokens doesn't matter and the tokens aren't required to
  be found in the same field of the log entry.

  The following functions produce the same results, and they match a log entry
  that contains the tokens "hello" and "world":

  ```
  SEARCH("hello world")
  SEARCH("World hello")
  ```
- If you specify the field to search, then the `SEARCH` function only
  searches that field. A match occurs when that field contains all tokens;
  however, the order of tokens doesn't matter.

  The following functions produce a match only when the `textPayload` field
  contains the tokens "hello" and "world":

  ```
  SEARCH(textPayload, "hello world")
  ```
- To impose a case-insensitive but exact match on a phrase,
  enclose the phrase in backticks.
  For example, the following functions match the string "hello world":

  ```
  SEARCH("`hello world`")
  SEARCH("`Hello World`")
  SEARCH("`HELLO WORLD`")
  ```

  Because backticks are used in the following functions, they produce different
  results:

  ```
  SEARCH("`hello world`")
  SEARCH("`world hello`")
  ```

The Logging query language supports different ways that you can search
your log data. When searching for a string, it is more efficient to use the
`SEARCH` function than to perform a global search or a substring search.
However, you can't use the `SEARCH` function to match non-text fields.
For guidance on performing search operations, see
[Minimize global and substring searches](https://docs.cloud.google.com/logging/docs/view/logging-query-language#minimize-searching).

### Searching by time

In the interface, you can set specific limits on the
date and time of log entries to show. For example, if you add the following
conditions to your query, the results pane displays exactly the log entries
in the indicated 30-minute period and you won't be able to scroll outside
of that date range:

```
timestamp >= "2023-11-29T23:00:00Z"
timestamp <= "2023-11-29T23:30:00Z"
```

When writing a query with a timestamp, you must use dates and times in the
format shown previously.

You can also search log entries using `timestamp` shortcuts. For example,
you can enter a date with a comparison operator to get all log entries after a
certain day:

    timestamp > "2023-11-29"

> [!NOTE]
> **Note:** Logging interprets query expressions that use the `YYYY-MM-DD` format as `YYYY-MM-DDT00:00:00Z`.

### Using regular expressions

You can use regular expressions to build queries and create filters for
sinks, metrics, and wherever log filters are used. For example, you can use
regular expressions in the
[Logs Explorer](https://docs.cloud.google.com/logging/docs/view/logs-explorer-interface) and with
[Google Cloud CLI](https://docs.cloud.google.com/logging/docs/reference/tools/gcloud-logging).

A regular expression is a sequence of characters that define a search. The
Logging query language uses the RE2 syntax. For a complete explanation of
the RE2 syntax, see the [RE2 wiki on GitHub](https://github.com/google/re2/wiki/Syntax).

Regular expression queries have the following characteristics:

- Only fields of the string type can be matched with a regular expression.

- String normalization isn't performed; for example, `kubernetes` isn't
  considered the same as `KUBERNETES`. For more information,
  see the [Comparison operators](https://docs.cloud.google.com/logging/docs/view/logging-query-language#comparison_operators) section.

- Queries are case sensitive and aren't anchored by default.

- Boolean operators can be used between multiple regular expressions on the
  right side of the regular expression comparison operator, `=~` and `!~`.

A regular expression query has the following structure:

**Match a pattern**:

```
jsonPayload.message =~ "regular expression pattern"
```

**Does not match a pattern**:

```
jsonPayload.message !~ "regular expression pattern"
```

The `=~` and `!~` changes the query to a regular expression query, and the
pattern you're trying to match must be within double quotation marks. To query
for patterns that *contain* double quotation marks, escape them using a
backslash.

> [!NOTE]
> **Note:** Regular expression queries offer a potential speed increase over a regular text query. For example, querying for log entries that contain both `foo` and `bar` can be faster using the regular expression query `jsonPayload.message =~ "foo.*bar|bar.*foo"` than the substring query `jsonPayload.message : ("foo" AND "bar")`.

#### Examples querying logs using regular expressions

| Query type | Example |
|---|---|
| Standard query | `sourceLocation.file =~ "foo"` |
| Query with case-insensitive search | `labels.subnetwork_name =~ "(?i)foo"` |
| Query containing quotation marks | `jsonPayload.message =~ "field1=\"bar.*\""` |
| Query using a boolean `or` | `labels.pod_name =~ "(foo|bar)"` |
| Query using anchors | `logName =~ "/my%2Flog$"` |
| Query not matching a pattern | `labels.pod_name !~ "foo"` |
| Query using boolean operator | `labels.env =~ ("^prod.*server" OR "^staging.*server")` |
| Query that begins with a value | `logName =~ "^foo"` |
| Query that ends with a value | `logName =~ "foo$"` |

> [!NOTE]
> **Note:** For a detailed explanation of the RE2 syntax, see the [RE2 wiki page](https://github.com/google/re2/wiki/Syntax).

## Finding log entries quickly

To find log entries efficiently, do the following:

- Query using indexed fields.
- Minimize the number of log entries that must be searched.

### Use indexed fields

Logging always indexes the following [`LogEntry`](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry) fields:

- [resource.type](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)
- [resource.labels.\*](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)
- [logName](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)
- [severity](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)
- [timestamp](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#FIELDS.timestamp)
- [insertId](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)
- [operation.id](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#LogEntryOperation)
- [trace](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)
- [httpRequest.status](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry#HttpRequest)
- [labels.\*](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)
- [split.uid](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry)

You can also add [custom indexed fields](https://docs.cloud.google.com/logging/docs/analyze/custom-index) to
any log bucket or make use of the `SEARCH` function to accelerate your query.

### Optimize your queries

Make your searches faster by reducing the number of logs, the number of log
entries, or the time span of your searches. Even better, you can reduce all
three.

#### Example: Use the `SEARCH` function

Instead of doing global or substring searches, you can use the `SEARCH`
function to make use of indexes to optimize your queries.

#### Example: Use the right log name

Specify the log containing the log entries you're interested in. Be sure you
know the actual log name by inspecting one of your log entries. For example, the
results pane shows that the Compute Engine section contains a log named
"activity". On closer inspection of the Admin Activity audit log entries, the log
is actually named "cloudaudit.googleapis.com/activity".

The following comparison is **incorrect**. It doesn't match anything because it
uses the wrong log name:

```
logName = "projects/my-project-id/logs/activity"   -- WRONG!
```

The following comparison is **correct**. It chooses log entries from the
Admin Activity audit log entries. You must URL-encode the log name, as shown:

```
logName = "projects/my-project-id/logs/cloudaudit.googleapis.com%2Factivity"
```

#### Example: Choose the right log entries

If you know that the log entries you want are coming from a particular VM
instance, then specify it. Check for the right label names by inspecting one of
the log entries that you want to search for. In the following example,
`instance_id` is one of the indexed labels:

```
resource.type = "gce_instance" AND
resource.labels.instance_id = "6731710280662790612"
logName = "projects/my-project-id/logs/cloudaudit.googleapis.com%2Factivity"
```

#### Example: Choose the right time period

Specify a time period to search in. A quick way of determining useful
timestamps in RFC 3339 format is to use the GNU/Linux `date` command:

```
$ date --rfc-3339=s
2023-06-27 17:39:00-04:00
$ date --rfc-3339=s --date="3 hours ago"
2023-06-27 14:40:00-04:00
$ date --rfc-3339=s --date="5 hours ago"
2023-06-27 12:40:00-04:00
```

Use the values of these timestamps in the following queries. To create a
timestamp acceptable to Logging, replace the space between the
date and time with the letter `T`.

For example, to search within the last three hours:

    timestamp >= "2023-06-27T14:40:00-04:00"

As another example, to search between three and five hours ago:

```
timestamp >= "2023-06-27T12:40:00-04:00" AND
timestamp <= "2023-06-27T14:40:00-04:00"
```

### Minimize disjunctive restrictions

Queries that use only conjunctive restrictions, `AND`, can make better use
of indexes. You can use disjunctive restriction, `OR`, but these queries can
be slow and cannot make use of indexes.

For example, `SEARCH("foo") AND SEARCH("bar")` makes use of indexes and will be
faster than a query like `SEARCH("foo") OR SEARCH("bar")`.

### Minimize global and substring searches

Avoid the temptation to take shortcuts when typing queries.

#### Example: Don't use global searches

If you're searching for a log entry with "Hello Kitty" in the payload:

- **Don't** use a global search. For one reason, they are all substring
  searches:

  <br />

  ```
     "Hello Kitty"   -- THIS CAUSES A SLOW SEARCH!
     
  ```

  <br />

- **Do** limit the search to a single field, even if you must keep the
  substring search:

  <br />

  ```
     textPayload:"Hello Kitty"
     
  ```

  <br />

- **Do** use an equality test if you can:

  <br />

  ```
     textPayload = "Hello Kitty"
     
  ```

  <br />

- **Do** reference individual fields in a payload, if your log entries
  have structured payloads:

  <br />

  ```
     jsonPayload.my_favorite_cat = "Hello Kitty"
     
  ```

  <br />

- **Do** use an indexed field to restrict the search:

  <br />

  ```
     logName = "projects/my-project_id/logs/somelog" AND
     jsonPayload.my_favorite_cat = "Hello Kitty"
     
  ```

  <br />

- **Do** use the `SEARCH` function and specify the complete text to match.
  The `SEARCH` function performs a case-insensitive match:

  <br />

        SEARCH("Hello Kitty")
        
  <br />

  **Don't** use the `SEARCH` function and specify partial text. For
  example, the following function doesn't match "Hello Kitty".

  <br />

        SEARCH("Hello Kit")
        
  <br />

### Searching examples

The log entries shown are the ones that match a query.
If the **Jump to time** menu contains a value, then
the display scrolls to that point in time. Here are some query examples:

`resource.type=k8s_cluster`

:   Finds all Google Kubernetes Engine log entries. For a list of resource types,
    see [Monitored resource list](https://docs.cloud.google.com/logging/docs/api/v2/resource-list).

    As you type, the query pane suggests completions for fields
    like `resource.type`.

`resource.type=k8s_cluster AND logName:request_log`

:   Finds log entries for Google Kubernetes Engine clusters from log names containing
    `request_log`. Note several things:

    - The `=` operator is exact equality. The resource type must be exactly `"k8s_cluster"` except for letter case.
    - The `:` operator means "has". The `logName` field must contain `request_log`, in any letter case. The actual log name is much longer. Using `:` might result in slower searches.
    - The two comparisons are joined by `AND`. You can also use `OR`, but `AND` is assumed if you leave out the operator.

`resource.type = (gce_instance OR aws_ec2_instance) AND severity >= ERROR`

:   Finds log entries with either of two resource types: Compute Engine VM
    instance or AWS EC2 VM instance. The log entries must have `severity` of at
    least `ERROR`, which is equivalent to selecting **ERROR** in the query
    interface's severity menu.

`logName = "projects/[PROJECT_ID]/logs/cloudaudit.googleapis.com%2Factivity"`

:   Finds all the Admin Activity audit log entries in the project `[PROJECT_ID]`.
    Audit logs all use the same log name in a project, but have different
    resource types. The log ID, `cloudaudit.googleapis.com/activity` must be
    URL-encoded in the log name. Using equality in the comparison speeds up the
    search. For more information, see
    [Understanding audit logs](https://docs.cloud.google.com/logging/docs/audit/understanding-audit-logs).

`unicorn`

:   Finds log entries containing `unicorn` in any field, in any letter case. A
    search term that isn't part of a field comparison is an "all fields" query.

`unicorn phoenix`

:   Finds log entries that contain `unicorn` in some field and `phoenix` in
    some field.

`textPayload:(unicorn phoenix)`

:   Finds log entries whose `textPayload` field contains both `unicorn` and
    `phoenix` in any order---the `AND` is implicit between the two words.

`textPayload:"unicorn phoenix"`

:   Finds log entries whose `textPayload` field contains the string
    `"unicorn phoenix"`.

`NOT textPayload: "unicorn phoenix"`

:   Finds log entries whose `textPayload` field does *not contain* the string
    `"unicorn phoenix"`. This type of query reduces unwanted log entries.

`timestamp >= "2023-11-29T23:00:00Z" timestamp <= "2023-11-29T23:30:00Z"`

:   Finds log entries within a 30-minute period.

## Troubleshooting

### Syntax issues

If you have problems with your queries' expressions, check the
following:

- Your query obeys the syntax rules, with matched parentheses and quotation
  marks.

- Your log entry field names are correctly spelled.

- Boolean operations are in uppercase letters (`AND`, `OR`, `NOT`).

- Ensure that you're using
  [`NULL_VALUE`](https://developers.google.com/protocol-buffers/docs/reference/google.protobuf#nullvalue)
  to represent JSON null values.

- Boolean expressions as global restrictions or as the right-hand side of
  comparisons should be parenthesized for clarity. For example, the
  following two queries look the same, but are not:

  ```
  insertId = "ABC-1" OR "ABC-2"  -- ERROR!?
  insertId = ("ABC-1" OR "ABC-2")
  ```
- Unquoted text must not contain any special characters. When in doubt, add
  double quotation marks. For example, in the following, the first comparison
  is illegal
  because of the embedded substring operator (`:`). The comparison must be
  written with quotation marks:

  ```
  insertId = abc:def  -- ILLEGAL!
  insertId = "abc:def"
  ```

  > [!NOTE]
  > **Note:** If you use the search bar and if you don't wrap the search terms in double quotes, then the [`SEARCH` function](https://docs.cloud.google.com/logging/docs/view/logging-query-language#search-functions) is used. The `SEARCH` function performs a search along token boundaries. For example, if you enter `world` in the search bar, then Logging runs the query `SEARCH("world")`. The previous query matches `world` but it doesn't match `worlds`.

- The [Google Cloud CLI](https://docs.cloud.google.com/logging/docs/reference/tools/gcloud-logging) requires
  the query to be in double quotes. To use double quotes for escaping special
  characters using the `gcloud logging` command, wrap the entire query with
  single quotes instead:

  ```
  gcloud logging read 'resource.type=gce_instance AND jsonPayload.message="Stopped Unattended Upgrades Shutdown."'
  gcloud logging read 'timestamp>="2020-06-17T21:00:00Z"'
  ```

- When you are filtering on a field that is associated with the
  [`Any`](https://github.com/protocolbuffers/protobuf/blob/main/src/google/protobuf/any.proto)
  message type, the `value` field is automatically traversed. Therefore,
  don't include `value` in the query.

  For example, the
  [`Status`](https://github.com/grpc/grpc/blob/master/src/proto/grpc/status/status.proto)
  field in an
  [`AuditLog`](https://docs.cloud.google.com/logging/docs/reference/audit/auditlog/rest/Shared.Types/AuditLog)
  message has a `details` field that is of type `google.protobuf.Any`.
  To query the `details` field, omit the `value` field when specifying the
  filter:
  - Yes

    ```
    protoPayload.status.details.conditionNotMet.userVisibleMessage =~ "Specified reservation.*"
    ```
  - No

    ```
    protoPayload.status.details.value.conditionNotMet.userVisibleMessage =~ "Specified reservation.*"
    ```