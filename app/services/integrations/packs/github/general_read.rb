module Integrations
  module Packs
    class Github
      # GitHub answers only for what the installation was given, so the connection's repositories hold as for every other
      # tool. Which permission a path needs is GitHub's, so a refusal names the one its answer names.
      module GeneralRead
        def self.included(pack)
          pack.tool ApiReads::TOOL,
                    description: "Anything else GitHub's REST API reads that the other GitHub tools do not cover, such as a repository's " \
                                 "environments and their protection rules, deployment statuses, rulesets, collaborators, teams, webhooks' " \
                                 "deliveries, packages, Pages, traffic or an organization's settings. A GET to a path of GitHub's REST API " \
                                 "(#{GithubApp::API_ROOT}), as the API reference the github_api skill names writes it, such as " \
                                 "/repos/<owner>/<repo>/environments. A list answers one page: pass per_page, at most 100, and page 2, 3 " \
                                 "and on while a page comes back full. Only reads, so it never changes anything. Secrets and webhooks come " \
                                 "back as their names",
                    params_schema: ApiReads.path_schema("/repos/<owner>/<repo>/environments"),
                    read_only: true
        end

        def api_read(environment_row:, arguments:)
          call = begin
            ReadGuards::Github.reading(ApiReads::TOOL, arguments)
          rescue ReadGuards::Refused => error
            fail!(error.message)
          end
          path, query = call.values_at("path", "query")
          repo = path.match(%r{\A/repos/([^/]+/[^/]+)})&.[](1)
          token = GithubApp.installation_token(environment_row)
          asking(ApiReads::TOOL, "GitHub found nothing at #{path}") do
            answer = GithubApp.read(path, query, token: token)
            text = ApiReads.answer(GithubApp::PROVIDER, ApiReads.asked(path, query), answer, secret: ReadGuards::Github.secret?(path),
                                                                                   webhooks: ReadGuards::Github.webhooks?(path))
            linked(text, (answer["html_url"].presence if answer.is_a?(Hash)) || (repo_page(repo) if repo))
          end
        end
      end
    end
  end
end
