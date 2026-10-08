---
name: devin_handoff
when: Writing a fix whose code change Devin will write, or handing Devin a code change in a chat
tools: [fix_code]
references: [handoff/SKILL.md]
---
Devin writes a code change in its own machine, opens the pull request itself and never merges it. Firefight hands a fix's code change to Devin only when Devin is the workspace's choice under Settings, Workspace, and builds the call from the fix: the step's description is the `title`, the step's repository is `repo`, and the finding, its evidence and how to tell it worked are the `brief`. Devin reads nothing of Firefight's, so what it needs has to be in the fix.

1. Write the step's description as the pull request's title, a short sentence of what changes, and name the repository as owner/name, as the resource map shows it.
2. Put in the finding everything Devin needs to reproduce and fix it: the exact error text, the file and line from a stack trace, the request or input that fails, the commit or deploy it began with, and the test or check that shows it is fixed. Leave out credentials and customer data, since anything that looks like a credential is redacted before it leaves Firefight.
3. Devin starts from the repository's default branch. Name another branch in `base` when the fix belongs on a release branch.
4. One step is one repository and one pull request. A fix that needs changes in two repositories is two steps, the second waiting on the first, and the second is told about the first in `context`.
5. Devin stops at the ACU limit set on the connection, and Firefight stops the session after 30 minutes. A change too large for that is a person's step, or several smaller ones.
6. In a chat, call `fix_code` only once the person agreed to the change. It runs as them, and an approval rule can hold it. The answer names the pull request and the session, and gives both links to the person.
7. Firefight cannot refuse what Devin pushes, so the brief asks it to leave alone the paths the code host connections list under Code changes as ones Halon may not change, and to start the pull request's description with a warning when the change touches a CI workflow. The protected_paths skill reads and changes that list.
8. When the change touches another system's interface, such as a webhook, an API, a config format or a CI trigger, read that system's documented contract and how it is set up now before writing the fix, and put both in the finding with what each said. List anything you could not verify, since Devin cannot check it from the repository alone.
