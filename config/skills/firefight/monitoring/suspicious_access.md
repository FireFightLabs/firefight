---
name: suspicious_access
when: A login, key or token used from somewhere unusual, access nobody recognises, a new admin or permission nobody granted, or an alert about suspicious access to an account or system
tools: [list_notices, search_activity, list_principals, search_map, get_resource]
---
1. Name what was accessed and by whom from the alert or the person's words: the account, user, key or role, the system, and the time.
2. Read the system's own audit log around that time through its provider's skill, such as CloudTrail for AWS or a code host's audit log: what that identity did, from which address, and what it did before.
3. For Firefight itself, `search_activity` lists what each person, key and agent did through the gateway, and `list_principals` who holds what.
4. Compare with what is normal for that identity: the addresses and times it usually works from, and whether a change it made was planned, such as one on a pull request or in an incident.
5. When you cannot tell it apart from normal work, say so and name who could confirm it, such as the owner of the key.
6. Propose the containment in order: revoke the session or key, remove access that was added, then rotate anything it could read. Each is a change a person approves.
7. Read `list_notices` to see whether it was raised before.
