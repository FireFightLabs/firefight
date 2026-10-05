---
name: modal_deploys
when: Finding what changed on Modal before something broke, or putting an app back on an earlier version
tools: [recent_deploys, resource_status, app_logs, rollback, restart]
---
1. Call `recent_deploys`. Each version says when it went out, by whom, from which commit and branch (and whether the commit had uncommitted changes), and whether it was a rollback or a rollover. Every deploy of an app increases its version, and a deploy that changed nothing does not.
2. Line the versions up against when the trouble began. A version that went out after the trouble began did not cause it. Read `app_logs` with `source` stderr just after the suspect version went out, to see whether the errors start with it.
3. A build that fails never goes live, and the old version keeps serving. Modal moves traffic to a new version as its containers become ready, and old containers finish what they hold first, so a bad version can serve alongside the old one for a while.
4. To go back, `rollback` with `to` set to the version that worked, such as v12. Modal deploys it again as a new version, with the functions and settings of the one asked for, whatever the code now says. Rollbacks are on Modal's Team and Enterprise plans. The next deploy from the code puts the bad version back unless the code is fixed first, so say so.
5. When the code did not change but something it loads at start did, such as a secret, `restart` rolls the app over to fresh containers on the same version.
6. Say which version came right before the trouble, who deployed it and from which commit, and how sure the timing makes you.
