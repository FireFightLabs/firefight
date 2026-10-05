---
name: netlify_triage
when: Starting on anything wrong with a Netlify site, before knowing what kind of problem it is
tools: [list_sites, resource_status, recent_deploys, describe_deploy]
references: [deploy/deployment-patterns.md]
---
Work from what is live outward, and stop as soon as one of these explains what was reported.

1. Call `list_sites` for the exact name. A site is named by its Netlify name, its id or its custom domain.
2. Call `resource_status` on it. Note the live deploy (when it was published, its branch and commit, and whether auto publishing is locked to it), the repository and branch it builds from, the custom domain and aliases, and whether builds are stopped. Later steps lean on these.
3. Call `recent_deploys`. A production deploy published shortly before the trouble began is the first suspect, so load the netlify_deploys skill. A deploy in state error never went live, so the version before it is still serving.
4. When the site answers with the wrong page, an old version or errors from its functions, load the netlify_wrong_version skill.
5. When the site does not answer at its own domain while its netlify.app address works, or HTTPS fails, load the netlify_domains skill.

Netlify's API keeps no function logs, build logs or traffic numbers, so those are read in the Netlify app. Give the person the link each answer carries, and say which of these you could not read.
