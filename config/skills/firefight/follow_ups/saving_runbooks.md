---
name: saving_runbooks
when: The person asks to remember a multi-step task as a runbook, such as remember this as Release Firefight, or agrees when offered
tools: [search_runbooks, upsert_runbook]
---
1. Check with `search_runbooks` that no runbook already has that name. When one does, ask whether to change it or save a new one.
2. Write each step the task took as one of the runbook's `steps`: a title a person reads, the tool you called, as you called it, and the arguments you called it with. Leave out steps that only looked something up to decide what to do.
3. A value the person chose this time and could choose differently next time, such as a version bump, becomes one of its `inputs`: a key, the question to ask and the default they chose. In the arguments it is written as {{key}}.
4. When the task ended by following something until it finished, such as a release run and the deploy after it, save what you watched as its `watch`, with the same inputs in place. Keep the order the work happens in: each item that only means something once another is done names it in waits_for, such as a deploy waiting for the run that ships it and each health check waiting for its own deploy, and items that go side by side wait for the same item rather than each other. An item that follows a run the release names, such as a workflow run named after the tag, names it in run with the input that makes it.
5. Add the words the person used for it as `aliases`, such as release firefight.
6. Call `upsert_runbook` with the `name`, the steps, inputs, aliases and watch. Say it is saved and that they can ask for it by name.
