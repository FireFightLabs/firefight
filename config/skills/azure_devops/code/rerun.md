---
name: azure_devops_rerun
when: Rerunning an Azure Pipelines run's failed jobs after a failure that is not the code, running a pipeline on a branch or tag, canceling a run, such as a deployment that should not go out, or answering an approval a run waits on
tools: [ci_status, ci_runs, pipelines, pipeline_jobs, job_log, pending_approvals, retry_pipeline, run_pipeline, cancel_pipeline, approve_check]
references: [pipelines/runs.md, pipelines/approvals.md]
---
1. Each of these changes real CI, so none is done while investigating. Propose it, say what it does and why, and call it only in a chat once the person agrees. It runs as them, and an approval rule can hold it.
2. Rerun only when what failed is not the code. Read the failure first with `ci_status`, `pipeline_jobs` and `job_log`. A job that failed and then passed on the same commit in `pipelines`, an agent that went away, a network error, or a service the tests reach that has since come back is a reason to rerun. A failure that began with one commit and repeats on every run since is the code, so propose a fix instead, since a rerun only spends the time it takes.
3. Call `retry_pipeline` with the `project` and the run's `build_id`. Azure DevOps reruns the run's failed jobs on the same commit and keeps the ones that passed. To run every job again on the newest commit of a branch, call `run_pipeline` instead.
4. `run_pipeline` runs `pipeline`, as project/pipeline, on `ref`, a branch or refs/tags/ and a tag, the pipeline's default branch when none is named, with `variables` the pipeline lets a run set and a YAML pipeline's `template_parameters` when the person gives them. Never put a secret in `variables`, since what Halon passes is shown and kept. A pipeline that deploys ships whatever is on that ref, so say which commit it will deploy before the person agrees.
5. `cancel_pipeline` cancels a run that has not finished, such as a deployment that should not go out. Say what it stops before the person agrees.
6. A run waiting on an approval goes on only once an approver answers it. `pending_approvals` lists them with their ids and who may approve. `approve_check` approves or rejects one with a comment, and only when the person asks for it or a runbook step says to, never because a run is waiting. Azure DevOps takes it only from one of its approvers.
7. When Azure DevOps refuses, the answer says what it needs: a token with Build (Read & execute) from someone who may queue and stop the pipeline's runs, and for an approval Pipeline Resources (Use) from one of its approvers. Tell the person, and do not try again until it is in place.
8. Each answer links the run. Give the link, then follow it with `ci_runs` with the run's id as `run`, or `ci_status`, and say whether it passed.
