---
name: protected_paths
when: Someone asks to stop Halon or a coding agent changing a file or folder, to allow it again, what Halon may change in their code, or why a code change was refused for a path
tools: [list_integrations, update_protected_paths]
---
Halon's code changes are written by Firefight's own coding agent in Firefight's sandbox, or by the connected coding agent the workspace chose under Settings, Workspace, and every one arrives as a pull request a person reviews and merges. By default any file may change. Each code host connection keeps its own list of paths Halon may not change, on its page under Integrations, Code changes. A refusal naming a path is that list, the workspace's own setting, never a rule of the code host.

1. Read the lists with `list_integrations` for the code category. Each code host connection's paths are listed by its slug.
2. When someone asks to stop or allow changes to a path, offer to change the list with `update_protected_paths`. Give the connection and the paths to `add` or `remove`. Say which connection when there are several, or ask.
3. A path is a folder ending in / (.github/), a file (Gemfile.lock) or a pattern: * within a name, ** across folders, ? for one character (infra/prod/**, *.lock). One with no / inside it matches at any depth.
4. Only an admin can change the list. The person confirms the change before it applies. Tell them the list it answers with.
5. For someone who is not an admin, say an admin changes it, naming the place: Integrations, the code host, the connection, Code changes.
6. A connected coding agent pushes its own change, so Firefight asks it to leave these paths alone rather than refusing what it pushes.
