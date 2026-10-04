---
name: circleci_flaky_tests
when: Telling whether a CircleCI test that fails only sometimes is flaky or really broken
tools: [list_runs, get_run, list_workflows, list_jobs, list_job_tests]
---
1. Call `list_runs` for the project and branch, and look for runs of the same commit that failed and then passed, or a branch that alternates between failing and passing without new commits. `get_run` gives the commit each run built.
2. For two or three of those runs, find the test job with `list_workflows` and `list_jobs`, then call `list_job_tests` on each. The same test failing in one and passing in the other on the same commit is flaky. A test that fails every time since one commit is broken by that commit.
3. Compare the failure messages. A timeout, a port or connection already in use, an order the test assumed, or a time of day in the message usually means the test depends on something besides the code.
4. Say which test, how often it failed in the runs you read, on which commits, and whether it looks flaky or broken. A flaky test is a reason to fix the test, not to roll back a change.
