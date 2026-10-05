---
name: factory_refused
when: Factory refused fix_code or session_status, or Firefight could not start or read a Factory session
tools: [fix_code, session_status]
---
What Factory said is in the answer, after the status code. Each one is fixed in Factory or on the connection, never by retrying.

1. 401: the API key is wrong or revoked. An admin creates a new one under Settings, API Keys in Factory and reconnects Factory.
2. 403: Factory switches its sessions API on only for some organizations, so this can mean it is not on for this one yet, which only Factory can change. It can also mean the key's account cannot use the Droid Computer.
3. The Droid Computer has no copy of the repository, or several: someone clones it on the computer once, in one folder named after the repository. Then hand the change over again.
4. The Droid Computer is still being set up or failed: it is shown under Settings, Droid Computers in Factory, where it is fixed.
5. The Droid finished without a pull request because it could not push: a managed Droid Computer pushes through the GitHub integration set up in Factory, and a computer of your own pushes with the git credentials already on it.
