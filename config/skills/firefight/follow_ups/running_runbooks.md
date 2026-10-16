---
name: running_runbooks
when: The person asks for something a saved runbook does, by its name or in their own words, such as release Firefight
tools: [search_runbooks, get_runbook]
---
1. Look for it with `search_runbooks`, using the person's words as the `query`. A runbook marked runnable links a workflow that can start now.
2. Read it with `get_runbook` by its `slug`. When it links no workflow, it is followed by hand, so walk the person through its steps and stop here. Otherwise say in a sentence or two what its workflow will do, step by step, and what it watches afterward, in the order its steps give.
3. Each of the workflow's inputs is asked of the person unless they already said it. One with a default is used as it is unless they say otherwise, and say which value you will use.
4. Call run_runbook with the runbook's name and the inputs. The person confirms the run before it starts, so never ask them to confirm it in words as well. It runs as the workflow's own identity, with only what an admin granted it.
5. Say it started and link its run, where each step shows as it goes. When it could not start, say why in its own words, such as a workflow nobody published yet, and link the workflow's page.
