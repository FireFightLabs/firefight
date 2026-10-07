module Integrations
  module Packs
    class Github
      # A repository's issues through the REST API's issues paths (github/rest-api-description, docs.github.com REST API,
      # Issues), which need the App's Issues permission. GitHub lists pull requests among issues and marks each with
      # pull_request, so the issue tools leave them out and send a pull request to the pull request tools, whose
      # permission is Pull requests. Every change is read_only false, so it goes through the gateway like any other.
      module RepositoryIssues
        STATES = %w[open closed all].freeze
        CLOSE_REASONS = %w[completed not_planned duplicate].freeze
        COMMENTS_SHOWN = 20
        REPO = Code::REPO
        NUMBER = { "type" => "integer", "description" => "The issue's number" }.freeze
        NAMES = { "type" => "array", "items" => { "type" => "string" } }.freeze

        def self.included(pack)
          pack.tool :list_issues,
                    description: "List a repository's issues, newest first, filtered by state, labels, assignee, author or words in them. " \
                                 "Pull requests are left out, list_pull_requests lists them",
                    params_schema: Code.object_schema({
                      "repo" => REPO,
                      "state" => { "type" => "string", "enum" => STATES, "description" => "open, closed or all (optional, open)" },
                      "labels" => NAMES.merge("description" => "Only issues with every one of these labels (optional)"),
                      "assignee" => { "type" => "string", "description" => "Only issues assigned to this GitHub login (optional)" },
                      "author" => { "type" => "string", "description" => "Only issues opened by this GitHub login (optional)" },
                      "text" => { "type" => "string", "description" => "Only issues whose title or description has these words (optional)" },
                      "since" => { "type" => "string", "description" => "Only issues updated at or after this time, as ISO 8601 (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many (optional, #{Asking::LIST_LIMIT}, at most #{Asking::MAX_LIST})" }
                    }, %w[repo]),
                    read_only: true

          pack.tool :issue_lookup,
                    description: "Fetch an issue with its description, labels, assignees and its newest comments",
                    params_schema: Code.object_schema({ "repo" => REPO, "number" => NUMBER }, %w[repo number]),
                    read_only: true

          pack.tool :create_issue,
                    description: "Open an issue in a repository, with labels it already has and assignees if given",
                    params_schema: Code.object_schema({
                      "repo" => REPO,
                      "title" => { "type" => "string", "description" => "The issue's title" },
                      "body" => { "type" => "string", "description" => "What the issue says, in GitHub's markdown (optional)" },
                      "labels" => NAMES.merge("description" => "Labels the repository has (optional)"),
                      "assignees" => NAMES.merge("description" => "GitHub logins to assign (optional)")
                    }, %w[repo title]),
                    read_only: false

          pack.tool :comment_on_issue,
                    description: "Add a comment to an issue",
                    params_schema: Code.object_schema({ "repo" => REPO, "number" => NUMBER, "body" => { "type" => "string", "description" => "What to say, in GitHub's markdown" } },
                                                      %w[repo number body]),
                    read_only: false

          pack.tool :update_issue,
                    description: "Change an issue's title or description",
                    params_schema: Code.object_schema({
                      "repo" => REPO, "number" => NUMBER,
                      "title" => { "type" => "string", "description" => "The new title (optional)" },
                      "body" => { "type" => "string", "description" => "The new description, replacing the old one (optional)" }
                    }, %w[repo number]),
                    read_only: false

          pack.tool :label_issue,
                    description: "Add labels to an issue or take them off. Only labels the repository already has are added",
                    params_schema: Code.object_schema({
                      "repo" => REPO, "number" => NUMBER,
                      "add" => NAMES.merge("description" => "Labels to add (optional)"), "remove" => NAMES.merge("description" => "Labels to take off (optional)")
                    }, %w[repo number]),
                    read_only: false

          pack.tool :assign_issue,
                    description: "Assign people to an issue or take them off it",
                    params_schema: Code.object_schema({
                      "repo" => REPO, "number" => NUMBER,
                      "add" => NAMES.merge("description" => "GitHub logins to assign (optional)"), "remove" => NAMES.merge("description" => "GitHub logins to take off (optional)")
                    }, %w[repo number]),
                    read_only: false

          comment = { "type" => "string", "description" => "A comment saying why, posted with it (optional)" }
          pack.tool :close_issue,
                    description: "Close an issue as completed, not planned or a duplicate, with a comment saying why if given. It can be reopened",
                    params_schema: Code.object_schema({
                      "repo" => REPO, "number" => NUMBER,
                      "reason" => { "type" => "string", "enum" => CLOSE_REASONS, "description" => "completed, not_planned or duplicate (optional, completed)" },
                      "comment" => comment
                    }, %w[repo number]),
                    read_only: false

          pack.tool :reopen_issue,
                    description: "Reopen a closed issue",
                    params_schema: Code.object_schema({ "repo" => REPO, "number" => NUMBER, "comment" => comment }, %w[repo number]),
                    read_only: false
        end

        def list_issues(environment_row:, arguments:)
          repo = repo_argument(arguments)
          state = choice_argument(arguments, "state", STATES, default: "open")
          limit = limit_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          asking("list_issues", "GitHub found no repository #{repo}, or its issues are turned off") do
            issues = arguments["text"].present? ? searched_issues(repo, state, limit, arguments, token) : listed_issues(repo, state, limit, arguments, token)
            text = issues.empty? ? "No issues in #{repo} match." : "Issues in #{repo}, #{state}:\n#{issues.map { |issue| issue_line(issue) }.join("\n")}"
            linked(text, repo_page(repo, "issues"))
          end
        end

        def issue_lookup(environment_row:, arguments:)
          repo, number, token = issue_target(arguments, environment_row)
          asking("issue_lookup", "GitHub has no issue #{number} in #{repo}") do
            issue = GithubApp.get("/repos/#{repo}/issues/#{number}", token: token)
            comments = issue["comments"].to_i.positive? ? newest_comments(repo, number, issue["comments"].to_i, token) : []
            lines = [
              "Issue ##{issue['number']}: #{issue['title']}",
              ("This is a pull request, and pr_lookup reads its reviews and checks." if issue["pull_request"]),
              "State: #{issue['state']}#{" as #{issue['state_reason'].tr('_', ' ')}" if issue['state'] == 'closed' && issue['state_reason']}" \
                "#{" at #{issue['closed_at']} by #{issue.dig('closed_by', 'login')}" if issue['closed_at']}",
              "Opened by #{login_of(issue)} at #{issue['created_at']}, updated #{issue['updated_at']}",
              ("Labels: #{label_names(issue).join(', ')}" if label_names(issue).any?),
              ("Assignees: #{Array(issue['assignees']).map { |user| user['login'] }.join(', ')}" if Array(issue["assignees"]).any?),
              "",
              issue["body"].presence || "(no description)",
              ("\nComments#{", the newest #{comments.size} of #{issue['comments']}" if issue['comments'].to_i > comments.size}:\n#{comments.join("\n")}" if comments.any?)
            ].compact
            linked(lines.join("\n"), issue["html_url"])
          end
        end

        def create_issue(environment_row:, arguments:)
          repo = repo_argument(arguments)
          title = written_text(arguments, "title", limit: Asking::TITLE_LIMIT)
          body = written_text(arguments, "body", required: false)
          labels = names_argument(arguments, "labels")
          assignees = logins_argument(arguments, "assignees")
          token = GithubApp.installation_token(environment_row)
          asking("create_issue", "GitHub found no repository #{repo}, or its issues are turned off") do
            check_labels!(repo, labels, token)
            issue = GithubApp.write(:post, "/repos/#{repo}/issues", { title: title, body: body, labels: labels.presence, assignees: assignees.presence }.compact, token: token)
            linked("Opened issue ##{issue['number']} #{issue['title']} in #{repo}.", issue["html_url"])
          end
        end

        def comment_on_issue(environment_row:, arguments:)
          repo, number, token = issue_target(arguments, environment_row)
          body = written_text(arguments, "body")
          asking("comment_on_issue", "GitHub has no issue #{number} in #{repo}") do
            issue = only_issue!(repo, number, token)
            comment = GithubApp.write(:post, "/repos/#{repo}/issues/#{number}/comments", { body: body }, token: token)
            linked("Commented on issue ##{number} #{issue['title']} in #{repo}.", comment["html_url"].presence || issue["html_url"])
          end
        end

        def update_issue(environment_row:, arguments:)
          repo, number, token = issue_target(arguments, environment_row)
          changes = { title: written_text(arguments, "title", required: false, limit: Asking::TITLE_LIMIT), body: written_text(arguments, "body", required: false) }.compact
          fail! "Give a title or body to change." if changes.empty?

          asking("update_issue", "GitHub has no issue #{number} in #{repo}") do
            only_issue!(repo, number, token)
            issue = GithubApp.write(:patch, "/repos/#{repo}/issues/#{number}", changes, token: token)
            linked("Changed #{changes.keys.map { |key| key == :title ? 'its title' : 'its description' }.to_sentence} on issue ##{number} #{issue['title']} in #{repo}.", issue["html_url"])
          end
        end

        def label_issue(environment_row:, arguments:)
          repo, number, token = issue_target(arguments, environment_row)
          asking("label_issue", "GitHub has no issue #{number} in #{repo}") do
            issue = only_issue!(repo, number, token)
            linked(relabel(repo, number, "issue ##{number} #{issue['title']}", arguments, token), issue["html_url"])
          end
        end

        def assign_issue(environment_row:, arguments:)
          repo, number, token = issue_target(arguments, environment_row)
          added = logins_argument(arguments, "add")
          taken = logins_argument(arguments, "remove")
          fail! "Give logins to assign or take off." if added.empty? && taken.empty?

          asking("assign_issue", "GitHub has no issue #{number} in #{repo}") do
            issue = only_issue!(repo, number, token)
            # GitHub leaves out a login it cannot assign rather than refusing it (issues/add-assignees), so what it kept is read back.
            after = added.any? ? GithubApp.write(:post, "/repos/#{repo}/issues/#{number}/assignees", { assignees: added }, token: token) : issue
            after = GithubApp.write(:delete, "/repos/#{repo}/issues/#{number}/assignees", { assignees: taken }, token: token) if taken.any?
            now = Array(after["assignees"]).map { |user| user["login"] }
            dropped = added.reject { |login| now.any? { |kept| kept.casecmp?(login) } }
            words = [ ("Assigned #{(added - dropped).to_sentence}." if (added - dropped).any?), ("Took #{taken.to_sentence} off it." if taken.any?),
                      ("GitHub did not assign #{dropped.to_sentence}, who cannot be assigned in #{repo}." if dropped.any?),
                      "Issue ##{number} #{issue['title']} is now assigned to #{now.any? ? now.to_sentence : 'nobody'}." ].compact
            linked(words.join(" "), issue["html_url"])
          end
        end

        def close_issue(environment_row:, arguments:)
          repo, number, token = issue_target(arguments, environment_row)
          reason = choice_argument(arguments, "reason", CLOSE_REASONS, default: "completed")
          comment = written_text(arguments, "comment", required: false)
          asking("close_issue", "GitHub has no issue #{number} in #{repo}") do
            issue = only_issue!(repo, number, token)
            fail! "Issue ##{number} in #{repo} is already closed." if issue["state"] == "closed"

            GithubApp.write(:post, "/repos/#{repo}/issues/#{number}/comments", { body: comment }, token: token) if comment
            GithubApp.write(:patch, "/repos/#{repo}/issues/#{number}", { state: "closed", state_reason: reason }, token: token)
            linked("Closed issue ##{number} #{issue['title']} in #{repo} as #{reason.tr('_', ' ')}#{', with a comment saying why' if comment}. reopen_issue opens it again.",
                   issue["html_url"])
          end
        end

        def reopen_issue(environment_row:, arguments:)
          repo, number, token = issue_target(arguments, environment_row)
          comment = written_text(arguments, "comment", required: false)
          asking("reopen_issue", "GitHub has no issue #{number} in #{repo}") do
            issue = only_issue!(repo, number, token)
            fail! "Issue ##{number} in #{repo} is already open." if issue["state"] == "open"

            GithubApp.write(:patch, "/repos/#{repo}/issues/#{number}", { state: "open", state_reason: "reopened" }, token: token)
            GithubApp.write(:post, "/repos/#{repo}/issues/#{number}/comments", { body: comment }, token: token) if comment
            linked("Reopened issue ##{number} #{issue['title']} in #{repo}.", issue["html_url"])
          end
        end

        private

        def issue_target(arguments, environment_row)
          [ repo_argument(arguments), number_argument(arguments), GithubApp.installation_token(environment_row) ]
        end

        # The issue, refused when it is a pull request, whose changes go through the pull request tools and their permission.
        def only_issue!(repo, number, token)
          issue = GithubApp.get("/repos/#{repo}/issues/#{number}", token: token)
          fail! "##{number} in #{repo} is a pull request, so the pull request tools change it, such as comment_on_pull_request or close_pull_request." if issue["pull_request"]

          issue
        end

        def listed_issues(repo, state, limit, arguments, token)
          query = { "state" => state, "labels" => names_argument(arguments, "labels").join(",").presence, "assignee" => login_argument(arguments, "assignee"),
                    "creator" => login_argument(arguments, "author"), "since" => since_argument(arguments)&.iso8601, "sort" => "updated", "direction" => "desc",
                    "per_page" => Asking::MAX_LIST }.compact
          Array(GithubApp.get("/repos/#{repo}/issues?#{query.to_query}", token: token)).reject { |issue| issue["pull_request"] }.first(limit)
        end

        def searched_issues(repo, state, limit, arguments, token)
          terms = [ "repo:#{repo}", "is:issue", ("is:#{state}" unless state == "all"),
                    *names_argument(arguments, "labels").map { |label| "label:\"#{label.delete('"')}\"" },
                    login_argument(arguments, "assignee")&.then { |login| "assignee:#{login}" }, login_argument(arguments, "author")&.then { |login| "author:#{login}" },
                    since_argument(arguments)&.then { |since| "updated:>=#{since.utc.iso8601}" }, arguments["text"].to_s.strip ].compact
          Array(GithubApp.get("/search/issues?#{{ 'q' => terms.join(' '), 'sort' => 'updated', 'order' => 'desc', 'per_page' => limit }.to_query}", token: token)["items"])
        end

        def issue_line(issue)
          assignees = Array(issue["assignees"]).map { |user| user["login"] }
          "  ##{issue['number']} #{issue['title']}  #{issue['state']}  by #{login_of(issue)}  updated #{issue['updated_at']}" \
            "#{"  labels #{label_names(issue).join(', ')}" if label_names(issue).any?}#{"  assigned #{assignees.join(', ')}" if assignees.any?}  #{issue['html_url']}"
        end

        # GitHub lists comments oldest first and has no other order (issues/list-comments), so the last page holds the newest.
        def newest_comments(repo, number, total, token)
          last_page = (total.to_f / 100).ceil
          comments = Array(GithubApp.get("/repos/#{repo}/issues/#{number}/comments?per_page=100&page=#{last_page}", token: token))
          comments.last(COMMENTS_SHOWN).map { |comment| "  #{login_of(comment)} at #{comment['created_at']}: #{shown(comment['body'], 800)}  #{comment['html_url']}" }
        end
      end
    end
  end
end
