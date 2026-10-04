---
name: devin_refused
when: Devin refused fix_code or session_status, or Firefight could not start or read a Devin session
tools: [fix_code, session_status]
---
What Devin said is in the answer, after the status code. Each one is fixed in Devin or on the connection, never by retrying.

1. 401: the API key is wrong, revoked or a legacy key (apk_). Devin's v3 API takes a service user's key or a personal access token, both starting cog_. An admin reconnects Devin with a new key.
2. 403: the key's role lacks a permission. Starting a session needs UseDevinSessions and stopping one needs ManageOrgSessions. The Member role can create and manage sessions, as Devin's docs say. An admin changes the service user's role in Devin, under Settings, Devin API.
3. 404: the organization id on the connection is wrong, or the session belongs to another organization. The id is shown at the top of Settings, Devin API in Devin.
4. 429: Devin is limiting how often it is asked. Try again in a minute.
5. Devin started but could not open the pull request: Devin reaches repositories through the git provider connected in Devin, so the repository has to be one that connection can push to.
