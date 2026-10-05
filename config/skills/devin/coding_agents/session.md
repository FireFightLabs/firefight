---
name: devin_session
when: A code change handed to Devin failed, stopped, is still running, or someone asks how it went
tools: [session_status, fix_code]
---
1. Find the session id in the step's result, or in what `fix_code` answered, and call `session_status` with it as `session`.
2. Read what it says and act on it:
   - Working: Devin is still writing it. Give the person the session's link to follow it.
   - Waiting for a person: Devin asked a question or waits for an action to be approved in its session. Someone answers it there, in Devin, since Firefight cannot.
   - Finished with a pull request: hand the person its link. Review and merging are theirs.
   - Finished without one: read what Devin said. It usually could not reproduce the problem, found no change to make, or could not reach the repository. Say which, and what the fix needs instead.
   - Stopped at its usage limit: Devin used the ACUs the connection allows for one change. A larger limit is set on the connection, or the change is split.
   - Stopped because the account is out of credits, quota or its contract: that is the Devin account's billing, for an admin of it.
   - Stopped at Firefight's 30 minute limit: say what Devin had done by then, and that the session can be picked up in Devin.
3. Give the person the session's link and any pull request's link with what you found.
