---
name: planetscale_query_data
when: Looking something up in a PlanetScale database, such as counting rows or reading records to answer a question
tools: [planetscale_list_organizations, planetscale_list_databases, planetscale_get_branch_schema, planetscale_execute_read_query]
references: [postgres/query-patterns.md, postgres/schema-design.md]
---
1. When the person did not name the database, find its organization with `planetscale_list_organizations` and the database with `planetscale_list_databases`. Production is usually the main branch.
2. Read the tables and columns the question needs from the application's repository before writing any query: db/schema.rb, db/structure.sql, prisma/schema.prisma, its models or its migrations, found with the code host's code search or file list. The repository says what each column means and how the tables join, which the database alone does not.
3. When no repository you can read holds them, read those tables with `planetscale_get_branch_schema` instead. Never guess a table or column name.
4. Run the query with `planetscale_execute_read_query`. Send one statement per call, since several statements in one call are refused. Count or aggregate instead of reading a large table whole, and add a LIMIT when listing rows, since a query running past 50 seconds is cancelled.
5. Firefight sends the query to the primary, which is current. Set use_replica only as a fallback, when the primary was slow or refused, and then say the rows came from a replica, which may lag behind it.
6. The tool reads as a role that row level security still applies to, so zero rows from a table with row level security may mean the rows are hidden by a policy rather than missing. Say so when the result is empty and a warning says that risk is there.
7. Answer with the numbers or rows, and the query that produced them. When PlanetScale was slow to answer, say so and what you did instead.
