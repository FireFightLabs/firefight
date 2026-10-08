---
name: github_fixing
when: Writing a code change with Firefight's own coding agent, in a chat or as a fix's step, especially one that touches another system's interface such as a webhook, an API, a config format or a CI trigger
tools: [fix_code]
---
1. Before designing the change, read what it depends on. When it touches another system's interface, such as a webhook, an API, a config format or a CI trigger, read that system's documented contract, from its provider's skill and guides, its own documentation tool, or its documentation with search_web, and read how it is set up now with the tools that reach it. Never design it from what such systems usually do.
2. Write the `brief` for someone who has only the repository: what to change and why, the exact error or behaviour, the files and lines, the contract and the setup you read with what each said, and a list of anything you could not verify. The person's own words and the results you read travel with it, so quote rather than summarise what matters.
3. Name the repository as owner/name in `repo`, give a short `title`, and a `summary` for the pull request's readers. Name a `base` when the change belongs on another branch, `pull_request` or `branch` to add it to an open one, and say in `context` what other changes in the same fix did.
4. The agent reads the connected systems as the person who asked and may ask them a question while it works, which shows under the step with a box to answer it. Nobody answering within five minutes stops the change.
5. Its change is checked in the sandbox and reviewed against what the person asked before it opens. A change the review finds wrong goes back to the agent once, and one still wrong is not opened. The answer lists what the review found and what nobody could verify, and those lead the pull request's description. Tell the person both.
6. In a chat, call `fix_code` only once the person agreed to the change. It runs as them, and an approval rule can hold it. Give them the link the answer carries.
