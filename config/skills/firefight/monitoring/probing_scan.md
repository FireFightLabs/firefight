---
name: probing_scan
when: A daily look through the logs for someone probing the team's services, such as scanners, path probing, bursts of not found answers from one address, requests for admin paths or known exploit strings
tools: [search_map, get_resource, search_logs, new_log_patterns, list_notices]
---
1. Find what faces the internet on the map with `search_map`: the public services, sites and APIs, and what serves them.
2. For each, read the last 24 hours of request logs with `search_logs`, and the log lines that are new against the usual with `new_log_patterns`.
3. Look for the signs of probing, each with the addresses behind it:
   - scanners by their user agent, such as sqlmap, nikto, nuclei, zgrab or masscan
   - paths that do not exist being walked, such as many different not found answers from one address in a few minutes
   - bursts of 404 or 403 answers from one address or network
   - admin and config paths asked for, such as /wp-admin, /.env, /.git/config, /phpmyadmin, /actuator or /server-status
   - known exploit strings in paths or parameters, such as ../, ${jndi:, <script, union select or /etc/passwd
4. Tell probing from real use. A crawler the team runs, an uptime monitor or one person mistyping a path is not probing. Many addresses trying the same exploit string, or one address walking hundreds of paths, is.
5. Read `list_notices` to see whether the same probing was raised before, so the same addresses are not reported as new.
6. Report problem when probing reached a service or keeps coming from the same addresses, with high severity when a request looks like it worked (a 200 answer to an exploit string or an admin path), medium when it was all refused, and low for scattered scanner noise worth knowing. Report ok when the logs show none, and unsure when no logs could be read, naming which.
7. In what you found, name each service, the addresses or networks, the paths or strings, how many requests and what the service answered.
