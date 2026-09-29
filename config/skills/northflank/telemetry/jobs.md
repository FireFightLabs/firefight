---
name: northflank_jobs
when: Finding why a cron or manual job on Northflank failed, did not run or ran too long
tools: [list_jobs, job_runs]
---
1. Call `list_jobs` for the exact name, whether it runs on a schedule or by hand, and whether it is suspended. A suspended cron job does not run at all.
2. Call `job_runs` for it. Look at when runs started, how they ended, and how many attempts failed. Gaps between scheduled runs mean runs did not start.
3. A run that failed after several attempts used its retries. A run that kept going until it was stopped hit its time limit. Both limits are set on the job and can be raised in Northflank when the work legitimately needs more.
4. Say which runs failed, since when, and whether they fail every time or only sometimes.

The token needs permission to read jobs. When Northflank refuses, say that the token's role needs Project, Jobs, General, Read.
