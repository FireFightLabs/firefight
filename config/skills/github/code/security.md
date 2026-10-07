---
name: github_security
when: Reading a GitHub repository's Dependabot, code scanning or secret scanning alerts, or dismissing or reopening a Dependabot alert
tools: [dependabot_alerts, dependabot_alert, dismiss_dependabot_alert, reopen_dependabot_alert, code_scanning_alerts, code_scanning_alert, secret_scanning_alerts, secret_scanning_alert, pr_lookup, list_pull_requests]
references: [security/dependabot-alerts.md, security/view-dependabot-alerts.md, security/code-scanning-alerts.md, security/secret-scanning-alerts.md]
---
1. List what is open with `dependabot_alerts`, narrowed by `severity`, `ecosystem` or `package`, `code_scanning_alerts` by `severity` or `ref`, and `secret_scanning_alerts`. Read one in full by its `number` with `dependabot_alert`, `code_scanning_alert` or `secret_scanning_alert`.
2. A Dependabot pull request fixes an alert. Find it with `list_pull_requests` and `author` dependabot[bot], and `pr_lookup` shows the advisories it fixes beside its checks.
3. A secret scanning alert never shows the secret. One that still works should be revoked at the service that issued it, which is a step for a person, and then resolved on GitHub. Never ask for the secret or repeat one you see.
4. Dismissing a Dependabot alert is a change, so none is done while investigating. Call `dismiss_dependabot_alert` in a chat once the person agrees, with the `reason` they give (fix_started, inaccurate, no_bandwidth, not_used or tolerable_risk) and a `comment` of at most 280 characters. `reopen_dependabot_alert` opens a dismissed one again.
5. GitHub answers not found when a kind of scanning is off for the repository. Say so rather than calling it clean.
6. Give the person the link each answer carries.
