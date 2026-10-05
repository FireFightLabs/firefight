---
name: cursor_refused
when: Cursor refused fix_code or session_status, or Firefight could not start or read a Cursor agent
tools: [fix_code, session_status]
---
What Cursor said is in the answer, after the status code. Each one is fixed in Cursor or on the connection, never by retrying.

1. 401: the API key is wrong or was deleted. An admin creates a new one on the API Keys page of Cursor's dashboard, or uses a service account's key, and reconnects Cursor.
2. Source control not connected, or no access to the repository: Cursor reaches repositories through the GitHub, GitLab, Bitbucket or Azure DevOps connection set up in Cursor, which has to cover this repository. An admin connects it in Cursor's cloud agent settings.
3. A plan or a role that does not allow cloud agents, or a usage limit reached: that is the Cursor account's, for its admin.
4. 429: Cursor is limiting how often it is asked. Try again in a minute.
5. The repository is not on the map: Firefight does not guess an address. Name the repository by its address in `repo`.
