---
name: factory_session
when: A code change handed to Factory failed, stopped, is still running, or someone asks how it went
tools: [session_status, fix_code]
---
1. Find the session id in the step's result, or in what `fix_code` answered, and call `session_status` with it as `session`.
2. Read what it says and act on it:
   - Working: the Droid is still writing it. Factory gives no page for a session, so say it is running and that it shows in the Factory app.
   - Finished with a pull request: hand the person its link. Review and merging are theirs.
   - Finished without one: read what the Droid said. It may have committed without pushing, found no change to make, or could not reproduce the problem. Say which, and what the fix needs instead.
   - Stopped by Firefight's 30 minute limit: the Droid was interrupted. Say what it had done, and that the session can be picked up in the Factory app.
3. What it used is in Factory credits, as Factory reports it. Give the person any pull request's link with what you found.
