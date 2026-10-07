module Integrations
  module Packs
    class Github
      # A repository's releases and tags (repos/list-releases, get-latest-release, get-release-by-tag and list-tags in
      # github/rest-api-description). Releases are Contents read, tags Metadata. A release Firefight makes is always a
      # draft (repos/create-release with draft true), which nobody outside the repository sees and which makes no tag until
      # a person publishes it, so publishing stays a person's.
      module Releases
        NOTES_SHOWN = 4_000

        def self.included(pack)
          pack.tool :list_releases,
                    description: "A repository's releases, newest first, with each one's tag, whether it is a draft or a prerelease, when it was published and its page",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{Asking::LIST_LIMIT}, at most #{Asking::MAX_LIST})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :release_lookup,
                    description: "One release with its notes and files: by its tag, or the latest published one",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, "tag" => { "type" => "string", "description" => "The release's tag, such as v2.4.0 (optional, the latest release)" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :list_tags,
                    description: "A repository's tags, with the commit each one points at",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{Asking::LIST_LIMIT}, at most #{Asking::MAX_LIST})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :create_draft_release,
                    description: "Write a draft release for a person to review and publish on GitHub. It is never published here, and its tag is " \
                                 "made only when a person publishes it",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "tag" => { "type" => "string", "description" => "The tag the release will have, such as v2.4.1" },
                      "target" => { "type" => "string", "description" => "The branch or commit SHA the tag will point at (optional, the default branch)" },
                      "name" => { "type" => "string", "description" => "The release's title (optional, the tag)" },
                      "body" => { "type" => "string", "description" => "The release notes, in GitHub's markdown (optional)" },
                      "generate_notes" => { "type" => "boolean", "description" => "Let GitHub write the notes from what merged since the last release (optional)" }
                    }, %w[repo tag]),
                    read_only: false
        end

        def list_releases(environment_row:, arguments:)
          repo = repo_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          asking("list_releases", "GitHub found no repository #{repo}") do
            releases = Array(GithubApp.get("/repos/#{repo}/releases?per_page=#{limit_argument(arguments)}", token: token))
            text = releases.empty? ? "#{repo} has no releases." : "Releases in #{repo}, newest first:\n#{releases.map { |release| release_line(release) }.join("\n")}"
            linked(text, repo_page(repo, "releases"))
          end
        end

        def release_lookup(environment_row:, arguments:)
          repo = repo_argument(arguments)
          tag = ref_argument(arguments, "tag")
          token = GithubApp.installation_token(environment_row)
          asking("release_lookup", tag ? "GitHub has no release tagged #{tag} in #{repo}" : "#{repo} has no published release") do
            release = GithubApp.get("/repos/#{repo}/releases/#{tag ? "tags/#{Http.segment(tag)}" : 'latest'}", token: token)
            assets = Array(release["assets"]).map { |asset| "  #{asset['name']} (#{asset['size']} bytes, #{asset['download_count']} downloads)" }
            lines = [ release_line(release).strip, ("Files:\n#{assets.join("\n")}" if assets.any?), shown(release["body"], NOTES_SHOWN) || "(no notes)" ].compact
            linked(lines.join("\n\n"), release["html_url"])
          end
        end

        def list_tags(environment_row:, arguments:)
          repo = repo_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          asking("list_tags", "GitHub found no repository #{repo}") do
            tags = Array(GithubApp.get("/repos/#{repo}/tags?per_page=#{limit_argument(arguments)}", token: token))
            text = tags.empty? ? "#{repo} has no tags." : "Tags in #{repo}:\n#{tags.map { |tag| "  #{tag['name']}  #{tag.dig('commit', 'sha').to_s[0, 12]}" }.join("\n")}"
            linked(text, repo_page(repo, "tags"))
          end
        end

        def create_draft_release(environment_row:, arguments:)
          repo = repo_argument(arguments)
          tag = ref_argument(arguments, "tag", required: true)
          target = ref_argument(arguments, "target")
          name = written_text(arguments, "name", required: false, limit: Asking::TITLE_LIMIT)
          body = written_text(arguments, "body", required: false)
          token = GithubApp.installation_token(environment_row)
          asking("create_draft_release", "GitHub found no repository #{repo}") do
            release = GithubApp.write(:post, "/repos/#{repo}/releases",
                                      { tag_name: tag, target_commitish: target, name: name, body: body, draft: true,
                                        generate_release_notes: boolean_argument(arguments, "generate_notes") }.compact, token: token)
            linked("Wrote a draft release #{release['name'].presence || tag} for tag #{tag} on #{release['target_commitish']} in #{repo}. " \
                   "Nobody outside the repository sees it, and a person publishes it on GitHub, which makes the tag.", release["html_url"])
          end
        end

        private

        def release_line(release)
          kind = if release["draft"] then "draft"
          elsif release["prerelease"] then "prerelease published #{release['published_at']}"
          else "published #{release['published_at']}"
          end
          "  #{release['tag_name']}  #{release['name'].presence || release['tag_name']}  #{kind}  by #{release.dig('author', 'login') || 'unknown'}  " \
            "on #{release['target_commitish']}  #{release['html_url']}"
        end
      end
    end
  end
end
