---
name: digitalocean_databases
when: A DigitalOcean managed database is down, slow, full, or refusing connections
tools: [list_resources, resource_status, query_metrics]
references: [postgres/troubleshooting.md, databases/mysql.md, shared/error-patterns.md]
---
1. Call `resource_status`. Read its engine and version, its status (online when it serves), its nodes and size, and its maintenance window. A status other than online (creating, resizing, migrating or forking), or trouble that began inside the maintenance window, often explains what was reported.
2. For a MySQL database, call `query_metrics` with `metrics` set to cpu, memory and disk. Disk near full stops writes, and cpu pinned at 100% makes every query slow. DigitalOcean's API keeps these metrics for MySQL only, so for PostgreSQL, Valkey, MongoDB and the rest say that and work from the status and the apps that use it.
3. Errors in an app about too many connections, refused connections or SSL usually come from how the app connects, not from the database. Read the app's logs with the digitalocean_triage skill.
4. A database's version that has reached its end of life shows in the status, and is worth saying when it is close.
5. Firefight does not change a managed database. Resizing, adding nodes, failing over and restoring are steps for a person in the control panel.
