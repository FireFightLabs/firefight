module Integrations
  module Packs
    class Github
      # How Halon's pull request review reaches GitHub (Integrations::PullRequestReviews): a comment in the conversation,
      # one review with its line comments, a reply in a thread, an edit of a comment Firefight wrote and a thread it
      # opened marked resolved. Each is one of the pack's own tools, so a grant, an approval rule and the activity log
      # see it like any other call. Editing goes through PATCH issues/comments/{id} or pulls/comments/{id}, and resolving
      # through GraphQL's resolveReviewThread, since only GraphQL knows a thread (PullRequestReviewThread). Both refuse a
      # comment or a thread someone else started, which a person changes on GitHub.
      module ReviewPosting
        REVIEW_TOOLS = {
          PullRequestReviews::COMMENT => "comment_on_pull_request", PullRequestReviews::EDIT => "edit_pull_request_comment",
          PullRequestReviews::REVIEW => "review_pull_request", PullRequestReviews::REPLY => "reply_to_review_comment",
          PullRequestReviews::RESOLVE => "resolve_review_thread",
          PullRequestReviews::CHANGES => "compare_commits", PullRequestReviews::FILE => "fetch_file"
        }.freeze
        THREAD_PAGE = 100
        THREAD_PAGES = 20
        THREADS_QUERY = "query($owner: String!, $name: String!, $number: Int!, $after: String) { repository(owner: $owner, name: $name) { " \
                        "pullRequest(number: $number) { reviewThreads(first: #{THREAD_PAGE}, after: $after) { pageInfo { hasNextPage endCursor } " \
                        "nodes { id isResolved comments(first: 1) { nodes { fullDatabaseId viewerDidAuthor } } } } } } }".freeze
        RESOLVE_MUTATION = "mutation($id: ID!) { resolveReviewThread(input: { threadId: $id }) { thread { id isResolved } } }".freeze

        def self.included(pack)
          pack.extend(ClassMethods)
          number = { "type" => "integer", "description" => "The pull request's number" }
          pack.tool :edit_pull_request_comment,
                    summary: "Edits a comment Firefight posted on a pull request.",
                    description: "Change the words of a comment Firefight posted on a pull request, in its conversation as " \
                                 "comment_on_pull_request said it or on its code as review_pull_request or reply_to_review_comment " \
                                 "said it. A comment anyone else wrote is refused, and a person edits it on GitHub",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO,
                      "comment_id" => { "type" => "integer", "description" => "The comment's id" },
                      "body" => { "type" => "string", "description" => "The comment's new words, in GitHub's markdown" },
                      "review" => { "type" => "boolean", "description" => "Whether it is a review comment on the code (optional, a comment in the conversation)" }
                    }, %w[repo comment_id body]),
                    read_only: false

          pack.tool :resolve_review_thread,
                    summary: "Marks a review thread Firefight started on a pull request as resolved.",
                    description: "Mark the review thread a comment Firefight posted on a pull request's code started as resolved, " \
                                 "by that comment's id. A thread someone else started is refused, and a person resolves it on GitHub",
                    params_schema: Code.object_schema({
                      "repo" => Code::REPO, "number" => number,
                      "comment_id" => { "type" => "integer", "description" => "The id of the comment that started the thread" }
                    }, %w[repo number comment_id]),
                    read_only: false
        end

        module ClassMethods
          # The tool and its arguments for one operation of the review host contract.
          def review_call(operation, repository:, number: nil, body: nil, reference: nil, line: false, commit: nil, comments: [], base: nil, path: nil, start: nil)
            arguments = case operation
            when PullRequestReviews::COMMENT then { "repo" => repository, "number" => number, "body" => body }
            when PullRequestReviews::EDIT then { "repo" => repository, "comment_id" => reference.to_i, "body" => body, "review" => line }
            when PullRequestReviews::REVIEW
              { "repo" => repository, "number" => number, "event" => "comment", "body" => body, "commit" => commit,
                "comments" => comments.map { |comment| { "path" => comment.path, "line" => comment.line, "body" => comment.body } }.presence }.compact
            when PullRequestReviews::REPLY then { "repo" => repository, "number" => number, "comment_id" => reference.to_i, "body" => body }
            when PullRequestReviews::RESOLVE then { "repo" => repository, "number" => number, "comment_id" => reference.to_i }
            when PullRequestReviews::CHANGES then { "repo" => repository, "base" => base, "head" => commit }
            when PullRequestReviews::FILE then { "repo" => repository, "path" => path, "ref" => commit, "start_line" => start }.compact
            end
            [ REVIEW_TOOLS.fetch(operation), arguments ]
          end

          # What a call's facts say it posted: the comment's id, or for a review its id and each line comment's.
          def review_posted(operation, facts)
            case operation
            when PullRequestReviews::REVIEW
              PullRequestReviews::Posted.new(reference: facts["review_id"]&.to_s, comments: Array(facts["comment_ids"]).map { |id| id&.to_s },
                                             urls: Array(facts["comment_urls"]))
            else facts["comment_id"]&.to_s
            end
          end

          # A reply on GitHub names the comment that started its thread (in_reply_to_id), which is the reference kept.
          def review_thread_of(reference) = reference
        end

        # Who Firefight is on GitHub: its App's bot, which a person @-mentions by the App's slug. GitHub's reviewers box
        # offers people and teams, never an App, so a review is asked for in a comment, though a review request the API
        # makes of the bot still counts.
        def review_identity(_environment_row)
          login = GithubApp.bot_login
          PullRequestReviews::Identity.new(handles: [ login, login&.delete_suffix("[bot]") ], pickable: false)
        end

        def edit_pull_request_comment(environment_row:, arguments:)
          repo = repo_argument(arguments)
          id = number_argument(arguments, "comment_id")
          body = written_text(arguments, "body")
          review = boolean_argument(arguments, "review")
          path = review ? "/repos/#{repo}/pulls/comments/#{id}" : "/repos/#{repo}/issues/comments/#{id}"
          token = GithubApp.installation_token(environment_row)
          asking("edit_pull_request_comment", "GitHub has no comment #{id} in #{repo}") do
            own_comment!(GithubApp.get(path, token: token), id, "edited")
            edited = GithubApp.write(:patch, path, { body: body }, token: token)
            linked("Edited comment #{id} in #{repo}.", edited["html_url"], facts: { "comment_id" => edited["id"] || id })
          end
        end

        def resolve_review_thread(environment_row:, arguments:)
          repo, number, token = pull_target(arguments, environment_row)
          id = number_argument(arguments, "comment_id")
          asking("resolve_review_thread", "GitHub has no pull request #{number} in #{repo}") do
            thread = thread_started_by(repo, number, id, token)
            fail! "No review thread on PR ##{number} in #{repo} starts with comment #{id}." unless thread
            fail_policy! "Only a thread Firefight started is resolved here, and comment #{id} is someone else's. A person resolves it on GitHub." unless thread.dig("comments", "nodes", 0, "viewerDidAuthor")

            unless thread["isResolved"]
              resolved = GithubApp.graphql(RESOLVE_MUTATION, { id: thread["id"] }, token: token).dig("resolveReviewThread", "thread").to_h
              fail! "GitHub did not mark the thread resolved." unless resolved["isResolved"]
            end
            linked("Resolved the review thread comment #{id} started on PR ##{number} in #{repo}.", "https://github.com/#{repo}/pull/#{number}", facts: { "comment_id" => id })
          end
        end

        private

        def own_comment!(comment, id, done)
          author = comment.dig("user", "login").to_s
          own = GithubApp.bot_login
          return if own.present? && author.casecmp?(own)

          fail_policy! "Only a comment Firefight posted is #{done} here, and comment #{id} is #{author.presence || 'someone else'}'s. A person changes it on GitHub."
        end

        # The review thread whose first comment is this one, read page by page.
        def thread_started_by(repo, number, id, token)
          owner, name = repo.split("/", 2)
          after = nil
          THREAD_PAGES.times do
            threads = GithubApp.graphql(THREADS_QUERY, { owner: owner, name: name, number: number, after: after }, token: token)
                               .dig("repository", "pullRequest", "reviewThreads").to_h
            found = Array(threads["nodes"]).find { |thread| thread.dig("comments", "nodes", 0, "fullDatabaseId").to_i == id }
            return found if found

            info = threads["pageInfo"].to_h
            return nil unless info["hasNextPage"]

            after = info["endCursor"]
          end
          nil
        end
      end
    end
  end
end
