---
name: saving_runbooks
when: The person asks to remember a multi-step task as a runbook, such as remember this as Release Firefight, or agrees when offered
tools: [search_runbooks, upsert_runbook]
---
1. Check with `search_runbooks` that no runbook already has that name. When one does, ask whether to change it or save a new one.
2. Write each step the task took as one of the runbook's `steps`: a title a person reads, the tool you called, as you called it, and the arguments you called it with. Leave out steps that only looked something up to decide what to do.
3. A value the person chose this time and could choose differently next time, such as a version bump, becomes one of its `inputs`: a key, the question to ask and the default they chose. In the arguments it is written as {{key}}.
4. When the task ended by following something until it finished, such as a release run and the deploy after it, save what you watched as its `watch`, with the same inputs in place.
5. Add the words the person used for it as `aliases`, such as release firefight.
6. Call `upsert_runbook` with the `name`, the steps, inputs, aliases and watch. Say it is saved and that they can ask for it by name.
