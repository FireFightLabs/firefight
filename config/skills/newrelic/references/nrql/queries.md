# NRQL Reference

## Aggregator functions

Pick the function that matches the question rather than defaulting to `count()` or `average()`.

| What the question asks for | Use |
|---|---|
| How many rows / how many non-null values | `count(*)`, `count(attribute)` |
| How many distinct values — or list them | `uniqueCount(attribute)`, `uniques(attribute)` |
| Total, or a typical value | `sum()`, `average()`, `median()` |
| Biggest / smallest | `max()`, `min()` |
| First or last value in the window | `earliest()`, `latest()` |
| Spread, tail latency, distribution | `percentile(attribute, 50, 95, 99)`, `stddev()`, `histogram(attribute, ceiling, buckets)` |
| Share of the whole, as a percentage | `percentage(count(*), WHERE <condition>)` |
| Aggregate only a subset, inline | `filter(count(*), WHERE <condition>)` |
| Per-minute / per-second rate | `rate(count(*), 1 minute)` |
| Rate of change, or a projection | `derivative(attribute, 1 minute)`, `predictLinear(attribute, 1 hour)` |
| Apdex score | `apdex(duration, t: 0.5)` |
| Step-by-step conversion through a flow | `funnel(session, WHERE …, WHERE …)` |
| How much falls under a threshold | `cdfPercentage(attribute, threshold)`, `getCdfCount(attribute, threshold)` |

## Resolving an absolute/compound time range

Pass the user's phrasing to `convert_time_period_to_epoch_ms` as `text_input`. If `errors` comes back populated, the wording — not the meaning — is usually the problem: re-order it as `<range> <day>` (`"from 9am until 30 minutes later yesterday"`) and retry once. If it fails again, ask the user for explicit start and end times rather than guessing.

```json
{"data": {"start_time_ms": 1786006800000, "end_time_ms": 1786008600000}, "errors": null, "warnings": null}
```

Put the two numbers straight into the query — don't hand-convert epoch to a date string:

```sql
SELECT count(*) FROM Transaction SINCE 1786006800000 UNTIL 1786008600000
```
