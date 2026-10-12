module Integrations
  module Packs
    class Github
      # Reverting a merged pull request, which GitHub's REST API has no call for, so it is built from the Git database
      # (git/get-commit, git/create-commit, git/create-ref and git/update-ref) and a merge (repos/merge) in
      # github/rest-api-description, all Contents write, then opened as a pull request (pulls/create, Pull requests write).
      # A commit whose tree is the code before the pull request, made on top of what it merged, is the pull request
      # undone. GitHub merges that commit into a branch under halon/ made from the base branch as it is now, which applies
      # the undoing to every change since, and the result is kept as one commit on the base. A merge GitHub cannot make
      # cleanly is refused and the branch deleted, so nothing half done is left. The revert merges only through its pull
      # request, so the base branch's reviews and checks hold as for any other change.
      module Reverting
        # The most commits of a rebase merge walked back, each one a call.
        REBASE_LIMIT = 50
        CONFLICT = /answered 409/
        EXISTS = /answered 422/

        def self.included(pack)
          pack.tool :revert_pull_request,
                    description: "Open a pull request that reverts a merged pull request, on a branch under #{Branches::PREFIX} made from its " \
                                 "base branch as it is now. Nothing reaches the base branch until that pull request is reviewed and merged. " \
                                 "A pull request whose changes were since changed again, so it does not revert cleanly, is refused",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, "number" => { "type" => "integer", "description" => "The merged pull request's number" },
                      "reason" => { "type" => "string", "description" => "Why it is reverted, for the new pull request's description (optional)" }
                    }, %w[repo number]),
                    read_only: false
        end

        def revert_pull_request(environment_row:, arguments:)
          repo, number, token = pull_target(arguments, environment_row)
          reason = written_text(arguments, "reason", required: false)
          asking("revert_pull_request", "GitHub has no pull request #{number} in #{repo}") do
            pull = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
            unless pull["merged_at"] && pull["merge_commit_sha"]
              fail_policy! "PR ##{number} in #{repo} was never merged, so there is nothing to revert. close_pull_request closes it."
            end

            reverted(repo, pull, reason, token)
          end
        end

        private

        def reverted(repo, pull, reason, token)
          number = pull["number"]
          base = pull.dig("base", "ref")
          branch = "#{Branches::PREFIX}revert-pr-#{number}"
          before, merged = reverted_range(repo, pull, token)
          title = Chat::SecretFree.redacted("Revert \"#{pull['title']}\"").truncate(Asking::TITLE_LIMIT)
          head = GithubApp.get("/repos/#{repo}/git/ref/heads/#{ref_path(base)}", token: token).dig("object", "sha")
          tree = GithubApp.get("/repos/#{repo}/git/commits/#{before}", token: token).dig("tree", "sha")
          undoing = GithubApp.write(:post, "/repos/#{repo}/git/commits", { message: title, tree: tree, parents: [ merged ] }, token: token)
          make_revert_branch(repo, branch, head, token)

          begin
            revert = revert_commit(repo, branch, head, undoing["sha"], "#{title}\n\nThis reverts PR ##{number}, #{pull['merge_commit_sha']}.", token)
            GithubApp.write(:patch, "/repos/#{repo}/git/refs/heads/#{ref_path(branch)}", { sha: revert, force: true }, token: token)
            body = [ "Reverts ##{number}.", reason ].compact.join("\n\n")
            opened = GithubApp.open_pull_request(repo, base: base, branch: branch, title: title, body: body, token: token)
          rescue StandardError
            drop_revert_branch(repo, branch, token)
            raise
          end
          linked("Opened PR ##{opened['number']} #{title} in #{repo}, from #{branch} into #{base}, which undoes PR ##{number} on #{base} as it is " \
                 "now at #{head.to_s[0, 12]}. It merges once it is reviewed like any other change.", opened["html_url"])
        end

        # The commit before the pull request and the last commit it put on the base. A merge commit's first parent is the
        # base before it. A squash is one commit. A rebase put each of the pull request's commits on the base, which is
        # told apart from a squash by the commits before the merge commit carrying the pull request's own messages.
        def reverted_range(repo, pull, token)
          merged = pull["merge_commit_sha"]
          commit = GithubApp.get("/repos/#{repo}/git/commits/#{merged}", token: token)
          parents = Array(commit["parents"]).map { |parent| parent["sha"] }
          return [ parents.first, merged ] if parents.size > 1 || pull["commits"].to_i <= 1

          count = pull["commits"].to_i
          fail_policy! "PR ##{pull['number']} put #{count} commits on its base, more than the #{REBASE_LIMIT} Firefight walks back. A person reverts it by hand." if count > REBASE_LIMIT

          messages = Array(GithubApp.get("/repos/#{repo}/pulls/#{pull['number']}/commits?per_page=100", token: token)).map { |each| each.dig("commit", "message").to_s.strip }
          walked = [ commit ]
          (count - 1).times { walked << GithubApp.get("/repos/#{repo}/git/commits/#{walked.last.dig('parents', 0, 'sha')}", token: token) }
          rebased = walked.reverse.map { |each| each["message"].to_s.strip } == messages
          [ rebased ? walked.last.dig("parents", 0, "sha") : parents.first, merged ]
        end

        def make_revert_branch(repo, branch, head, token)
          GithubApp.write(:post, "/repos/#{repo}/git/refs", { ref: "refs/heads/#{branch}", sha: head }, token: token)
        rescue GithubApp::Error => error
          raise unless error.message.match?(EXISTS)

          fail_policy! "#{branch} is already in #{repo}, likely from an earlier revert. list_pull_requests with head #{branch} shows its pull request, and " \
                       "delete_branch removes the branch if it is not wanted."
        end

        # GitHub merges the undoing commit into the branch, then the result is kept as one commit on the base's head.
        def revert_commit(repo, branch, head, undoing, message, token)
          merge = GithubApp.write(:post, "/repos/#{repo}/merges", { base: branch, head: undoing, commit_message: message }, token: token)
          fail_policy! "Every change of that pull request is already undone on #{repo}'s base branch, so there is nothing to revert." if merge.blank?

          GithubApp.write(:post, "/repos/#{repo}/git/commits", { message: message, tree: merge.dig("commit", "tree", "sha"), parents: [ head ] }, token: token)["sha"]
        rescue GithubApp::Error => error
          raise unless error.message.match?(CONFLICT)

          fail_policy! "The pull request does not revert cleanly onto the base branch as it is now, since later changes touch the same lines. " \
                       "A person reverts it by hand and settles the conflicts."
        end

        # A branch left behind by a revert that stopped part way is removed. One GitHub will not remove is left for a person,
        # since the refusal that stopped the revert is what they need to hear.
        def drop_revert_branch(repo, branch, token)
          GithubApp.write(:delete, "/repos/#{repo}/git/refs/heads/#{ref_path(branch)}", token: token)
        rescue GithubApp::Error => error
          Rails.logger.warn("GitHub revert branch #{branch} in #{repo} was not removed: #{error.message}")
        end

        def ref_path(name) = name.split("/").map { |part| Http.segment(part) }.join("/")
      end
    end
  end
end
