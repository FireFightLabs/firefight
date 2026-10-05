---
name: github_rerun
when: Rerunning a GitHub Actions run after a failure that is not the code, starting a workflow by hand, or canceling a run, such as a deploy that should not go out
tools: [ci_status, workflow_runs, workflow_jobs, job_log, rerun_workflow, run_workflow, cancel_workflow]
references: [actions/re-run-workflows-and-jobs.md, actions/manually-run-a-workflow.md, actions/cancel-a-workflow-run.md, actions/workflow-cancellation.md]
---
1. Each of these changes real CI, so none is done while investigating. Propose it, say what it does and why, and call it only in a chat once the person agrees. It runs as them, and an approval rule can hold it.
2. Rerun only when what failed is not the code. Read the failure first with `ci_status`, `workflow_jobs` and `job_log`. A job that failed and then passed on the same commit in `workflow_runs`, a timeout, a network error, a runner that went away, or a service the tests reach that has since come back is a reason to rerun. A failure that began with one commit and repeats on every run since is the code, so propose a fix instead, since a rerun only spends the time it takes.
3. Call `rerun_workflow` with `repo`, the run's `run_id` and `failed_only` set, so only the failed jobs and the jobs that depend on them run again and the jobs that passed are kept. Leave `failed_only` off to run every job again, such as when a job that passed used something that has since changed. Only a run that finished can run again.
4. `run_workflow` starts a workflow by hand, such as a smoke test or a deploy, with `workflow` as its file name, `ref` for the branch or tag, and `inputs` by name. Only a workflow whose file on the default branch has a workflow_dispatch trigger can be started, and Firefight checks the inputs against the ones it declares. Starting a deploy ships whatever is on that ref, so say which commit it will deploy before the person agrees.
5. `cancel_workflow` stops a queued or running run, such as a deploy that should not go out. Say what it stops before the person agrees. A job or step whose if condition still holds, such as always(), keeps running after a cancel.
6. When GitHub refuses for a missing permission, the answer names the Actions read and write permission. Tell the person an owner of the GitHub account grants it, and do not try again until they have.
7. Each answer links the run. Give the link, then follow the run with `workflow_jobs` or `ci_status`, and say whether it passed.
