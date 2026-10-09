module Integrations
  module Packs
    class Github
      # A repository's pull requests through the REST API's pulls and issues paths (github/rest-api-description,
      # docs.github.com REST API, Pulls and Issues). A pull request is an issue to GitHub, so its comments and labels go
      # through issues/{number}, which takes Pull requests write for one (Permissions required for GitHub Apps). Merging is
      # PUT pulls/{number}/merge, which needs Contents write, not Pull requests. Every change is read_only false, so it goes
      # through the gateway, permission packs and approval rules like any other.
      module PullRequests
        STATES = %w[open closed all].freeze
        SORTS = %w[created updated popularity long-running].freeze
        REVIEW_EVENTS = { "approve" => "APPROVE", "request_changes" => "REQUEST_CHANGES", "comment" => "COMMENT" }.freeze
        # Every change to a pull request is read back from GitHub before it is reported, and Halon says only what that shows.
        READ_BACK = "Say only what GitHub shows here about what changed on the pull request.".freeze
        # How much of a description read back is quoted.
        SHOWN_BODY = 300
        MERGE_METHODS = %w[merge squash rebase].freeze
        # mergeable_state as GitHub reports it (GraphQL's MergeStateStatus, which the REST field mirrors in lower case):
        # clean, unstable (non-required checks fail) and has_hooks can merge. behind, blocked, dirty, draft and unknown cannot.
        MERGEABLE_STATES = %w[clean unstable has_hooks].freeze
        STATE_WORDS = {
          "behind" => "its branch is behind its base, so update_pull_request_branch brings it up to date first",
          "blocked" => "a branch protection rule blocks it, such as a required review or a required check that has not passed",
          "dirty" => "it conflicts with its base. fix_code with this pull_request, asked to merge the base in, resolves the " \
                     "conflict, so offer that to the person and run it once they agree",
          "draft" => "it is a draft, which a person marks ready for review",
          "unknown" => "GitHub has not worked out yet whether it can merge, so ask again in a moment"
        }.freeze
        # Halon opened it, so the conflict is Halon's to fix, with the person's yes, rather than a suggestion.
        OWN_CONFLICT = "it conflicts with its base. Firefight opened it, so fixing it is yours: offer fix_code with this pull_request, " \
                       "asked to merge the base in and resolve the conflict, and run it once the person agrees".freeze
        # How long the code host may take to work out whether a pull request can merge after a push, read again meanwhile.
        SETTLE_TRIES = 5
        SETTLE_WAIT = 2
        CHANGES_REQUESTED = "CHANGES_REQUESTED".freeze
        REVIEWS_SHOWN = 20
        COMMENTS_SHOWN = 30
        FILES_SHOWN = 30
        MAX_FILES = 300
        PATCH_LINES = 400
        DEPENDABOT = "dependabot[bot]".freeze
        # How Dependabot names what it bumps: "Bump rack from 2.2.3 to 2.2.8" in the title, and "Updates `rack` from" for
        # each dependency of a grouped update in the body.
        BUMPED = /\bbump (\S+) from /i
        GROUPED = /Updates `([^`]+)` from/
        REPO = Code::REPO
        NUMBER = { "type" => "integer", "description" => "The pull request's number" }.freeze

        def self.included(pack)
          pack.tool :list_pull_requests,
                    description: "List a repository's pull requests, newest first, filtered by state, base or head branch, author, label or " \
                                 "words in them, each with its branches, author and page",
                    params_schema: Code.object_schema({
                      "repo" => REPO,
                      "state" => { "type" => "string", "enum" => STATES, "description" => "open, closed (merged or not) or all (optional, open)" },
                      "base" => { "type" => "string", "description" => "Only pull requests into this branch (optional)" },
                      "head" => { "type" => "string", "description" => "Only pull requests from this branch (optional)" },
                      "author" => { "type" => "string", "description" => "Only pull requests opened by this GitHub login, such as dependabot[bot] (optional)" },
                      "label" => { "type" => "string", "description" => "Only pull requests with this label (optional)" },
                      "text" => { "type" => "string", "description" => "Only pull requests whose title or description has these words (optional)" },
                      "sort" => { "type" => "string", "enum" => SORTS, "description" => "created, updated, popularity or long-running (optional, created)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{Asking::LIST_LIMIT}, at most #{Asking::MAX_LIST})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :pr_lookup,
                    description: "Fetch a pull request: title, state, author, branches, whether GitHub says it can merge, its reviews and " \
                                 "review comments, the checks and statuses on its head commit, its changed files, and for a Dependabot " \
                                 "update the security advisories it fixes",
                    params_schema: Code.object_schema({ "repo" => REPO, "number" => NUMBER }, %w[repo number]),
                    read_only: true

          pack.tool :pull_request_diff,
                    description: "A pull request's changed files with each one's diff, optionally only the files under a path",
                    params_schema: Code.object_schema({
                      "repo" => REPO, "number" => NUMBER,
                      "path" => { "type" => "string", "description" => "Only files whose path starts with this (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many files (optional, #{FILES_SHOWN}, at most #{MAX_FILES})" }
                    }, %w[repo number]),
                    read_only: true

          body = { "type" => "string", "description" => "What to say, in GitHub's markdown" }
          pack.tool :comment_on_pull_request,
                    description: "Add a comment to a pull request's conversation",
                    params_schema: Code.object_schema({ "repo" => REPO, "number" => NUMBER, "body" => body }, %w[repo number body]),
                    read_only: false

          pack.tool :reply_to_review_comment,
                    description: "Reply in the thread of a review comment on a pull request's code, by the comment's id as pr_lookup shows it",
                    params_schema: Code.object_schema({
                      "repo" => REPO, "number" => NUMBER,
                      "comment_id" => { "type" => "integer", "description" => "The review comment's id" }, "body" => body
                    }, %w[repo number comment_id body]),
                    read_only: false

          pack.tool :review_pull_request,
                    description: "Submit a review of a pull request on its current head commit: approve it, request changes or comment, " \
                                 "with comments on lines of its diff if given",
                    params_schema: Code.object_schema({
                      "repo" => REPO, "number" => NUMBER,
                      "event" => { "type" => "string", "enum" => REVIEW_EVENTS.keys, "description" => "approve, request_changes or comment" },
                      "body" => { "type" => "string", "description" => "The review's text, required to request changes or comment (optional to approve)" },
                      "comments" => {
                        "type" => "array", "description" => "Comments on lines of the diff (optional)",
                        "items" => { "type" => "object", "required" => %w[path line body], "properties" => {
                          "path" => { "type" => "string", "description" => "The file's path" },
                          "line" => { "type" => "integer", "description" => "The line in the file as the pull request changes it" },
                          "start_line" => { "type" => "integer", "description" => "The first line, for a comment on several lines (optional)" },
                          "body" => { "type" => "string", "description" => "The comment" }
                        } }
                      }
                    }, %w[repo number event]),
                    read_only: false

          pack.tool :update_pull_request,
                    description: "Change a pull request's title, description or the branch it merges into",
                    params_schema: Code.object_schema({
                      "repo" => REPO, "number" => NUMBER,
                      "title" => { "type" => "string", "description" => "The new title (optional)" },
                      "body" => { "type" => "string", "description" => "The new description, replacing the old one (optional)" },
                      "base" => { "type" => "string", "description" => "The branch to merge into instead (optional)" }
                    }, %w[repo number]),
                    read_only: false

          pack.tool :request_reviewers,
                    description: "Ask people or teams to review a pull request",
                    params_schema: Code.object_schema({
                      "repo" => REPO, "number" => NUMBER,
                      "reviewers" => { "type" => "array", "items" => { "type" => "string" }, "description" => "GitHub logins (optional)" },
                      "team_reviewers" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Team slugs, such as platform (optional)" }
                    }, %w[repo number]),
                    read_only: false

          labels = { "type" => "array", "items" => { "type" => "string" } }
          pack.tool :label_pull_request,
                    description: "Add labels to a pull request or take them off. Only labels the repository already has are added",
                    params_schema: Code.object_schema({
                      "repo" => REPO, "number" => NUMBER,
                      "add" => labels.merge("description" => "Labels to add (optional)"),
                      "remove" => labels.merge("description" => "Labels to take off (optional)")
                    }, %w[repo number]),
                    read_only: false

          comment = { "type" => "string", "description" => "A comment saying why, posted first (optional)" }
          pack.tool :close_pull_request,
                    description: "Close a pull request without merging it, with a comment saying why if given. It can be reopened",
                    params_schema: Code.object_schema({ "repo" => REPO, "number" => NUMBER, "comment" => comment }, %w[repo number]),
                    read_only: false

          pack.tool :reopen_pull_request,
                    description: "Reopen a pull request that was closed without being merged",
                    params_schema: Code.object_schema({ "repo" => REPO, "number" => NUMBER, "comment" => comment }, %w[repo number]),
                    read_only: false

          pack.tool :merge_pull_request,
                    description: "Merge a pull request, only when GitHub says it can merge: no conflicts, no failing required check or " \
                                 "missing review, and up to date where its base asks for that. The merge is of the head commit read now",
                    params_schema: Code.object_schema({
                      "repo" => REPO, "number" => NUMBER,
                      "method" => { "type" => "string", "enum" => MERGE_METHODS, "description" => "merge, squash or rebase (optional, merge)" },
                      "commit_title" => { "type" => "string", "description" => "The merge or squash commit's title (optional, GitHub's)" },
                      "commit_message" => { "type" => "string", "description" => "The merge or squash commit's message (optional, GitHub's)" }
                    }, %w[repo number]),
                    read_only: false

          pack.tool :update_pull_request_branch,
                    description: "Bring a pull request's branch up to date with its base, by merging the base into it as GitHub's Update branch button does",
                    params_schema: Code.object_schema({ "repo" => REPO, "number" => NUMBER }, %w[repo number]),
                    read_only: false
        end

        def list_pull_requests(environment_row:, arguments:)
          repo = repo_argument(arguments)
          state = choice_argument(arguments, "state", STATES, default: "open")
          sort = choice_argument(arguments, "sort", SORTS)
          limit = limit_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          searched = %w[author label text].any? { |key| arguments[key].present? }
          asking("list_pull_requests", "GitHub found no repository #{repo}") do
            lines = searched ? searched_pulls(repo, state, sort, limit, arguments, token) : listed_pulls(repo, state, sort, limit, arguments, token)
            text = lines.empty? ? "No pull requests in #{repo} match." : "Pull requests in #{repo}, #{state}:\n#{lines.join("\n")}"
            linked(text, repo_page(repo, "pulls"))
          end
        end

        def pr_lookup(environment_row:, arguments:)
          repo = repo_argument(arguments)
          number = number_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          asking("pr_lookup", "GitHub has no pull request #{number} in #{repo}") do
            pull = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
            files = GithubApp.get("/repos/#{repo}/pulls/#{number}/files?per_page=#{FILE_LIMIT}", token: token)
            sections = [
              pull_heading(repo, pull),
              reviews_text(repo, number, token),
              review_comments_text(repo, number, token),
              adding("Checks", "Checks read") { Github::Checks.lines(repo, pull.dig("head", "sha"), token) },
              advisories_text(repo, pull, token),
              "Files:\n#{file_lines(files, pull['changed_files'])}",
              pull["body"].presence || "(no description)"
            ].compact
            linked(sections.join("\n\n"), pull["html_url"])
          end
        end

        def pull_request_diff(environment_row:, arguments:)
          repo = repo_argument(arguments)
          number = number_argument(arguments)
          prefix = arguments["path"].to_s.strip.delete_prefix("/")
          limit = whole_number_argument(arguments, "limit", FILES_SHOWN, MAX_FILES)
          token = GithubApp.installation_token(environment_row)
          asking("pull_request_diff", "GitHub has no pull request #{number} in #{repo}") do
            pull = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
            files = changed_files(repo, number, token).select { |file| file["filename"].to_s.start_with?(prefix) }
            shown = files.first(limit).map { |file| diff_text(file) }
            more = files.size > limit ? "\n\n#{files.size - limit} more files not shown. Ask with a path or a larger limit." : ""
            heading = "PR ##{number} #{pull['title']} in #{repo}, #{files.size} #{'file'.pluralize(files.size)}#{" under #{prefix}" if prefix.present?}:"
            linked("#{heading}\n\n#{shown.join("\n\n")}#{more}", "#{pull['html_url']}/files")
          end
        end

        def comment_on_pull_request(environment_row:, arguments:)
          repo, number, token = pull_target(arguments, environment_row)
          body = written_text(arguments, "body")
          asking("comment_on_pull_request", "GitHub has no pull request #{number} in #{repo}") do
            pull = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
            comment = GithubApp.write(:post, "/repos/#{repo}/issues/#{number}/comments", { body: body }, token: token)
            shown = comment_shown(repo, comment["id"], token)
            said = shown ? "Commented on PR ##{number} #{pull['title']} in #{repo}, and GitHub shows the comment." : "GitHub does not show a comment on PR ##{number} #{pull['title']} in #{repo}, so nothing was said there."
            linked("#{said} #{READ_BACK}", shown&.dig("html_url").presence || pull["html_url"])
          end
        end

        def reply_to_review_comment(environment_row:, arguments:)
          repo, number, token = pull_target(arguments, environment_row)
          comment_id = number_argument(arguments, "comment_id")
          body = written_text(arguments, "body")
          asking("reply_to_review_comment", "GitHub has no review comment #{comment_id} on pull request #{number} in #{repo}") do
            reply = GithubApp.write(:post, "/repos/#{repo}/pulls/#{number}/comments/#{comment_id}/replies", { body: body }, token: token)
            linked("Replied to review comment #{comment_id} on PR ##{number} in #{repo}#{" on #{reply['path']}" if reply['path']}.", reply["html_url"])
          end
        end

        def review_pull_request(environment_row:, arguments:)
          repo, number, token = pull_target(arguments, environment_row)
          event = choice_argument(arguments, "event", REVIEW_EVENTS.keys) || fail!("event must be one of #{REVIEW_EVENTS.keys.join(', ')}")
          body = written_text(arguments, "body", required: event != "approve")
          comments = review_comments_argument(arguments)
          asking("review_pull_request", "GitHub has no pull request #{number} in #{repo}") do
            pull = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
            fail! "PR ##{number} in #{repo} is #{pull['merged_at'] ? 'merged' : 'closed'}, so it takes no review." unless pull["state"] == "open"

            # commit_id pins the review to the commit read now, so lines are commented as they stood (pulls/create-review).
            review = GithubApp.write(:post, "/repos/#{repo}/pulls/#{number}/reviews",
                                     { commit_id: pull.dig("head", "sha"), event: REVIEW_EVENTS.fetch(event), body: body, comments: comments.presence }.compact,
                                     token: token)
            done = { "approve" => "Approved", "request_changes" => "Requested changes on", "comment" => "Reviewed with comments" }.fetch(event)
            linked("#{done} PR ##{number} #{pull['title']} in #{repo} at #{pull.dig('head', 'sha').to_s[0, 12]}" \
                   "#{", with #{comments.size} line #{'comment'.pluralize(comments.size)}" if comments.any?}.", review["html_url"].presence || pull["html_url"])
          end
        end

        def update_pull_request(environment_row:, arguments:)
          repo, number, token = pull_target(arguments, environment_row)
          changes = { title: written_text(arguments, "title", required: false, limit: Asking::TITLE_LIMIT), body: written_text(arguments, "body", required: false),
                      base: ref_argument(arguments, "base") }.compact
          fail! "Give a title, body or base to change." if changes.empty?

          asking("update_pull_request", "GitHub has no pull request #{number} in #{repo}") do
            pull = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
            fail! "PR ##{number} in #{repo} is merged, so it cannot change." if pull["merged_at"]

            GithubApp.write(:patch, "/repos/#{repo}/pulls/#{number}", changes, token: token)
            now = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
            linked(updated_words(repo, number, changes, now), now["html_url"].presence || pull["html_url"])
          end
        end

        def request_reviewers(environment_row:, arguments:)
          repo, number, token = pull_target(arguments, environment_row)
          people = logins_argument(arguments, "reviewers")
          teams = names_argument(arguments, "team_reviewers").map { |team| team.split("/").last }
          teams.each { |team| fail! "#{team} in team_reviewers is not a team's slug" unless team.match?(Asking::TEAM) }
          fail! "Give reviewers or team_reviewers to ask." if people.empty? && teams.empty?

          asking("request_reviewers", "GitHub has no pull request #{number} in #{repo}") do
            pull = GithubApp.write(:post, "/repos/#{repo}/pulls/#{number}/requested_reviewers",
                                   { reviewers: people.presence, team_reviewers: teams.presence }.compact, token: token)
            asked = people + teams.map { |team| "the #{team} team" }
            linked("Asked #{asked.to_sentence} to review PR ##{number} #{pull['title']} in #{repo}.", pull["html_url"])
          end
        end

        def label_pull_request(environment_row:, arguments:)
          repo, number, token = pull_target(arguments, environment_row)
          asking("label_pull_request", "GitHub has no pull request #{number} in #{repo}") do
            pull = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
            said = relabel(repo, number, "PR ##{number} #{pull['title']}", arguments, token)
            linked("#{said} #{labels_shown(repo, number, token)} #{READ_BACK}", pull["html_url"])
          end
        end

        def close_pull_request(environment_row:, arguments:)
          repo, number, token = pull_target(arguments, environment_row)
          comment = written_text(arguments, "comment", required: false)
          asking("close_pull_request", "GitHub has no pull request #{number} in #{repo}") do
            pull = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
            fail! "PR ##{number} in #{repo} is already #{pull['merged_at'] ? 'merged' : 'closed'}." unless pull["state"] == "open"

            GithubApp.write(:post, "/repos/#{repo}/issues/#{number}/comments", { body: comment }, token: token) if comment
            GithubApp.write(:patch, "/repos/#{repo}/pulls/#{number}", { state: "closed" }, token: token)
            linked("Closed PR ##{number} #{pull['title']} in #{repo} without merging it#{', with a comment saying why' if comment}. " \
                   "reopen_pull_request opens it again.", pull["html_url"])
          end
        end

        def reopen_pull_request(environment_row:, arguments:)
          repo, number, token = pull_target(arguments, environment_row)
          comment = written_text(arguments, "comment", required: false)
          asking("reopen_pull_request", "GitHub has no pull request #{number} in #{repo}") do
            pull = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
            fail! "PR ##{number} in #{repo} is merged, so it cannot be reopened." if pull["merged_at"]
            fail! "PR ##{number} in #{repo} is already open." if pull["state"] == "open"

            GithubApp.write(:patch, "/repos/#{repo}/pulls/#{number}", { state: "open" }, token: token)
            GithubApp.write(:post, "/repos/#{repo}/issues/#{number}/comments", { body: comment }, token: token) if comment
            linked("Reopened PR ##{number} #{pull['title']} in #{repo}.", pull["html_url"])
          end
        end

        def merge_pull_request(environment_row:, arguments:)
          repo, number, token = pull_target(arguments, environment_row)
          method = choice_argument(arguments, "method", MERGE_METHODS, default: "merge")
          title = written_text(arguments, "commit_title", required: false, limit: Asking::TITLE_LIMIT)
          message = written_text(arguments, "commit_message", required: false)
          asking("merge_pull_request", "GitHub has no pull request #{number} in #{repo}") do
            pull = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
            mergeable!(repo, pull)
            head = pull.dig("head", "sha")
            # sha makes GitHub refuse with 409 when the head moved since it was read, so only what was checked is merged.
            merged = GithubApp.write(:put, "/repos/#{repo}/pulls/#{number}/merge",
                                     { merge_method: method, sha: head, commit_title: title, commit_message: message }.compact, token: token)
            fail! Sentence.join("GitHub did not merge PR ##{number} in #{repo}", merged["message"]) unless merged["merged"]

            linked("Merged PR ##{number} #{pull['title']} in #{repo} into #{pull.dig('base', 'ref')} by #{method}, as #{merged['sha'].to_s[0, 12]}. " \
                   "Its head was #{head.to_s[0, 12]}.", pull["html_url"])
          end
        rescue GithubApp::Error => error
          raise unless error.message.match?(/answered (405|409)/)

          fail! Sentence.join("GitHub did not merge PR ##{number} in #{repo}", error, after: "Read it again with pr_lookup to see why")
        end

        def update_pull_request_branch(environment_row:, arguments:)
          repo, number, token = pull_target(arguments, environment_row)
          asking("update_pull_request_branch", "GitHub has no pull request #{number} in #{repo}") do
            pull = GithubApp.get("/repos/#{repo}/pulls/#{number}", token: token)
            fail! "PR ##{number} in #{repo} is #{pull['merged_at'] ? 'merged' : 'closed'}, so its branch is not updated." unless pull["state"] == "open"

            # expected_head_sha makes GitHub refuse with 422 when the branch moved since it was read (pulls/update-branch).
            GithubApp.write(:put, "/repos/#{repo}/pulls/#{number}/update-branch", { expected_head_sha: pull.dig("head", "sha") }, token: token)
            linked("GitHub is merging #{pull.dig('base', 'ref')} into #{pull.dig('head', 'ref')} for PR ##{number} #{pull['title']} in #{repo}. " \
                   "It runs in the background, and pr_lookup shows the new head and its checks once it has.", pull["html_url"])
          end
        end

        # A pull request as Integrations::PullRequests reads it: its state, whether it can merge, the checks that failed on
        # its head and the reviews whose latest word from each reviewer asks for changes. GitHub works out mergeable after
        # a push, answering null meanwhile, so settle reads it again a few times.
        def pull_request_status(environment_row, repository:, number:, settle: false)
          token = GithubApp.installation_token(environment_row)
          pull = settled_pull(repository, number, token, settle)
          state = if pull["merged_at"] then Integrations::PullRequests::MERGED
          elsif pull["state"] == "open" then Integrations::PullRequests::OPEN
          else Integrations::PullRequests::CLOSED
          end
          base = pull.dig("base", "ref")
          return closed_status(pull, number, state, base) unless state == Integrations::PullRequests::OPEN

          failing, pending = failing_checks(repository, pull.dig("head", "sha"), token)
          Integrations::PullRequests::Status.new(
            number: number, url: pull["html_url"], state: state, mergeable: mergeable_of(pull), blocked: blocked_words(pull),
            head_sha: pull.dig("head", "sha"), base: base, base_sha: pull.dig("base", "sha"), failing_checks: failing, checks_pending: pending,
            reviews: changes_requested(repository, number, token)
          )
        end

        private

        # What GitHub shows after a change was asked for: each change said only when the pull request read back shows it.
        def updated_words(repo, number, changes, now)
          shown = { title: now["title"], body: now["body"], base: now.dig("base", "ref") }
          names = { title: "title", body: "description", base: "base" }
          landed, missing = changes.keys.partition { |key| same_text?(shown[key], changes[key]) }
          [ ("Changed the #{landed.map { |key| names[key] }.to_sentence} on PR ##{number} #{now['title']} in #{repo}." if landed.any?),
            ("GitHub does not show the new #{missing.map { |key| names[key] }.to_sentence}, so it is unchanged." if missing.any?),
            "GitHub now shows the title #{now['title'].to_s.inspect}, the base #{shown[:base]}, and #{description_shown(now['body'])}",
            READ_BACK ].compact.join(" ")
        end

        def description_shown(body)
          text = body.to_s.strip
          return "no description." if text.empty?

          "a description of #{text.size.to_fs(:delimited)} characters starting #{text.truncate(SHOWN_BODY).inspect}."
        end

        def labels_shown(repo, number, token)
          names = Array(GithubApp.get("/repos/#{repo}/issues/#{number}/labels", token: token)).map { |label| label["name"] }
          names.any? ? "GitHub now shows the labels #{names.to_sentence}." : "GitHub now shows no labels on it."
        rescue GithubApp::Error
          "Its labels could not be read back, so do not say what they are."
        end

        def comment_shown(repo, id, token)
          id && GithubApp.get("/repos/#{repo}/issues/comments/#{id}", token: token)
        rescue GithubApp::NotFound
          nil
        end

        # GitHub keeps text as it was sent apart from line endings and the space around it.
        def same_text?(shown, sent) = shown.to_s.gsub("\r\n", "\n").strip == sent.to_s.gsub("\r\n", "\n").strip

        def settled_pull(repository, number, token, settle)
          tries = settle ? SETTLE_TRIES : 1
          pull = nil
          tries.times do |attempt|
            sleep(SETTLE_WAIT) if attempt.positive?
            pull = GithubApp.get("/repos/#{repository}/pulls/#{number}", token: token)
            break unless pull["state"] == "open" && pull["mergeable"].nil?
          end
          pull
        end

        def closed_status(pull, number, state, base)
          Integrations::PullRequests::Status.new(number: number, url: pull["html_url"], state: state, mergeable: Integrations::PullRequests::UNKNOWN,
                                                 head_sha: pull.dig("head", "sha"), base: base)
        end

        def mergeable_of(pull)
          return Integrations::PullRequests::CONFLICTED if pull["mergeable"] == false && pull["mergeable_state"] == "dirty"
          return Integrations::PullRequests::UNKNOWN if pull["mergeable"].nil?
          return Integrations::PullRequests::MERGEABLE if pull["mergeable"] && MERGEABLE_STATES.include?(pull["mergeable_state"])

          Integrations::PullRequests::BLOCKED
        end

        def blocked_words(pull)
          return STATE_WORDS.fetch("draft") if pull["draft"]
          return if pull["mergeable"].nil? || MERGEABLE_STATES.include?(pull["mergeable_state"]) || pull["mergeable_state"] == "dirty"

          STATE_WORDS.fetch(pull["mergeable_state"].to_s, "GitHub says #{pull['mergeable_state'] || 'it cannot'}")
        end

        # Check runs and commit statuses on the head that ended failing, and whether any has not finished.
        def failing_checks(repository, sha, token)
          runs = Array(GithubApp.get("/repos/#{repository}/commits/#{sha}/check-runs?filter=latest&per_page=#{Github::Checks::RUNS_SHOWN}", token: token)["check_runs"])
          failing = runs.select { |run| Github::Checks::FAILING.include?(run["conclusion"]) }
                        .map { |run| Integrations::PullRequests::Check.new(name: run["name"], url: run["html_url"] || run["details_url"]) }
          pending = runs.any? { |run| run["status"] != "completed" }
          statuses = Array(GithubApp.get("/repos/#{repository}/commits/#{sha}/status?per_page=100", token: token)["statuses"])
          failing += statuses.select { |status| Github::Checks::STATUS_FAILING.include?(status["state"]) }
                             .map { |status| Integrations::PullRequests::Check.new(name: status["context"], url: status["target_url"]) }
          [ failing, pending || statuses.any? { |status| status["state"] == "pending" } ]
        rescue GithubApp::NotPermitted
          [ failing || [], false ]
        end

        # The latest review from each reviewer, kept when it asks for changes.
        def changes_requested(repository, number, token)
          reviews = Array(GithubApp.get("/repos/#{repository}/pulls/#{number}/reviews?per_page=100", token: token))
          latest = reviews.select { |review| %w[APPROVED CHANGES_REQUESTED DISMISSED].include?(review["state"]) }.group_by { |review| review.dig("user", "login") }
                          .transform_values(&:last)
          latest.values.select { |review| review["state"] == CHANGES_REQUESTED }.map do |review|
            Integrations::PullRequests::Review.new(id: review["id"].to_s, reviewer: review.dig("user", "login").to_s, body: review["body"].to_s)
          end
        end

        def pull_target(arguments, environment_row)
          [ repo_argument(arguments), number_argument(arguments), GithubApp.installation_token(environment_row) ]
        end

        def listed_pulls(repo, state, sort, limit, arguments, token)
          owner = repo.split("/").first
          query = { "state" => state, "base" => ref_argument(arguments, "base"), "per_page" => limit, "sort" => sort,
                    "direction" => "desc", "head" => ref_argument(arguments, "head")&.then { |branch| "#{owner}:#{branch}" } }.compact
          Array(GithubApp.get("/repos/#{repo}/pulls?#{query.to_query}", token: token)).map { |pull| listed_pull_line(pull) }
        end

        # Search takes the author, label and words the list does not, held to the one repository (docs.github.com,
        # Searching issues and pull requests).
        def searched_pulls(repo, state, sort, limit, arguments, token)
          terms = [ "repo:#{repo}", "is:pr", ("is:#{state}" unless state == "all"), ("base:#{ref_argument(arguments, 'base')}" if arguments["base"].present?),
                    ("head:#{ref_argument(arguments, 'head')}" if arguments["head"].present?),
                    login_argument(arguments, "author")&.then { |login| "author:#{login}" },
                    arguments["label"].to_s.strip.presence&.then { |label| "label:\"#{label.delete('"')}\"" }, arguments["text"].to_s.strip.presence ].compact
          query = { "q" => terms.join(" "), "per_page" => limit, "sort" => (sort if %w[created updated].include?(sort)), "order" => "desc" }.compact
          Array(GithubApp.get("/search/issues?#{query.to_query}", token: token)["items"]).map do |item|
            "  ##{item['number']} #{item['title']}  #{item['state']}#{', draft' if item['draft']}  by #{login_of(item)}  updated #{item['updated_at']}" \
              "#{"  labels #{label_names(item).join(', ')}" if label_names(item).any?}  #{item['html_url']}"
          end
        end

        def listed_pull_line(pull)
          state = pull["merged_at"] ? "merged #{pull['merged_at']}" : pull["state"]
          "  ##{pull['number']} #{pull['title']}  #{state}#{', draft' if pull['draft']}  #{pull.dig('head', 'ref')} -> #{pull.dig('base', 'ref')}  " \
            "by #{login_of(pull)}  updated #{pull['updated_at']}#{"  labels #{label_names(pull).join(', ')}" if label_names(pull).any?}  #{pull['html_url']}"
        end

        def pull_heading(repo, pull)
          head_repo = pull.dig("head", "repo", "full_name")
          state = if pull["merged_at"] then "merged at #{pull['merged_at']} by #{pull.dig('merged_by', 'login') || 'unknown'}"
          elsif pull["draft"] then "#{pull['state']}, draft"
          else pull["state"]
          end
          requested = Array(pull["requested_reviewers"]).map { |user| user["login"] } + Array(pull["requested_teams"]).map { |team| "the #{team['slug']} team" }
          [
            "PR ##{pull['number']}: #{pull['title']}",
            "State: #{state}",
            "Author: #{login_of(pull)}",
            "Branch: #{pull.dig('head', 'ref')} -> #{pull.dig('base', 'ref')}#{" from the fork #{head_repo}" if head_repo && head_repo != repo}, head #{pull.dig('head', 'sha').to_s[0, 12]}",
            ("Can merge: #{merge_words(pull, own: CodeAgentSession.opened_pull_request?(integration.workspace, repo, pull['number']))}" if pull["state"] == "open"),
            "Changes: #{pull['changed_files']} files, +#{pull['additions']} -#{pull['deletions']}",
            ("Review requested from #{requested.to_sentence}" if requested.any?),
            ("Labels: #{label_names(pull).join(', ')}" if label_names(pull).any?)
          ].compact.join("\n")
        end

        def merge_words(pull, own: false)
          return "no, #{STATE_WORDS.fetch('draft')}" if pull["draft"]
          return "not known yet, #{STATE_WORDS.fetch('unknown')}" if pull["mergeable"].nil?
          return "yes#{', though a check that is not required fails' if pull['mergeable_state'] == 'unstable'}" if pull["mergeable"] && MERGEABLE_STATES.include?(pull["mergeable_state"])
          return "no, #{OWN_CONFLICT}" if own && pull["mergeable_state"] == "dirty"

          "no, #{STATE_WORDS.fetch(pull['mergeable_state'].to_s, "GitHub says #{pull['mergeable_state'] || 'it cannot'}")}"
        end

        def mergeable!(repo, pull)
          name = "PR ##{pull['number']} in #{repo}"
          fail_policy! "#{name} is already merged." if pull["merged_at"]
          fail_policy! "#{name} is closed, so Firefight does not merge it." unless pull["state"] == "open"
          return if pull["mergeable"] == true && !pull["draft"] && MERGEABLE_STATES.include?(pull["mergeable_state"])

          fail_policy! "Firefight checked #{name} before merging and does not merge it now, because " \
                       "#{merge_words(pull).delete_prefix('no, ').delete_prefix('not known yet, ')}."
        end

        def reviews_text(repo, number, token)
          reviews = Array(GithubApp.get("/repos/#{repo}/pulls/#{number}/reviews?per_page=100", token: token))
          return "Reviews: none." if reviews.empty?

          lines = reviews.last(REVIEWS_SHOWN).map do |review|
            "  #{review.dig('user', 'login')} #{review['state'].to_s.downcase.tr('_', ' ')} at #{review['submitted_at']}#{": #{shown(review['body'], 300)}" if review['body'].present?}"
          end
          "Reviews#{" (the newest #{REVIEWS_SHOWN} of #{reviews.size})" if reviews.size > REVIEWS_SHOWN}:\n#{lines.join("\n")}"
        end

        def review_comments_text(repo, number, token)
          comments = Array(GithubApp.get("/repos/#{repo}/pulls/#{number}/comments?per_page=100&sort=created&direction=desc", token: token))
          return "Review comments: none." if comments.empty?

          lines = comments.first(COMMENTS_SHOWN).map do |comment|
            "  #{comment['id']} by #{login_of(comment)} on #{comment['path']}#{":#{comment['line']}" if comment['line']}" \
              "#{" replying to #{comment['in_reply_to_id']}" if comment['in_reply_to_id']}: #{shown(comment['body'], 400)}  #{comment['html_url']}"
          end
          "Review comments, newest first, by id#{" (#{COMMENTS_SHOWN} of the newest #{comments.size})" if comments.size > COMMENTS_SHOWN}:\n#{lines.join("\n")}"
        end

        # The advisories a Dependabot update fixes, from the repository's alerts for the packages it bumps.
        def advisories_text(repo, pull, token)
          return nil unless pull.dig("user", "login") == DEPENDABOT

          packages = ([ pull["title"].to_s[BUMPED, 1] ] + pull["body"].to_s.scan(GROUPED).flatten).compact.uniq
          return "Dependabot advisories: this update names no package Firefight can read." if packages.empty?

          adding("Dependabot advisories", "Dependabot alerts read") do
            alerts = Array(GithubApp.get("/repos/#{repo}/dependabot/alerts?#{{ 'package' => packages.join(','), 'per_page' => 20 }.to_query}", token: token))
            next "Dependabot advisories: no alert in #{repo} names #{packages.to_sentence}, so this is a version update, not a security one." if alerts.empty?

            "Dependabot advisories for #{packages.to_sentence}:\n#{alerts.map { |alert| Github::Security.dependabot_line(alert) }.join("\n")}"
          end
        end

        def changed_files(repo, number, token)
          Pages.read(max_pages: MAX_FILES / 100) do |page|
            listed = Array(GithubApp.get("/repos/#{repo}/pulls/#{number}/files?per_page=100&page=#{page || 1}", token: token))
            [ listed, (listed.size == 100 ? (page || 1) + 1 : nil) ]
          end.items
        end

        def diff_text(file)
          lines = file["patch"].to_s.lines
          patch = if lines.empty? then "(no text diff, binary or too large for GitHub to show)"
          elsif lines.size > PATCH_LINES then "#{lines.first(PATCH_LINES).join.rstrip}\n... #{lines.size - PATCH_LINES} more lines, see the page"
          else lines.join.rstrip
          end
          "#{file['filename']} (#{file['status']}, +#{file['additions']} -#{file['deletions']})\n#{patch}"
        end

        def review_comments_argument(arguments)
          given = arguments["comments"]
          return [] if given.blank?
          fail! "comments must be a list of path, line and body" unless given.is_a?(Array)

          given.map do |comment|
            fail! "each comment needs path, line and body" unless comment.is_a?(Hash)

            comment = comment.transform_keys(&:to_s)
            path = comment["path"].to_s.strip
            line = Integer(comment["line"].to_s, exception: false)
            start = comment["start_line"].presence && Integer(comment["start_line"].to_s, exception: false)
            fail! "each comment needs a path, a line as a whole number and a body" if path.empty? || !line&.positive? || comment["body"].to_s.strip.empty?
            fail! "start_line must come before line" if start && start >= line

            { path: path, line: line, side: "RIGHT", body: written_text(comment, "body"), start_line: start, start_side: ("RIGHT" if start) }.compact
          end
        end

        # Adds the labels asked for, only ones the repository has, and takes off those asked. Answers what changed.
        def relabel(repo, number, name, arguments, token)
          added = names_argument(arguments, "add")
          taken = names_argument(arguments, "remove")
          fail! "Give labels to add or remove." if added.empty? && taken.empty?

          check_labels!(repo, added, token)
          GithubApp.write(:post, "/repos/#{repo}/issues/#{number}/labels", { labels: added }, token: token) if added.any?
          # GitHub answers 404 for a label the issue does not have (issues/remove-label).
          absent = taken.select do |label|
            GithubApp.write(:delete, "/repos/#{repo}/issues/#{number}/labels/#{Http.segment(label)}", token: token)
            false
          rescue GithubApp::NotFound
            true
          end
          [ ("Added #{added.to_sentence} to #{name} in #{repo}." if added.any?),
            ("Took #{(taken - absent).to_sentence} off #{name}." if (taken - absent).any?),
            ("#{name} did not have #{absent.to_sentence}." if absent.any?) ].compact.join(" ")
        end
      end
    end
  end
end
