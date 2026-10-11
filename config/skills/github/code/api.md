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

Key reads, the ones an investigation reaches for most, with what to fill in braces and the query parameters that matter. The API reference lists every other read.
- GET /repos/{owner}/{repo}/actions/workflows (per_page, page): The repository's workflows, with each one's file path and whether it is active or switched off.
- GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}: One workflow by its id or file name, such as deploy.yml, with its state.
- GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs (branch, event, status, per_page, page): One workflow's runs, newest first.
- GET /repos/{owner}/{repo}/actions/runs (branch, event, status, per_page, page): Every workflow run in the repository, newest first.
- GET /repos/{owner}/{repo}/actions/runs/{run_id}: One run, with its status, conclusion, commit and who started it.
- GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs (filter, per_page, page): A run's jobs and their steps, each with its conclusion.
- GET /repos/{owner}/{repo}/actions/runs/{run_id}/pending_deployments: Deployments a run is waiting on approval for.
- GET /repos/{owner}/{repo}/actions/runs/{run_id}/approvals: Who approved or rejected a run's deployments.
- GET /repos/{owner}/{repo}/actions/secrets (per_page, page): The repository's Actions secrets, by name and when each changed, never their values.
- GET /repos/{owner}/{repo}/actions/variables (per_page, page): The repository's Actions variables.
- GET /repos/{owner}/{repo}/actions/runners (per_page, page): Self-hosted runners and whether each is online and busy.
- GET /repos/{owner}/{repo}/actions/permissions: Whether Actions is on for the repository and which actions it allows.
- GET /repos/{owner}/{repo}/deployments (ref, environment, per_page, page): Deployments, newest first, by environment, ref or commit.
- GET /repos/{owner}/{repo}/deployments/{deployment_id}/statuses (per_page, page): A deployment's statuses, newest first, with where it went live.
- GET /repos/{owner}/{repo}/environments (per_page, page): The repository's environments and their protection rules.
- GET /repos/{owner}/{repo}/environments/{environment_name}: One environment, with its reviewers, wait timer and branch policy.
- GET /repos/{owner}/{repo}/environments/{environment_name}/secrets (per_page, page): An environment's secrets, by name and when each changed, never their values.
- GET /repos/{owner}/{repo}/releases (per_page, page): Releases, newest first.
- GET /repos/{owner}/{repo}/releases/latest: The latest published release.
- GET /repos/{owner}/{repo}/tags (per_page, page): The repository's tags.
- GET /repos/{owner}/{repo}/commits (sha, path, since, until, per_page): Commits on a branch or touching a path, newest first, between two times.
- GET /repos/{owner}/{repo}/commits/{ref} (page, per_page): One commit, with its files and changes.
- GET /repos/{owner}/{repo}/commits/{ref}/status (per_page, page): The combined status of a commit or branch from every status check.
- GET /repos/{owner}/{repo}/commits/{ref}/check-runs (status, filter, per_page, page): Check runs on a commit or branch, each with its conclusion.
- GET /repos/{owner}/{repo}/compare/{basehead} (page, per_page): What changed between two refs, written base...head.
- GET /repos/{owner}/{repo}/branches/{branch}/protection: A branch's protection, its required checks and reviews.
- GET /repos/{owner}/{repo}/rulesets (per_page, page): The rulesets that apply to the repository.
- GET /repos/{owner}/{repo}/activity (per_page, after, ref): Pushes, force pushes, branch creations and deletions, with who did each and when.
- GET /repos/{owner}/{repo}/events (per_page, page): Recent events in the repository, such as pushes, releases and members added.
- GET /repos/{owner}/{repo}/collaborators (per_page, page): Who has access to the repository and with which permission.
- GET /repos/{owner}/{repo}/keys (per_page, page): The repository's deploy keys, with whether each can write and when it was last used.
- GET /repos/{owner}/{repo}/hooks (per_page, page): The repository's webhooks, with their events and last delivery.
- GET /repos/{owner}/{repo}/hooks/{hook_id}/deliveries (per_page, cursor, status): A webhook's recent deliveries and their status codes.
- GET /repos/{owner}/{repo}/secret-scanning/alerts (state, page, per_page, after): Leaked secrets found in the repository, with their type and state.
- GET /repos/{owner}/{repo}/dependabot/alerts (state, after, per_page): Vulnerable dependencies, with severity and state.
- GET /repos/{owner}/{repo}/code-scanning/alerts (page, per_page, ref, after, state): Code scanning alerts, with severity and state.
- GET /repos/{owner}/{repo}/pages: The repository's Pages site, with its domain, certificate and build state.
- GET /orgs/{org}/members (filter, per_page, page): The organization's members.
- GET /orgs/{org}/personal-access-tokens (per_page, page): Fine-grained tokens with access to the organization, with when each was last used.
- GET /rate_limit: How much of GitHub's rate limit the connection has left.
