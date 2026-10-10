---
name: credential_stuffing
when: Many failed logins, a spike of sign in attempts from many addresses, accounts being taken over, or an alert about brute force or credential stuffing
tools: [list_notices, search_map, get_resource]
---
1. Find the login endpoint and what serves it on the map with `search_map`: the service, and the edge network or firewall in front of it.
2. Confirm it is an attack, not a broken login. Read the service's logs for failed logins over the last hours against the week before, and its errors. A broken login fails for everyone, an attack fails from many addresses trying many accounts.
3. Find who: the top client addresses, networks, countries and user agents, from the edge network's security events where one is connected (its attack skill says how), else the service's request logs.
4. Find whether any attempt worked: successful logins from the same addresses, and accounts that changed their email or password just after. That is what the team has to act on first.
5. Propose the narrowest stop: a rate limit on the login path, then a challenge or block for the networks the events point at. Each is a change a person approves, and each should end on its own, such as a rule that expires after a day, with a reminder before it does.
6. Say which accounts may be taken over, so the team can force a password reset. Never name a customer outside the team's own channel.
