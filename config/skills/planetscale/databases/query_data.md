---
name: planetscale_query_data
when: Looking something up in a PlanetScale database, such as counting rows or reading records to answer a question
tools: [planetscale_list_organizations, planetscale_list_databases, planetscale_execute_read_query]
references: [postgres/query-patterns.md, postgres/schema-design.md]
---
1. When the person did not name the database, find its organization with `planetscale_list_organizations` and the database with `planetscale_list_databases`. Production is usually the main branch.
2. Find the table and its columns in one query with `planetscale_execute_read_query`, rather than reading the whole schema: SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name ILIKE '%word%' ORDER BY table_name, ordinal_position. Use a word from the question in place of word.
3. Run the query with `planetscale_execute_read_query`. Send one statement per call, since several statements in one call are refused. Count or aggregate instead of reading a large table whole, and add a LIMIT when listing rows, since a query running past 50 seconds is cancelled.
4. The tool reads as a role that row level security still applies to, so zero rows from a table with row level security may mean the rows are hidden by a policy rather than missing. Say so when the result is empty and a warning says that risk is there.
5. Answer with the numbers or rows, and the query that produced them.
