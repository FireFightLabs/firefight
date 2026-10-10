---
name: github_cost
when: Watching or explaining what the GitHub organization spends, such as Actions minutes, storage or Copilot, or which repository costs more than before
tools: [billing_usage, list_repositories]
signals: [cost]
---
1. Read this month by day with `billing_usage` and `by` day, then the months before with `by` month and `months` 3.
2. Compare whole days, and the same days of last month. Find the product and SKU that grew, such as Actions on a larger runner, and the repository behind it.
3. For Actions that grew, the repository's workflow runs show which workflow runs more often or longer.
4. GitHub reports billing usage only for an organization on its enhanced billing platform. A personal account, or a refusal for want of Organization administration read on the App, is a gap to say, never a flat bill.
