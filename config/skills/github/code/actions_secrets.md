---
name: github_actions_secrets
when: Listing or setting a repository's or an environment's GitHub Actions secrets, such as a deploy webhook address or a token a workflow reads
tools: [list_actions_secrets, set_actions_secret]
references: [actions/secrets.md, actions/use-secrets.md]
---
1. Read what is there with `list_actions_secrets`, giving `environment` for an environment's secrets. GitHub never gives a value back, only each secret's name and when it was last set.
2. To set one, call `set_actions_secret` with `repo` and `name` once the person agreed. It never takes the value. Never ask the person for it and never put one in the chat. A value pasted into the chat is not used, so say so and point them to the field.
3. When another tool answered with a secret reference, such as the address of a Northflank workflow's webhook trigger, pass that reference as `value_from`. Firefight reads the value from that provider and sets it, so it never passes through you or the chat.
4. Otherwise the person types the value into the secure field under the step, which stays open for an hour, and nothing is set until they do. Tell them so. Once they say it is done, confirm with `list_actions_secrets`, which shows when it was set.
5. A refusal names what is missing in one line: Firefight's GitHub App needs Secrets read and write for a repository's secrets, and Environments read and write as well for an environment's. An admin adds it in GitHub under the app's permissions, and the installation's owner accepts it.
