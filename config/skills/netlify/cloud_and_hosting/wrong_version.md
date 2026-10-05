---
name: netlify_wrong_version
when: A Netlify site serves errors, an old version, or a different version than the one people expect
tools: [resource_status, recent_deploys, describe_deploy]
references: [deploy/deployment-patterns.md, caching/SKILL.md, functions/SKILL.md]
---
1. Call `resource_status` for the live deploy, its branch and commit, and whether auto publishing is locked. A locked site keeps serving the deploy it was locked to, however many deploys build after it, which explains a change that is built but not live.
2. Call `recent_deploys`. A newer production deploy that is ready but not live means auto publishing is locked or someone published an older deploy by hand. A newer one in state error means the build failed, so the version before it still serves.
3. A version that is live but wrong for one branch or preview comes from deploy contexts. Production serves only the production branch, and branch deploys and deploy previews have addresses of their own. Check the context of the deploy the person is looking at with `describe_deploy`.
4. Errors from a site's own server code come from its functions. `describe_deploy` names the scheduled functions the deploy carries, but Netlify's API keeps no function logs, so point the person at the site's function logs in the Netlify app for the errors themselves.
5. Builds stopped in `resource_status` mean pushes no longer deploy, which explains a fix that never reached the site.
6. Say which deploy is live, how it differs from the one expected, and why, with the link to it.
