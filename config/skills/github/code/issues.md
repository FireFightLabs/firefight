---
name: github_issues
when: Finding, reading, opening, commenting on, labelling, assigning, closing or reopening a GitHub issue
tools: [list_issues, issue_lookup, create_issue, comment_on_issue, update_issue, label_issue, assign_issue, close_issue, reopen_issue]
references: [issues/closing-an-issue.md]
---
1. Find issues with `list_issues`, by `state`, `labels`, `assignee`, `author`, `since` or `text`, and read one with `issue_lookup` by its `number`. Pull requests are left out of the list, and the pull request tools read and change them.
2. Every change here is real, so none is done while investigating. Say what it does and call it in a chat once the person agrees. It runs as them, and an approval rule can hold it.
3. Open an issue with `create_issue`, a `title` and a `body` that says what happened, the evidence and the links. `labels` must be ones the repository has, which a refusal lists. An issue opened while a chat is about an incident is kept on that incident as an action or a follow-up, and closing it completes that item.
4. Comment with `comment_on_issue`, change the title or description with `update_issue`, labels with `label_issue` and who it is assigned to with `assign_issue`, using `add` and `remove`. GitHub does not assign someone who cannot be assigned in the repository, and the answer names them.
5. Close with `close_issue` and a `reason`: completed when the work is done, not_planned when it will not be done, duplicate when another issue covers it. A `comment` says why. `reopen_issue` opens it again.
6. Give the person the link each answer carries.
