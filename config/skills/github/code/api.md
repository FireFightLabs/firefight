---
name: github_api
when: A question about GitHub that the other GitHub tools do not answer, such as a repository's environments and their protection rules, deployment statuses, rulesets, collaborators, teams, packages, Pages or an organization's settings, or anything else GitHub's REST API reads, and finding out whether GitHub's API offers a read at all
tools: [api_read, list_repositories]
references: [api/index.md]
---
`api_read` sends a GET to any path of GitHub's REST API and answers what GitHub said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through GitHub's other tools, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_repositories` for what this connection was given, and the pull request, Actions, release, branch and security tools for those. Reach for `api_read` for the rest.
2. Find the path in the API reference before the first call, not by guessing: read api/index.md (use_skill with this skill and that reference), which lists every read GitHub's REST API offers by area, then the area's page it names for the parameters and the fields each read answers. When the reference lists no read for the question, GitHub's API does not offer it. Say so, and give the steps on GitHub instead.
3. Write owner and repository into the path as owner/name, as `list_repositories` shows them, and put every parameter in `query`, never in the path.
4. A list answers one page. Pass per_page, at most 100, and read on with page 2, 3 and so on while a page comes back full.
5. GitHub answers only for the repositories this connection's GitHub App was given, and a refusal names the permission the App needs. Say which, and that an owner of the GitHub account grants it in the App's settings.
6. Secrets come back as their names, since GitHub never gives their values, and webhooks as their names too, since an address can carry a token. Archives, run and job logs and artifacts are downloads and are not read here. A job's log has its own tool in the failing build skill.
