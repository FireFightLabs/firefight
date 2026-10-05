---
name: bitbucket_failing_pipeline
when: Finding why a Bitbucket pipeline fails, such as a broken build, failing tests or a deployment step that stopped
tools: [ci_status, pipelines, pipeline_steps, job_log, search_logs]
---
1. Call `ci_status` with the repository as `repo`, and a `branch` when the failure is not on the main branch. It names the latest pipeline, its failed steps, and when the branch last passed.
2. A failure that began with one commit after a run of passing pipelines points at that commit. One that comes and goes on the same commit points at something outside the code, such as a flaky test, a service the tests reach, or the build's runner.
3. Call `job_log` with the repository for the newest failed step's log, read from its end, where a step says why it stopped. Pass `text` or `regex` to find an error, `exclude` to drop noise, and `pipeline` with `step` to read one step that `pipeline_steps` listed. `search_logs` asks the same of a repository on the map.
4. When a step has no log, Bitbucket no longer keeps it, so say so and read an earlier failure with `pipelines` set to `status` FAILED.
5. Never run a pipeline again while investigating. When what failed is not the code, such as a flaky test, a timeout or a service that has since come back, propose running it again and say why. When it is the code, propose a fix instead. Load bitbucket_rerun once the person wants it, since running one again asks them first.
6. Say which step fails, the line in its log that says why, the commit it ran on, and when the branch last passed, with the link the answer gives.
