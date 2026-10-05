# Trace Discovery Queries

All queries require `account_id` and a `SINCE` clause (default: `SINCE 30 minutes ago`). Use `execute_nrql_query`.

All discovery queries use `FACET string(traceId)` (or `string(trace.id)` for **Log only**) to group by trace — each result row = one unique trace. Default LIMIT is 25.

Trace-ID field per event type. Getting this wrong returns **zero rows, not an error**:

| Event | Field |
|---|---|
| `Span` | `traceId` (`trace.id` also works — aliased) |
| `Transaction` | `traceId` |
| `TransactionError` | `traceId` — **there is no `trace.id`** |
| `Log` | `trace.id` — **there is no `traceId`** |

## Span (default)

```sql
SELECT latest(timestamp), max(duration), latest(entity.name),
       latest(appName), latest(email), latest(entity.guid)
FROM Span
WHERE appName = '{app}'
FACET string(traceId)
SINCE 30 minutes ago  -- default; adjust to user's time window
LIMIT 25
```

Common WHERE filters:
- Slow: `duration > 2.0`
- Errors: `error IS TRUE`
- Endpoint: `request.uri LIKE '/api/checkout%'`
- Span name: `name LIKE '%PaymentProcess%'`
- HTTP status: `response.status >= 500`
- Datastore: `category = 'datastore' AND duration > 1.0`
- Entity: `entity.guid = 'MTIzNDV8...'`
- User: `email = 'user@example.com'` (unreliable)

## Transaction

```sql
SELECT latest(timestamp), max(duration), latest(name),
       latest(appName), latest(httpResponseCode)
FROM Transaction
WHERE appName = '{app}'
FACET string(traceId)
SINCE 30 minutes ago  -- default; adjust to user's time window
LIMIT 25
```

Common WHERE filters:
- Slow: `duration > 5`
- Failed: `error IS TRUE`
- Endpoint: `request.uri LIKE '/api/checkout%'`
- Status: `httpResponseCode >= 500` — valid on `Transaction` (unlike `TransactionError`, where it does not
  exist) and numeric, so it compares directly. Coverage is only partial;
  `response.status` covers more but is a **string**, so it needs `numeric(response.status) >= 500`.

## TransactionError

```sql
-- Note: traceId (camelCase!) — TransactionError has NO trace.id
SELECT latest(timestamp), latest(error.class), latest(error.message),
       max(duration), latest(transactionName), latest(appName),
       latest(response.status), latest(entityGuid)
FROM TransactionError
WHERE appName = '{app}' AND traceId IS NOT NULL
FACET string(traceId)
SINCE 30 minutes ago  -- default; adjust to user's time window
LIMIT 25
```

Common WHERE filters:
- Error class: `error.class = 'java.lang.NullPointerException'`
- Error message: `error.message LIKE '%timeout%'`
- Endpoint: `request.uri LIKE '/api/checkout%'`
- HTTP status: `numeric(response.status) >= 500` — `response.status` is a **string**, so a bare `>= 500`
  returns zero rows. `http.statusCode` is numeric but sparsely populated; `httpResponseCode` is legacy/absent.
- Expected errors excluded: `error.expected IS FALSE`

## Log

```sql
-- Note: trace.id (dot notation!) for Log events
SELECT latest(timestamp), latest(message), latest(level),
       latest(service.name)
FROM Log
WHERE level = 'ERROR' AND service.name = '{service}'
  AND trace.id IS NOT NULL
FACET string(trace.id)
SINCE 30 minutes ago  -- default; adjust to user's time window
LIMIT 25
```

Common WHERE filters:
- Pattern: `message LIKE '%timeout%'`
- Service: `service.name = 'payment-service'`

## Cross-reference (once you have a traceId)

```sql
-- Spans for a known trace
SELECT name, duration, appName FROM Span WHERE traceId = '{id}'

-- Transaction for a known trace
SELECT name, duration, request.uri FROM Transaction WHERE traceId = '{id}'

-- Logs for a known trace (note dot notation)
SELECT message, level FROM Log WHERE trace.id = '{id}'

-- Errors for a known trace (camelCase — TransactionError has no trace.id)
SELECT error.class, error.message, transactionName, duration
FROM TransactionError WHERE traceId = '{id}'
```

To join `TransactionError` to `Log`, alias the Log side so the keys match:

```sql
FROM TransactionError
  LEFT JOIN ( FROM Log SELECT latest(message) AS logMessage
              FACET trace.id AS traceId LIMIT MAX ) ON traceId
SELECT latest(error.message), latest(logMessage)
FACET string(traceId) SINCE 30 minutes ago
```

## No results?

0. **Confirm the field exists first** — a wrong attribute name returns empty rather than erroring:
   `SELECT keyset() FROM <EventType> SINCE 1 day ago`
1. Widen the time window (try 1–2 hours, max 4 hours)
2. Drop filters one by one
3. Try a different event type
