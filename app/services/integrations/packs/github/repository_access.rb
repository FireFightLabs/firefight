module Integrations
  module Packs
    class Github
      # Who can reach a repository: its collaborators with their role (repos/list-collaborators, Metadata read, which
      # every App holds), the teams given it (repos/list-teams, Administration read) and, in an organization, which
      # collaborators are outside collaborators rather than members (orgs/list-outside-collaborators, Members read). The
      # teams and the outside collaborators only add to the answer, which says which permission would show them.
      module RepositoryAccess
        ACCESS_PAGES = 5
        PER_PAGE = 100
        ORGANIZATION = "Organization".freeze

        def self.included(pack)
          pack.tool :repository_access,
                    description: "Who can reach a repository: each person with access and their role (read, triage, write, maintain or " \
                                 "admin), the teams given it with theirs, and in an organization which people are outside collaborators " \
                                 "rather than members",
                    params_schema: Code.object_schema({ "repo" => Code::REPO }, %w[repo]),
                    read_only: true
        end

        def repository_access(environment_row:, arguments:)
          repo = repo_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          asking("repository_access", "GitHub found no repository #{repo}") do
            owner = GithubApp.get("/repos/#{repo}", token: token)["owner"].to_h
            people = paged(token) { |page| "/repos/#{repo}/collaborators?#{{ 'affiliation' => 'all', 'per_page' => PER_PAGE, 'page' => page }.to_query}" }
            outside, outside_note = outside_collaborators(owner, token)
            lines = people.items.map do |person|
              "  #{person['login']}  #{person['role_name'] || role_of(person['permissions'])}#{'  outside collaborator' if outside&.include?(person['login'])}"
            end
            sections = [
              people.items.empty? ? "Nobody has access to #{repo}." : "People with access to #{repo}#{" (the first #{people.items.size})" if people.incomplete?}:\n#{lines.join("\n")}",
              adding("Teams", "Administration read") { teams_text(repo, token) },
              outside_note
            ].compact
            linked(sections.join("\n\n"), repo_page(repo, "settings/access"))
          end
        end

        private

        def paged(token)
          Pages.read(max_pages: ACCESS_PAGES) do |page|
            listed = Array(GithubApp.get(yield(page || 1), token: token))
            [ listed, (listed.size == PER_PAGE ? (page || 1) + 1 : nil) ]
          end
        end

        # The logins of the organization's outside collaborators, or nil with a line saying why they are not known.
        def outside_collaborators(owner, token)
          return [ nil, nil ] unless owner["type"] == ORGANIZATION

          logins = paged(token) { |page| "/orgs/#{Http.segment(owner['login'])}/outside_collaborators?per_page=#{PER_PAGE}&page=#{page}" }.items.map { |person| person["login"] }
          [ logins, nil ]
        rescue GithubApp::NotPermitted, GithubApp::NotFound
          [ nil, "Outside collaborators not marked: Firefight's GitHub App needs Members read on the organization for them." ]
        end

        def teams_text(repo, token)
          teams = Array(GithubApp.get("/repos/#{repo}/teams?per_page=#{PER_PAGE}", token: token))
          return "Teams: none." if teams.empty?

          "Teams with access:\n#{teams.map { |team| "  #{team['slug']}  #{team['permission']}" }.join("\n")}"
        end

        def role_of(permissions)
          permissions.to_h.select { |_role, held| held }.keys.max_by { |role| %w[pull triage push maintain admin].index(role).to_i }.to_s
        end
      end
    end
  end
end
