---
name: northflank_changes
when: Finding what changed on Northflank before something broke, such as a deployment, a build or a settings change
tools: [list_deployments, recent_builds, describe_resource, query_metrics]
---
1. Call `list_deployments` for the service. Each one says when it went out, the commit or image, how many instances, and why:
   - a build or a release, which brings new code, and its commit is where to look
   - a template or release flow run, which can change code and settings together
   - a change to the service's settings, such as environment variables, plan or instances, which redeploys the same code
   The reason also names who made it when a person did.
2. Call `query_metrics` for the errors or resources that went wrong, and line the moment they turned up against those times. A deployment that went out after the trouble began did not cause it.
3. Call `recent_builds` to see builds that failed or never deployed. A failed build is not deployed, so the old version keeps running. It can explain a fix that is not live, rarely an outage.
4. Call `describe_resource` for the commit running now and the repository it comes from. To see what the suspect deployment changed in code, compare its commit with the one before it in the repository.
5. Say which change came right before the trouble, what it was and who made it, and how sure the timing makes you.
