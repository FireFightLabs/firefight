module Integrations
  module Packs
    class Gitlab
      # A project's releases and tags (doc/api/releases/_index.md, list releases and get a release by a tag name, and
      # doc/api/tags.md, list repository tags). They only read, with the read_api scope.
      module Releases
        LIMIT = 10
        MAX_LIMIT = 100
        NOTES_SHOWN = 4_000

        def self.included(pack)
          repo = pack::REPO_PARAM
          limit = { "type" => "integer", "description" => "At most this many (optional, #{LIMIT}, at most #{MAX_LIMIT})" }
          pack.tool :list_releases,
                    summary: "Lists a project's releases, newest first.",
                    description: "A project's releases, newest first, with each one's tag, name, when it was released, whether it is still " \
                                 "upcoming, its commit and its page",
                    params_schema: CodeHost::Code.object_schema({ "repo" => repo, "limit" => limit }, %w[repo]),
                    read_only: true

          pack.tool :release_lookup,
                    summary: "Shows one release with its notes and files.",
                    description: "One release by its tag, with its notes, its commit and its files and links",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo, "tag" => { "type" => "string", "description" => "The release's tag, such as v2.4.0" }
                    }, %w[repo tag]),
                    read_only: true

          pack.tool :list_tags,
                    summary: "Lists a project's tags and the commit each one points at.",
                    description: "A project's tags, newest first, with the commit each one points at, its message and its release, " \
                                 "narrowed to names that start or end with some text when asked",
                    params_schema: CodeHost::Code.object_schema({
                      "repo" => repo,
                      "search" => { "type" => "string", "description" => "Only tags whose name holds this, ^v1 for names starting with v1 or -rc$ for names ending with -rc (optional)" },
                      "limit" => limit
                    }, %w[repo]),
                    read_only: true
        end

        def list_releases(environment_row:, arguments:)
          repo = repo_argument(arguments)
          gitlab = api(environment_row)
          releases = Array(gitlab.get("#{GitlabApi.project(repo)}/releases", "per_page" => whole_number_argument(arguments, "limit", LIMIT, MAX_LIMIT)))
          text = releases.empty? ? "#{repo} has no releases." : "Releases in #{repo}, newest first:\n#{releases.map { |release| release_line(release) }.join("\n")}"
          Telemetry.result(text, link: link(gitlab.web_url(repo, "-", "releases")))
        end

        def release_lookup(environment_row:, arguments:)
          repo = repo_argument(arguments)
          tag = ref_argument(arguments, "tag", required: true)
          gitlab = api(environment_row)
          release = begin
            gitlab.get("#{GitlabApi.project(repo)}/releases/#{Http.segment(tag)}")
          rescue GitlabApi::NotFound
            fail! "GitLab has no release tagged #{tag} in #{repo}. list_releases shows the releases it has."
          end
          files = Array(release.dig("assets", "links")).map { |file| "  #{file['name']}  #{file['url']}" }
          notes = release["description"].to_s.strip.truncate(NOTES_SHOWN).presence || "(no notes)"
          text = [ release_line(release).strip, ("Files and links:\n#{files.join("\n")}" if files.any?), notes ].compact.join("\n\n")
          Telemetry.result(text, link: link(release.dig("_links", "self")))
        end

        def list_tags(environment_row:, arguments:)
          repo = repo_argument(arguments)
          gitlab = api(environment_row)
          query = { "order_by" => "updated", "sort" => "desc", "search" => arguments["search"].to_s.strip.presence,
                    "per_page" => whole_number_argument(arguments, "limit", LIMIT, MAX_LIMIT) }.compact
          tags = Array(gitlab.get("#{GitlabApi.project(repo)}/repository/tags", query))
          text = if tags.empty?
            "#{repo} has no tags#{" matching #{query['search']}" if query['search']}."
          else
            "Tags in #{repo}, newest first:\n#{tags.map { |tag| tag_line(tag) }.join("\n")}"
          end
          Telemetry.result(text, link: link(gitlab.web_url(repo, "-", "tags")))
        end

        private

        def release_line(release)
          upcoming = release["upcoming_release"] ? ", upcoming" : ""
          "  #{release['tag_name']}  #{release['name']}  released #{release['released_at']}#{upcoming}  commit #{release.dig('commit', 'short_id') || release.dig('commit', 'id').to_s[0, 12]}  " \
            "#{release.dig('_links', 'self')}"
        end

        def tag_line(tag)
          message = tag["message"].to_s.lines.first.to_s.strip.presence
          "  #{tag['name']}  #{tag.dig('commit', 'id').to_s[0, 12]}  #{tag.dig('commit', 'committed_date')}#{"  #{message}" if message}#{'  has a release' if tag['release']}"
        end
      end
    end
  end
end
