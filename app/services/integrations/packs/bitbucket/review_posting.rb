module Integrations
  module Packs
    class Bitbucket
      # Comments on a pull request (Bitbucket's OpenAPI description, pullrequests/{id}/comments): one in its conversation,
      # one on a line of its diff (inline, to the line in the new file), a reply (parent), an edit of a comment Firefight
      # wrote and a thread Firefight started marked resolved (comments/{id}/resolve). They are how Halon's pull request
      # review reaches Bitbucket (Integrations::PullRequestReviews), and each needs a token with write:pullrequest:bitbucket.
      # Bitbucket has no review that holds line comments, so a review is each line comment, then its summary in the
      # conversation, and a line comment always sits on the pull request as it stands.
      module ReviewPosting
        REVIEW_TOOLS = {
          PullRequestReviews::COMMENT => "comment_on_pull_request", PullRequestReviews::EDIT => "edit_pull_request_comment",
          PullRequestReviews::REVIEW => "review_pull_request", PullRequestReviews::REPLY => "reply_to_pull_request_comment",
          PullRequestReviews::RESOLVE => "resolve_pull_request_comment",
          PullRequestReviews::CHANGES => "compare_commits", PullRequestReviews::FILE => "fetch_file"
        }.freeze
        REVIEW_NEEDS = "Commenting on a pull request needs a token with the write:pullrequest:bitbucket scope.".freeze

        def self.included(pack)
          pack.extend(ClassMethods)
          repo = Bitbucket::REPO_PARAM
          number = { "type" => "integer", "description" => "The pull request's number" }
          body = { "type" => "string", "description" => "What to say, in Bitbucket's markdown" }
          comment_id = { "type" => "integer", "description" => "The comment's id" }
          pack.tool :comment_on_pull_request,
                    summary: "Adds a comment to a pull request's conversation.",
                    description: "Add a comment to a pull request's conversation",
                    params_schema: Code.object_schema({ "repo" => repo, "number" => number, "body" => body }, %w[repo number body]),
                    read_only: false

          pack.tool :edit_pull_request_comment,
                    summary: "Edits a comment Firefight posted on a pull request.",
                    description: "Change the words of a comment Firefight posted on a pull request. A comment anyone else wrote is " \
                                 "refused, and a person edits it on Bitbucket",
                    params_schema: Code.object_schema({
                      "repo" => repo, "number" => number, "comment_id" => comment_id,
                      "body" => { "type" => "string", "description" => "The comment's new words, in Bitbucket's markdown" }
                    }, %w[repo number comment_id body]),
                    read_only: false

          pack.tool :review_pull_request,
                    summary: "Comments on lines of a pull request's diff, with a summary in its conversation.",
                    description: "Review a pull request: comment on each line given, then add body as a comment in its conversation",
                    params_schema: Code.object_schema({
                      "repo" => repo, "number" => number,
                      "body" => { "type" => "string", "description" => "The review's summary, in Bitbucket's markdown" },
                      "comments" => {
                        "type" => "array", "description" => "Comments on lines of the diff (optional)",
                        "items" => { "type" => "object", "required" => %w[path line body], "properties" => {
                          "path" => { "type" => "string", "description" => "The file's path" },
                          "line" => { "type" => "integer", "description" => "The line in the file as the pull request changes it" },
                          "body" => { "type" => "string", "description" => "The comment" }
                        } }
                      }
                    }, %w[repo number body]),
                    read_only: false

          pack.tool :reply_to_pull_request_comment,
                    summary: "Replies to a comment on a pull request.",
                    description: "Reply to a comment on a pull request, in its thread",
                    params_schema: Code.object_schema({ "repo" => repo, "number" => number, "comment_id" => comment_id, "body" => body }, %w[repo number comment_id body]),
                    read_only: false

          pack.tool :resolve_pull_request_comment,
                    summary: "Marks a thread Firefight started on a pull request as resolved.",
                    description: "Mark the thread a comment Firefight posted on a pull request's code started as resolved. A thread " \
                                 "someone else started is refused, and a person resolves it on Bitbucket",
                    params_schema: Code.object_schema({ "repo" => repo, "number" => number, "comment_id" => comment_id }, %w[repo number comment_id]),
                    read_only: false
        end

        module ClassMethods
          def review_call(operation, repository:, number: nil, body: nil, reference: nil, line: false, commit: nil, comments: [], base: nil, path: nil, start: nil)
            arguments = case operation
            when PullRequestReviews::COMMENT then { "repo" => repository, "number" => number, "body" => body }
            when PullRequestReviews::EDIT then { "repo" => repository, "number" => number, "comment_id" => reference.to_i, "body" => body }
            when PullRequestReviews::REVIEW
              { "repo" => repository, "number" => number, "body" => body,
                "comments" => comments.map { |comment| { "path" => comment.path, "line" => comment.line, "body" => comment.body } }.presence }.compact
            when PullRequestReviews::REPLY then { "repo" => repository, "number" => number, "comment_id" => reference.to_i, "body" => body }
            when PullRequestReviews::RESOLVE then { "repo" => repository, "number" => number, "comment_id" => reference.to_i }
            when PullRequestReviews::CHANGES then { "repo" => repository, "base" => base, "head" => commit }
            when PullRequestReviews::FILE then { "repo" => repository, "path" => path, "ref" => commit, "start_line" => start }.compact
            end
            [ REVIEW_TOOLS.fetch(operation), arguments ]
          end

          def review_posted(operation, facts)
            case operation
            when PullRequestReviews::REVIEW
              PullRequestReviews::Posted.new(reference: facts["comment_id"]&.to_s, comments: Array(facts["comment_ids"]).map { |id| id&.to_s })
            else facts["comment_id"]&.to_s
            end
          end

          # A reply on Bitbucket names the comment it answers as its parent.
          def review_thread_of(reference) = reference
        end

        # Who Firefight is on Bitbucket: the account the connection's token acts as. A workspace access token has no account
        # Bitbucket answers for, so Firefight is then known only by its name in a comment.
        def review_identity(environment_row)
          user = api(environment_row).get("/user")
          PullRequestReviews::Identity.new(handles: [ user["nickname"], user["username"] ], ids: [ user["account_id"], user["uuid"] ])
        rescue BitbucketApi::Error
          PullRequestReviews::Identity.new
        end

        def comment_on_pull_request(environment_row:, arguments:)
          repo, number, bitbucket = comment_target(arguments, environment_row)
          comment = posting("comment on PR ##{number} in #{repo}") do
            bitbucket.post(comments_path(repo, number), { "content" => { "raw" => comment_text(arguments, "body") } })
          end
          Telemetry.result("Commented on PR ##{number} in #{repo} as comment #{comment['id']}.", link: link(comment.dig("links", "html", "href")),
                           facts: { "comment_id" => comment["id"] })
        end

        def edit_pull_request_comment(environment_row:, arguments:)
          repo, number, bitbucket = comment_target(arguments, environment_row)
          id = comment_number(arguments, "comment_id")
          path = "#{comments_path(repo, number)}/#{id}"
          own_comment!(bitbucket, bitbucket.get(path), id)
          edited = posting("edit comment #{id} on PR ##{number} in #{repo}") { bitbucket.put(path, { "content" => { "raw" => comment_text(arguments, "body") } }) }
          Telemetry.result("Edited comment #{id} on PR ##{number} in #{repo}.", link: link(edited.dig("links", "html", "href")), facts: { "comment_id" => id })
        end

        def review_pull_request(environment_row:, arguments:)
          repo, number, bitbucket = comment_target(arguments, environment_row)
          body = comment_text(arguments, "body")
          lines = inline_comments(arguments)
          pull = bitbucket.get("#{BitbucketApi.repository(repo)}/pullrequests/#{number}")
          fail! "PR ##{number} in #{repo} is #{pull['state'].to_s.downcase}, so it takes no review." unless pull["state"] == "OPEN"

          # A line Bitbucket will not place is left without a comment rather than stopping the rest, and the caller places it. A
          # refusal for the token's access says the same for every line, so it stops the review with why.
          ids = lines.map do |comment|
            posting("comment on #{comment[:path]} line #{comment[:line]} of PR ##{number} in #{repo}") do
              bitbucket.post(comments_path(repo, number), { "content" => { "raw" => comment[:body] }, "inline" => { "path" => comment[:path], "to" => comment[:line] } })["id"]
            rescue BitbucketApi::NotFound, BitbucketApi::Refused
              raise
            rescue BitbucketApi::Error
              nil
            end
          end
          summary = posting("comment on PR ##{number} in #{repo}") { bitbucket.post(comments_path(repo, number), { "content" => { "raw" => body } }) }
          missed = ids.count(&:nil?)
          Telemetry.result("Reviewed PR ##{number} #{pull['title']} in #{repo}#{", with #{ids.size - missed} line #{'comment'.pluralize(ids.size - missed)}" if ids.any?}" \
                           "#{", and #{missed} Bitbucket would not place on its line" if missed.positive?}.",
                           link: link(summary.dig("links", "html", "href") || pull.dig("links", "html", "href")),
                           facts: { "comment_id" => summary["id"], "comment_ids" => ids.presence })
        end

        def reply_to_pull_request_comment(environment_row:, arguments:)
          repo, number, bitbucket = comment_target(arguments, environment_row)
          parent = comment_number(arguments, "comment_id")
          reply = posting("reply to comment #{parent} on PR ##{number} in #{repo}") do
            bitbucket.post(comments_path(repo, number), { "content" => { "raw" => comment_text(arguments, "body") }, "parent" => { "id" => parent } })
          end
          Telemetry.result("Replied to comment #{parent} on PR ##{number} in #{repo} as comment #{reply['id']}.", link: link(reply.dig("links", "html", "href")),
                           facts: { "comment_id" => reply["id"] })
        end

        def resolve_pull_request_comment(environment_row:, arguments:)
          repo, number, bitbucket = comment_target(arguments, environment_row)
          id = comment_number(arguments, "comment_id")
          path = "#{comments_path(repo, number)}/#{id}"
          comment = bitbucket.get(path)
          own_comment!(bitbucket, comment, id, what: "thread")
          posting("resolve the thread of comment #{id} on PR ##{number} in #{repo}") { bitbucket.post("#{path}/resolve") } if comment["resolution"].blank?
          Telemetry.result("Resolved the thread comment #{id} started on PR ##{number} in #{repo}.", link: link(comment.dig("links", "html", "href")),
                           facts: { "comment_id" => id })
        end

        private

        def comments_path(repo, number) = "#{BitbucketApi.repository(repo)}/pullrequests/#{number}/comments"

        def comment_target(arguments, environment_row) = [ repo_argument(arguments), comment_number(arguments, "number"), api(environment_row) ]

        def comment_number(arguments, key)
          id = Integer(arguments[key].to_s, exception: false)
          fail! "#{key} must be a whole number" unless id&.positive?

          id
        end

        def comment_text(arguments, key)
          text = arguments[key].to_s.strip
          fail! "#{key} is required" if text.empty?

          text
        end

        def inline_comments(arguments)
          given = arguments["comments"]
          return [] if given.blank?
          fail! "comments must be a list of path, line and body" unless given.is_a?(Array)

          given.map do |comment|
            comment = comment.to_h.transform_keys(&:to_s)
            line = Integer(comment["line"].to_s, exception: false)
            fail! "each comment needs a path, a line as a whole number and a body" if comment["path"].to_s.strip.empty? || !line&.positive? || comment["body"].to_s.strip.empty?

            { path: comment["path"].to_s.strip, line: line, body: comment["body"].to_s.strip }
          end
        end

        def own_comment!(bitbucket, comment, id, what: "comment")
          me = bitbucket.get("/user")
          author = comment["user"].to_h
          return if %w[account_id uuid].any? { |key| author[key].present? && author[key] == me[key] }

          fail_policy! "Only a #{what} Firefight started is changed here, and #{what} #{id} is #{comment.dig('user', 'display_name').presence || 'someone else'}'s. A person changes it on Bitbucket."
        rescue BitbucketApi::Refused
          fail_policy! "Bitbucket does not say who this token acts as, so Firefight cannot tell #{what} #{id} is its own and leaves it as it is."
        end

        def posting(what)
          yield
        rescue BitbucketApi::Refused => error
          fail! Sentence.join("Bitbucket refused to #{what}", error, after: REVIEW_NEEDS)
        end
      end
    end
  end
end
