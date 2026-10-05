---
name: cursor_handoff
when: Writing a fix whose code change a Cursor cloud agent will write, or handing Cursor a code change in a chat
tools: [fix_code]
---
A Cursor cloud agent writes a code change in its own machine, pushes a branch and opens the pull request itself, and never merges it. Firefight hands a fix's code change to Cursor only when Cursor is the workspace's choice under Settings, Workspace, and builds the call from the fix: the step's description is the `title`, the step's repository is `repo`, and the finding, its evidence and how to tell it worked are the `brief`. The agent reads nothing of Firefight's, so what it needs has to be in the fix.

1. Cursor needs the repository's address. Name the repository as the resource map shows it, owner/name, and Firefight uses the address the map holds. A repository that is not on the map is named by its address as its code host shows it.
2. Write the step's description as the pull request's title, a short sentence of what changes.
3. Put in the finding everything the agent needs to reproduce and fix it: the exact error text, the file and line from a stack trace, the request or input that fails, the commit or deploy it began with, and the test or check that shows it is fixed. Leave out credentials and customer data, since anything that looks like a credential is redacted before it leaves Firefight.
4. The agent starts from the repository's default branch. Name another branch in `base` when the fix belongs on a release branch.
5. One step is one repository and one pull request. A second repository is a second step that waits on the first, told about it in `context`.
6. Cursor has no spending limit for one agent, so Firefight's limit is time: it cancels the run after 30 minutes. A change too large for that is a person's step, or several smaller ones.
7. In a chat, call `fix_code` only once the person agreed to the change. It runs as them, and an approval rule can hold it. The answer names the pull request and the agent's page, and gives both links to the person.
