module Integrations
  module Packs
    class Github
      # A repository's releases and tags (repos/list-releases, get-latest-release, get-release-by-tag and list-tags in
      # github/rest-api-description). Releases are Contents read, tags Metadata. A release Firefight makes is always a
      # draft (repos/create-release with draft true), which nobody outside the repository sees and which makes no tag until
      # it is published. Editing and publishing a release are both repos/update-release, Contents write, and publishing is
      # its own tool so an approval rule can hold it apart from an edit.
      module Releases
        NOTES_SHOWN = 4_000
        # Drafts have no tag yet and get-release-by-tag finds only a published release, so a release named by its tag is
        # looked for in the list, 100 at a time.
        LIST_PAGES = 10
        RELEASE_PARAMS = {
          "tag" => { "type" => "string", "description" => "The release's tag, such as v2.4.1, or for a draft the tag it will have (this or id)" },
          "id" => { "type" => "integer", "description" => "The release's id, which list_releases shows (this or tag)" }
        }.freeze

        def self.included(pack)
          pack.tool :list_releases,
                    summary: "Lists a repository's releases, including drafts and prereleases.",
                    description: "A repository's releases, newest first, with each one's tag, whether it is a draft or a prerelease, when it was published and its page",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{Asking::LIST_LIMIT}, at most #{Asking::MAX_LIST})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :release_lookup,
                    summary: "Shows one release with its notes and files.",
                    description: "One release with its notes and files: by its tag, or the latest published one",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, "tag" => { "type" => "string", "description" => "The release's tag, such as v2.4.0 (optional, the latest release)" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :list_tags,
                    summary: "Lists a repository's tags and the commit each one points at.",
                    description: "A repository's tags, with the commit each one points at",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{Asking::LIST_LIMIT}, at most #{Asking::MAX_LIST})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :create_draft_release,
                    summary: "Creates a draft release for a person to review.",
                    description: "Write a draft release for a person to review. Nobody outside the repository sees a draft, and its tag is " \
                                 "made only when it is published",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "tag" => { "type" => "string", "description" => "The tag the release will have, such as v2.4.1" },
                      "target" => { "type" => "string", "description" => "The branch or commit SHA the tag will point at (optional, the default branch)" },
                      "name" => { "type" => "string", "description" => "The release's title (optional, the tag)" },
                      "body" => { "type" => "string", "description" => "The release notes, in GitHub's markdown (optional)" },
                      "generate_notes" => { "type" => "boolean", "description" => "Let GitHub write the notes from what merged since the last release (optional)" }
                    }, %w[repo tag]),
                    read_only: false

          pack.tool :update_release,
                    summary: "Updates a release's notes, title or prerelease flag.",
                    description: "Change a release's notes, title or prerelease flag, on a draft or a published release, such as filling in " \
                                 "a placeholder a release workflow left in a draft's notes before it is published. It does not publish a draft",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, **RELEASE_PARAMS,
                      "body" => { "type" => "string", "description" => "New notes in GitHub's markdown, replacing all of the old ones (optional)" },
                      "replace" => { "type" => "string", "description" => "Text in the notes to replace, such as a template's placeholder, " \
                                                                           "instead of giving the whole notes in body (optional)" },
                      "with" => { "type" => "string", "description" => "What replaces each place replace appears (with replace)" },
                      "name" => { "type" => "string", "description" => "The new title (optional)" },
                      "prerelease" => { "type" => "boolean", "description" => "Whether it is a prerelease (optional)" }
                    }, %w[repo]),
                    read_only: false

          pack.tool :publish_release,
                    summary: "Publishes a draft release and notifies the repository's watchers.",
                    description: "Publish a draft release. Its notes become public, it is marked the repository's latest release unless " \
                                 "make_latest is false or it is a prerelease, its tag is made on its target if the tag does not exist yet, " \
                                 "GitHub notifies the repository's watchers and sends the release published event. Publishing builds and " \
                                 "deploys nothing itself, though a workflow that runs on a published release starts. A release already " \
                                 "published is refused",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, **RELEASE_PARAMS,
                      "make_latest" => { "type" => "boolean", "description" => "Whether it becomes the repository's latest release (optional, true)" }
                    }, %w[repo]),
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
                   "Nobody outside the repository sees it until it is published, which makes the tag.", release["html_url"])
          end
        end

        def update_release(environment_row:, arguments:)
          repo = repo_argument(arguments)
          changes = { name: written_text(arguments, "name", required: false, limit: Asking::TITLE_LIMIT),
                      prerelease: (boolean_argument(arguments, "prerelease") unless arguments["prerelease"].nil?) }.compact
          body = written_text(arguments, "body", required: false)
          placeholder = arguments["replace"].to_s
          fail! "Give body or replace, not both." if body && placeholder.present?
          fail! "Give body, replace and with, name or prerelease to change." if changes.empty? && body.nil? && placeholder.empty?

          token = GithubApp.installation_token(environment_row)
          asking("update_release", "GitHub has no release #{release_words(arguments)} in #{repo}") do
            release = release_of(repo, arguments, token)
            notes = placeholder.present? ? replaced_notes(release, placeholder, arguments) : body
            updated = GithubApp.write(:patch, "/repos/#{repo}/releases/#{release['id']}", changes.merge(body: notes).compact, token: token)
            linked("Changed the #{changed_words(changes, notes)} of #{release_name(updated)} in #{repo}, which is #{updated['draft'] ? 'still a draft' : 'published'}.\n\n" \
                   "#{release_line(updated).strip}\n\n#{shown(updated['body'], NOTES_SHOWN) || '(no notes)'}", updated["html_url"])
          end
        end

        def publish_release(environment_row:, arguments:)
          repo = repo_argument(arguments)
          latest = (boolean_argument(arguments, "make_latest").to_s unless arguments["make_latest"].nil?)
          token = GithubApp.installation_token(environment_row)
          asking("publish_release", "GitHub has no release #{release_words(arguments)} in #{repo}") do
            release = release_of(repo, arguments, token)
            fail_policy! "The #{release_name(release)} in #{repo} was already published at #{release['published_at']}, so it is not published again." unless release["draft"]

            # make_latest is a string to GitHub (true, false or legacy), and left out it is true (repos/update-release).
            published = GithubApp.write(:patch, "/repos/#{repo}/releases/#{release['id']}", { draft: false, make_latest: latest }.compact, token: token)
            marked = published["prerelease"] || latest == "false" ? "It is not marked the latest release" : "It is marked the latest release"
            linked("Published the #{release_name(published)} for tag #{published['tag_name']} on #{published['target_commitish']} in #{repo}. " \
                   "#{marked}, and its notes are public.", published["html_url"])
          end
        end

        private

        # The release a tool names, by its id, or by its tag among every release including drafts. Drafts can share a tag,
        # so two with one are refused rather than one picked.
        def release_of(repo, arguments, token)
          id = (number_argument(arguments, "id") if arguments["id"].present?)
          tag = ref_argument(arguments, "tag")
          fail! "Give the release's tag or its id, not both." if id && tag
          fail! "Give the release's tag or its id." unless id || tag
          return GithubApp.get("/repos/#{repo}/releases/#{id}", token: token) if id

          found = Pages.read(max_pages: LIST_PAGES) do |page|
            listed = Array(GithubApp.get("/repos/#{repo}/releases?per_page=#{Asking::MAX_LIST}&page=#{page || 1}", token: token))
            [ listed.select { |release| release["tag_name"] == tag }, (listed.size == Asking::MAX_LIST ? (page || 1) + 1 : nil) ]
          end
          tagged = found.items
          return tagged.first if tagged.one?
          if tagged.many?
            fail_policy! "#{tagged.size} releases in #{repo} have tag #{tag}, " \
                         "#{tagged.map { |release| "id #{release['id']} (#{release_name(release)})" }.to_sentence}. Give the id of the one meant."
          end

          fail! "GitHub has no release, draft or published, with tag #{tag} in #{repo}#{" among its newest #{LIST_PAGES * Asking::MAX_LIST}" if found.incomplete?}. " \
                "list_releases shows the releases it has."
        end

        def replaced_notes(release, placeholder, arguments)
          fail! "with is required with replace" if arguments["with"].nil?

          notes = release["body"].to_s
          fail! "The notes of the #{release_name(release)} do not contain #{placeholder.inspect}, so nothing was changed." unless notes.include?(placeholder)

          written = written_text(arguments, "with", required: false).to_s
          replaced = notes.gsub(placeholder) { written }
          fail! "The notes would be longer than GitHub takes, #{Asking::BODY_LIMIT} characters" if replaced.length > Asking::BODY_LIMIT

          replaced
        end

        def changed_words(changes, notes)
          [ ("notes" if notes), ("title" if changes.key?(:name)), ("prerelease flag" if changes.key?(:prerelease)) ].compact.to_sentence
        end

        def release_words(arguments) = arguments["id"].present? ? "with id #{arguments['id']}" : "tagged #{arguments['tag']}"

        def release_name(release) = "release #{release['name'].presence || release['tag_name']}"

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
