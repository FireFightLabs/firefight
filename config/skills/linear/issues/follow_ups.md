---
name: linear_follow_ups
when: Opening a Linear issue for work an incident needs, during it or after it, or adding what the incident found to an existing issue
tools: [list_teams, list_issues, get_issue, save_issue, save_comment, list_issue_labels, list_users]
---
1. Before creating anything, search with `list_issues` for an open issue that already covers the work. If one does, add what the incident found to it with `save_comment` instead of opening a second.
2. Find the team with `list_teams` when the person did not name one, and its labels with `list_issue_labels` when the issue should carry one, such as Bug.
3. Write the issue: `title` names the component and what to do, and `description` says what happened in the incident, its identifier (such as INC-42) and title, the evidence, and what done looks like. To assign it, find the person with `list_users`.
4. Tell the person the team, title, labels and assignee before calling `save_issue` without an `id`, which opens a new issue in `team`.
5. Give the person the new issue's identifier and link. In a chat about an incident, Firefight keeps the new issue on it with its link by itself and says so in the answer, so do not add it again. Say how with `keep_on_incident_as` on `save_issue`: `action` for work to do while the incident is live, such as a fix or a mitigation, and `followup` for work after it, such as hardening or a cleanup. Left out, it is an action while the incident is live and a follow-up once it is over. Otherwise, when the issue is for an incident, record it there with `create_action_item`, naming the identifier and link, so the incident and the issue point at each other.
6. When the issue is completed or canceled, Firefight marks its item done on the incident by itself once it can read the issue's status, and says so in the answer. To check one now, read it with `get_issue`.
