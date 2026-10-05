---
name: bitbucket_rerun
when: Running a Bitbucket pipeline again after a failure that is not the code, running a pipeline on a branch or tag, or stopping one, such as a deploy that should not go out
tools: [ci_status, pipelines, pipeline_steps, job_log, rerun_pipeline, run_pipeline, cancel_pipeline]
---
1. Each of these changes real CI, so none is done while investigating. Propose it, say what it does and why, and call it only in a chat once the person agrees. It runs as them, and an approval rule can hold it.
2. Run a pipeline again only when what failed is not the code. Read the failure first with `ci_status`, `pipeline_steps` and `job_log`. A step that failed and then passed on the same commit in `pipelines`, a timeout, a network error, or a service the tests reach that has since come back is a reason to run it again. A failure that began with one commit and repeats on every pipeline since is the code, so propose a fix instead, since another run only spends the time it takes.
3. Call `rerun_pipeline` with `repo` and the `pipeline` uuid. Bitbucket's API has no rerun of only the failed steps, so this starts a new pipeline on the same commit, branch or tag and pipeline definition, and every step runs from the start. A pipeline that was given secured variables cannot be run again this way, since Bitbucket never hands them back, so the person runs it again in Bitbucket.
4. `run_pipeline` runs a pipeline on the newest commit of `ref`, a branch unless `ref_type` says tag, the main branch when none is named. Pass `custom` with a custom pipeline's name to run that one, and `variables` by name when the person gives them. Never put a secret in `variables`, since what Halon passes is shown and kept. A pipeline that deploys ships whatever is on that ref, so say which commit it will deploy before the person agrees.
5. `cancel_pipeline` stops a pipeline and every step that has not finished, such as a deploy that should not go out. Say what it stops before the person agrees.
6. When Bitbucket refuses, the answer says the token needs the write:pipeline:bitbucket scope. Tell the person, and do not try again until it has it.
7. Each answer links the commit the pipeline builds, since Bitbucket gives a pipeline no page address of its own. Give the link, then follow the pipeline with `pipeline_steps` or `ci_status`, and say whether it passed.
