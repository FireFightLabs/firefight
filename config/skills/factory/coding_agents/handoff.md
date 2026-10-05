---
name: factory_handoff
when: Writing a fix whose code change a Factory Droid will write, or handing Factory a code change in a chat
tools: [fix_code]
---
A Factory Droid writes a code change on the workspace's Droid Computer, in the copy of the repository cloned there, then commits, pushes and opens the pull request itself, and never merges it. Firefight hands a fix's code change to Factory only when Factory is the workspace's choice under Settings, Workspace, and builds the call from the fix: the step's description is the `title`, the step's repository is `repo`, and the finding, its evidence and how to tell it worked are the `brief`. The Droid reads nothing of Firefight's, so what it needs has to be in the fix.

1. The repository has to be cloned on the Droid Computer the connection names. Firefight finds its folder by the repository's name, so name it as owner/name, as the resource map shows it.
2. Write the step's description as the pull request's title, a short sentence of what changes.
3. Put in the finding everything the Droid needs to reproduce and fix it: the exact error text, the file and line from a stack trace, the request or input that fails, the commit or deploy it began with, and the test or check that shows it is fixed. Leave out credentials and customer data, since anything that looks like a credential is redacted before it leaves Firefight.
4. The Droid starts from the branch the copy is on. Name the branch in `base` when the fix belongs on a particular one.
5. One step is one repository and one pull request. A second repository is a second step that waits on the first, told about it in `context`.
6. Factory has no spending limit for one session, so Firefight's limit is time: it interrupts the Droid after 30 minutes. A change too large for that is a person's step, or several smaller ones.
7. Factory returns no pull request of its own, so the Droid is asked to end with its address, and Firefight reads it from there. In a chat, call `fix_code` only once the person agreed to the change. It runs as them, and an approval rule can hold it.
