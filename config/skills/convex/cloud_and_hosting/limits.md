---
name: convex_limits
when: Convex functions fail or slow down because they read too much, run too long or conflict on writes
tools: [search_errors, function_errors, search_logs]
references: [advisor/SKILL.md, insights/SKILL.md]
---
1. Call `search_errors` for the window and read the error words. Convex stops a query or mutation that reads or writes too much in one transaction (documents scanned, data read, documents written), runs user code for more than about a second, or keeps conflicting with other mutations.
2. For a write conflict, call `function_errors` with `text` set to changed while this mutation was being run. The error names the table and a document. Convex retries a conflicting mutation several times before it gives up, so many retried executions on one table mean many calls touch the same documents, such as a single counter.
3. For a read limit, call `search_logs` with `text` set to the function's path. Documents a filter throws away still count as read, so the usual fix is an index that narrows the query, or paginating it.
4. For an action timing out, the logs show what it was waiting on, usually a service it calls.
5. Say which limit is hit, by which function and on which table, and the fix Convex's documentation suggests for it. A fix is a code change for the team, since Firefight cannot change a deployment.
