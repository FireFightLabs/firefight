---
name: bitbucket_api
when: A question about Bitbucket that the other Bitbucket tools do not answer, such as a repository's deployment environments, branch restrictions, branching model, members and permissions, or a workspace's projects, or anything else Bitbucket's REST API reads, and finding out whether Bitbucket's API offers a read at all
tools: [api_read, list_repositories]
---
`api_read` sends a GET to any path of Bitbucket Cloud's REST API and answers what Bitbucket said. It only reads, so it never needs the person's go ahead and works while investigating and watching. Changes go through Bitbucket's other tools, never through this.

1. Use the named tools first where they answer the question, since their answers are shaped and linked: `list_repositories` for what this connection reads, and the pull request, pipeline and file tools for those. Reach for `api_read` for the rest.
2. Find the path in Bitbucket's REST reference before the first call, not by guessing. Bitbucket publishes it at https://developer.atlassian.com/cloud/bitbucket/rest/intro/ with every read listed by area. Read it with the web reading tool, where the workspace allows reading the web. Bitbucket's reference is not copied into Firefight's documentation. When the reference lists no read for the question, Bitbucket's API does not offer it. Say so, and give the steps in Bitbucket instead.
3. Write the path after /2.0, naming the workspace and repository as `list_repositories` shows them, such as /repositories/acme/checkout/environments. A read names a workspace this connection reads, unless it reads every workspace its token can. Put every parameter in `query`, never in the path.
4. A list answers one page. Pass pagelen, at most 100, and read on with page 2, 3 and so on while the answer names a next page.
5. Pipeline and deployment variables and webhooks come back as their names, with values hidden. Downloads, a file's source, diffs and step logs are not read here. Use the file tools, the compare tool and the job log tool in the failing pipeline skill.
