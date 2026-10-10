---
name: leaked_secret
when: A key, token, password or other secret was leaked, such as a secret scanning alert, a key posted in a public place, or someone asking what a leaked key could do
tools: [list_notices, search_activity, search_map, get_resource]
---
1. Never ask for the secret and never repeat one you see. Name it by its type, where it was found and the alert's number.
2. Read the alert with the code host's own security skill, such as github_security: what type of secret, which commit and file, whether it is still valid and whether it is public.
3. Find what the secret reaches. Its type names the provider, such as an AWS access key or a Stripe key. `search_map` and `get_resource` show what that provider runs here.
4. Find what was done with it. Read the provider's own audit or activity log for the key, such as CloudTrail for an AWS key, through that provider's skill, from the commit's time to now. `search_activity` shows what Firefight's own gateway did, which covers only Firefight's connections.
5. Propose the fix in this order: revoke or rotate the secret at the provider that issued it, put the new one where the service reads it, then check the old one no longer works, through a read that uses it failing. Removing it from the repository does not end the leak, since it stays in history.
6. Revoking a key is a change a person approves. Say what will break while the key is replaced, such as a service that reads it.
7. Read `list_notices` with `signal` leaked_secret to see whether this alert was raised before.
