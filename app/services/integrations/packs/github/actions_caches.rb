module Integrations
  module Packs
    class Github
      # Clearing a repository's GitHub Actions caches (actions/get-actions-cache-list, delete-actions-cache-by-key and
      # delete-actions-cache-by-id in github/rest-api-description), Actions read to list and read and write to delete.
      # A key or a ref is always named, so the whole repository's caches are never cleared at once.
      module ActionsCaches
        CACHE_PAGES = 10
        PER_PAGE = 100
        SHOWN = 20

        def self.included(pack)
          pack.tool :clear_actions_cache,
                    description: "Delete a repository's GitHub Actions caches with a key, or every cache made on a branch or ref, such as a " \
                                 "poisoned dependency cache that keeps failing builds. The next run on that ref builds its cache again, " \
                                 "which makes it slower once",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "key" => { "type" => "string", "description" => "The cache's key, exactly as the run saved it (this, ref or both)" },
                      "ref" => { "type" => "string", "description" => "A branch, such as main, or a full ref such as refs/pull/412/merge (this, key or both)" }
                    }, %w[repo]),
                    read_only: false
        end

        def clear_actions_cache(environment_row:, arguments:)
          repo = repo_argument(arguments)
          key = arguments["key"].to_s.strip.presence
          ref = cache_ref_argument(arguments)
          fail_policy! "Give a cache's key or a ref, since Firefight never clears every cache in a repository at once." unless key || ref

          token = GithubApp.installation_token(environment_row)
          where = [ ("key #{key}" if key), ("on #{ref}" if ref) ].compact.join(" ")
          asking("clear_actions_cache", "GitHub has no Actions cache with #{where} in #{repo}") do
            cleared = key ? cleared_by_key(repo, key, ref, token) : cleared_on_ref(repo, ref, token)
            next linked("#{repo} has no Actions cache #{where}, so nothing was cleared.", repo_page(repo, "actions/caches")) if cleared.empty?

            bytes = cleared.sum { |cache| cache["size_in_bytes"].to_i }
            lines = cleared.first(SHOWN).map { |cache| "  #{cache['key']}  #{cache['ref']}  #{cache['size_in_bytes']} bytes" }
            linked("Cleared #{cleared.size} Actions #{'cache'.pluralize(cleared.size)} #{where} in #{repo}, #{bytes} bytes:\n#{lines.join("\n")}" \
                   "#{"\n(and #{cleared.size - SHOWN} more)" if cleared.size > SHOWN}", repo_page(repo, "actions/caches"))
          end
        end

        private

        def cleared_by_key(repo, key, ref, token)
          Array(GithubApp.write(:delete, "/repos/#{repo}/actions/caches?#{{ 'key' => key, 'ref' => ref }.compact.to_query}", token: token)["actions_caches"])
        end

        def cleared_on_ref(repo, ref, token)
          caches = Pages.read(max_pages: CACHE_PAGES) do |page|
            listed = Array(GithubApp.get("/repos/#{repo}/actions/caches?#{{ 'ref' => ref, 'per_page' => PER_PAGE, 'page' => page || 1 }.to_query}", token: token)["actions_caches"])
            [ listed, (listed.size == PER_PAGE ? (page || 1) + 1 : nil) ]
          end.items
          caches.each { |cache| GithubApp.write(:delete, "/repos/#{repo}/actions/caches/#{cache['id']}", token: token) }
        end

        # A branch is named as GitHub's cache list takes it, refs/heads/<branch>, and a full ref is kept as given.
        def cache_ref_argument(arguments)
          ref = ref_argument(arguments, "ref")
          return nil unless ref

          ref.start_with?("refs/") ? ref : "refs/heads/#{ref}"
        end
      end
    end
  end
end
