---
name: cursor_session
when: A code change handed to Cursor failed, stopped, is still running, or someone asks how it went
tools: [session_status, fix_code]
---
1. Find the agent's id in the step's result, or in what `fix_code` answered (it starts bc-), and call `session_status` with it as `session`. Firefight reads the agent's latest run.
2. Read what it says and act on it:
   - Working: the run is starting or writing the change. Give the person the agent's page to follow it.
   - Finished with a pull request: hand the person its link. Review and merging are theirs.
   - Finished without one: read what the agent said. It may have pushed a branch without opening a pull request, found no change to make, or could not reproduce the problem. Say which, and what the fix needs instead.
   - Stopped because the run ended with an error or expired: read what the agent said, and give the agent's page, where a person can send it a follow-up in Cursor.
   - Stopped by Firefight's 30 minute limit: the run was cancelled. Say what it had done, and that a follow-up can be sent to the same agent in Cursor.
3. What it used is in tokens, as Cursor reports it. Give the person the agent's page and any pull request's link with what you found.
