---
name: cloudflare_cost
when: Watching or explaining what the Cloudflare account spends, a bill that grew, or which service or zone costs more than before
tools: [get_resource_map, resource_status, search, execute]
signals: [cost]
---
Start from the account on the resource map. `get_resource_map` names the Cloudflare account that holds each zone and its id, which every billing endpoint takes, and `resource_status` with a domain reads its zone. Both only read, so the person is not asked.

1. Find the billing endpoints with `search` before `execute`. Cloudflare's billable usage (accounts/{account_id}/billable-usage, with from and to) answers what was charged, a row per service and zone with BilledCost, BillingCurrency, ChargePeriodStart, ServiceName and ZoneName. With no dates it answers the current billing period, and a range has to include the day the period starts. Billing history (accounts/{account_id}/billing/history) lists what was invoiced and paid.
2. Read both with `execute`, which only reads here. Add up BilledCost by day and by ServiceName, and by ZoneName for what grew where.
3. Compare this period with the one before, and the same days of the last one. Billable usage covers pay as you go accounts, so a contract account may answer with less. Say so rather than calling it flat.
4. Cloudflare refusing the read means the connection's token lacks Billing Read on the account. Say so, and that an admin adds it to the token.
