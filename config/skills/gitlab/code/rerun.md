---
name: gitlab_rerun
when: Retrying a GitLab pipeline after a failure that is not the code, running a pipeline on a branch or tag, or canceling one, such as a deploy that should not go out
tools: [ci_status, pipelines, pipeline_jobs, job_log, retry_pipeline, run_pipeline, cancel_pipeline]
references: [ci/pipelines.md, ci/job-troubleshooting.md]
---
1. Each of these changes real CI, so none is done while investigating. Propose it, say what it does and why, and call it only in a chat once the person agrees. It runs as them, and an approval rule can hold it.
2. Retry only when what failed is not the code. Read the failure first with `ci_status`, `pipeline_jobs` and `job_log`. A job that failed and then passed on the same commit in `pipelines`, a stuck or timed out job, a runner system failure, a network error, or a service the tests reach that has since come back is a reason to retry. A failure that began with one commit and repeats on every pipeline since is the code, so propose a fix instead, since a retry only spends the time it takes.
3. Call `retry_pipeline` with `repo` and the `pipeline_id`. GitLab retries the pipeline's failed and canceled jobs and keeps the ones that passed. It has no retry of every job, so to run every job again on the newest commit of the branch, call `run_pipeline` instead.
4. `run_pipeline` runs a new pipeline on `ref`, a branch or tag, the default branch when none is named, with `variables` and `inputs` by name when the person gives them. Never put a secret in `variables`, since what Halon passes is shown and kept. A pipeline that deploys ships whatever is on that ref, so say which commit it will deploy before the person agrees.
5. `cancel_pipeline` cancels a pipeline's jobs that have not finished, such as a deploy that should not go out. Say what it stops before the person agrees.
6. When GitLab refuses, the answer says what it needs: a token with the api scope, from someone who may run pipelines in the project, and on a protected branch someone allowed to merge or push to it. Tell the person, and do not try again until it is in place.
7. Each answer links the pipeline. Give the link, then follow it with `pipeline_jobs` or `ci_status`, and say whether it passed.
