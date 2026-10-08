---
name: running_runbooks
when: The person asks for something a saved runbook does, by its name or in their own words, such as release Firefight
tools: [search_runbooks, get_runbook]
---
1. Look for it with `search_runbooks`, using the person's words as the `query`. A runbook marked runnable is one Halon can run.
2. Read it with `get_runbook` by its `slug`. Say in a sentence or two what it will do, step by step, and what it watches afterwards.
3. Each of its inputs is asked of the person unless they already said it. One with a default is used as it is unless they say otherwise, and say which value you will use.
4. Call run_runbook with the runbook's name and the inputs. The person confirms the run before any step happens, so never ask them to confirm it in words as well.
5. Say how it went from its answer. When a step was refused, waits for an approval or failed, say which step and why, and that nothing after it ran. When its watch started, say how long it will watch for.
