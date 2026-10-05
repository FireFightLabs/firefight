---
name: turso_blocked
when: Finding why a Turso database refuses reads or writes, such as queries failing with BLOCKED or clients that cannot connect
tools: [resource_status, get_database, database_analytics]
references: [help/usage-and-billing.md, cloud/allow-rules.md, cloud/limitations.md]
---
1. Call `resource_status` for the database. Reads or writes blocked is said in its status and in `get_database`.
2. On a plan with monthly quotas for rows read, rows written and storage, a query past them fails with the BLOCKED error code until the month ends or the plan changes. Turso counts a row read for every row a statement scans, not every row it returns, so a query without an index can use the quota quickly.
3. Call `database_analytics` for the database's top queries. One that reads many rows for each call is what is spending the quota.
4. When clients cannot connect at all, check the allow rules in `get_database`. A rule lets in only the addresses it lists, so a client on a new address is refused.
5. Say what is blocked, why, and what would lift it: a change to the plan or the quota, an index for the costly query, or a rule for the new address. Each is for a person to make in Turso.
