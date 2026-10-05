---
name: sentry_bad_release
when: Finding whether a release or deploy caused new errors in a service Sentry watches, and which change in it
tools: [recent_deploys, search_issues, execute_sentry_tool, get_sentry_resource]
---
1. Call `recent_deploys` for the service. Each release shows when it was created and last deployed, to which environment, its last commit, and how many new issues it brought. Note the release deployed just before the trouble began, and the one before it.
2. Call `search_issues` for the project in projectSlugOrId with the query firstRelease:<version>, to see the issues that first appeared in that release. New issues there, and few or none in the release before it, point at the release.
3. Call `execute_sentry_tool` with name get_release_details and, in its arguments, the releaseVersion, the project in projectSlugOrId and includeHealth true. It gives the release's deploys, its commits and its page in Sentry, and the health data Sentry keeps for the release in that project. Compare them with the release before.
4. Read the commits for the file an issue's stack trace names, from `get_sentry_resource` with resourceType issue and the issue's short id in resourceId. A commit that touched that file is the likeliest cause.
5. Say what you found, with the release's page and the issue's. Sentry cannot roll a release back. Going back to the earlier release is done through the platform that runs the service, with rollback, as a fix a person approves.
