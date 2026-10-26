module Integrations
  module Packs
    class Gitlab
      # Comments on a merge request (doc/api/notes.md and discussions.md): a note in its conversation, a thread on a line
      # of its diff, a reply in a thread, an edit of a note Firefight wrote and a thread Firefight started marked resolved.
      # They are how Halon's pull request review reaches GitLab (Integrations::PullRequestReviews), and like every change
      # they need a token with the api scope. A thread on a line is placed by the merge request version whose head is the
      # commit reviewed (GET merge_requests/:iid/versions), so its lines stand as they were read. GitLab names a thread by
      # its discussion and each note in it by its own id, so what Firefight keeps of a thread is both, as discussion/note.
      module ReviewPosting
        REVIEW_TOOLS = {
          PullRequestReviews::COMMENT => "comment_on_merge_request", PullRequestReviews::EDIT => "edit_merge_request_comment",
          PullRequestReviews::REVIEW => "review_merge_request", PullRequestReviews::REPLY => "reply_to_merge_request_thread",
          PullRequestReviews::RESOLVE => "resolve_merge_request_thread",
          PullRequestReviews::CHANGES => "compare_commits", PullRequestReviews::FILE => "fetch_file"
        }.freeze
        REVIEW_NEEDS = "Commenting on a merge request needs a token with the api scope and at least the Reporter role in the project, and resolving a thread the Developer role.".freeze

        def self.included(pack)
          pack.extend(ClassMethods)
          repo = Gitlab::REPO_PARAM
          iid = { "type" => "integer", "description" => "The merge request's number in the project, as in !42" }
          body = { "type" => "string", "description" => "What to say, in GitLab's markdown" }
          discussion = { "type" => "string", "description" => "The thread's discussion id" }
          pack.tool :comment_on_merge_request,
                    summary: "Adds a comment to a merge request's conversation.",
                    description: "Add a comment to a merge request's conversation",
                    params_schema: Code.object_schema({ "repo" => repo, "iid" => iid, "body" => body }, %w[repo iid body]),
                    read_only: false

          pack.tool :edit_merge_request_comment,
                    summary: "Edits a comment Firefight posted on a merge request.",
                    description: "Change the words of a comment Firefight posted on a merge request, in its conversation or in a thread. " \
                                 "A comment anyone else wrote is refused, and a person edits it on GitLab",
                    params_schema: Code.object_schema({
                      "repo" => repo, "iid" => iid, "note_id" => { "type" => "integer", "description" => "The comment's id" },
                      "body" => { "type" => "string", "description" => "The comment's new words, in GitLab's markdown" }
                    }, %w[repo iid note_id body]),
                    read_only: false

          pack.tool :review_merge_request,
                    summary: "Comments on lines of a merge request's diff, with a summary in its conversation.",
                    description: "Review a merge request: start a thread on each line given, on the merge request as it stood at commit, " \
                                 "then add body as a comment in its conversation",
                    params_schema: Code.object_schema({
                      "repo" => repo, "iid" => iid,
                      "body" => { "type" => "string", "description" => "The review's summary, in GitLab's markdown" },
                      "commit" => { "type" => "string", "description" => "The commit the review is of, one of the merge request's own (optional, its head now)" },
                      "comments" => {
                        "type" => "array", "description" => "Comments on lines of the diff (optional)",
                        "items" => { "type" => "object", "required" => %w[path line body], "properties" => {
                          "path" => { "type" => "string", "description" => "The file's path" },
                          "line" => { "type" => "integer", "description" => "The line in the file as the merge request changes it" },
                          "body" => { "type" => "string", "description" => "The comment" }
                        } }
                      }
                    }, %w[repo iid body]),
                    read_only: false

          pack.tool :reply_to_merge_request_thread,
                    summary: "Replies in a thread on a merge request.",
                    description: "Reply in a thread on a merge request, by its discussion id",
                    params_schema: Code.object_schema({ "repo" => repo, "iid" => iid, "discussion_id" => discussion, "body" => body }, %w[repo iid discussion_id body]),
                    read_only: false

          pack.tool :resolve_merge_request_thread,
                    summary: "Marks a thread Firefight started on a merge request as resolved.",
                    description: "Mark a thread Firefight started on a merge request as resolved, by its discussion id. A thread someone " \
                                 "else started is refused, and a person resolves it on GitLab",
                    params_schema: Code.object_schema({ "repo" => repo, "iid" => iid, "discussion_id" => discussion }, %w[repo iid discussion_id]),
                    read_only: false
        end

        module ClassMethods
          def review_call(operation, repository:, number: nil, body: nil, reference: nil, line: false, commit: nil, comments: [], base: nil, path: nil, start: nil)
            discussion, note = reference.to_s.split("/", 2)
            arguments = case operation
            when PullRequestReviews::COMMENT then { "repo" => repository, "iid" => number, "body" => body }
            when PullRequestReviews::EDIT then { "repo" => repository, "iid" => number, "note_id" => (line ? note : discussion).to_i, "body" => body }
            when PullRequestReviews::REVIEW
              { "repo" => repository, "iid" => number, "body" => body, "commit" => commit,
                "comments" => comments.map { |comment| { "path" => comment.path, "line" => comment.line, "body" => comment.body } }.presence }.compact
            when PullRequestReviews::REPLY then { "repo" => repository, "iid" => number, "discussion_id" => discussion, "body" => body }
            when PullRequestReviews::RESOLVE then { "repo" => repository, "iid" => number, "discussion_id" => discussion }
            when PullRequestReviews::CHANGES then { "repo" => repository, "base" => base, "head" => commit }
            when PullRequestReviews::FILE then { "repo" => repository, "path" => path, "ref" => commit, "start_line" => start }.compact
            end
            [ REVIEW_TOOLS.fetch(operation), arguments ]
          end

          def review_posted(operation, facts)
            case operation
            when PullRequestReviews::REVIEW
              PullRequestReviews::Posted.new(reference: facts["note_id"]&.to_s, comments: Array(facts["threads"]).map { |thread| thread&.to_s })
            else facts["note_id"]&.to_s
            end
          end

          # A thread on GitLab is its discussion, which a reply names.
          def review_thread_of(reference) = reference.to_s.split("/", 2).first
        end

        # Who Firefight is on GitLab: the user the connection's token acts as, a bot for a group or project access token.
        def review_identity(environment_row)
          user = api(environment_row).get("/user")
          PullRequestReviews::Identity.new(handles: [ user["username"] ], ids: [ user["id"]&.to_s ])
        end

        def comment_on_merge_request(environment_row:, arguments:)
          repo, iid, gitlab = merge_request_target(arguments, environment_row)
          body = posted_text(arguments, "body")
          request = gitlab.get("#{GitlabApi.project(repo)}/merge_requests/#{iid}")
          note = posting("comment on merge request !#{iid} in #{repo}") { gitlab.post("#{GitlabApi.project(repo)}/merge_requests/#{iid}/notes", { "body" => body }) }
          Telemetry.result("Commented on merge request !#{iid} #{request['title']} in #{repo} as note #{note['id']}.", link: link(note_url(request, note["id"])),
                           facts: { "note_id" => note["id"] })
        end

        def edit_merge_request_comment(environment_row:, arguments:)
          repo, iid, gitlab = merge_request_target(arguments, environment_row)
          id = posted_id(arguments, "note_id")
          body = posted_text(arguments, "body")
          path = "#{GitlabApi.project(repo)}/merge_requests/#{iid}/notes/#{id}"
          own_note!(gitlab, gitlab.get(path), id)
          posting("edit note #{id} on merge request !#{iid} in #{repo}") { gitlab.put(path, { "body" => body }) }
          request = gitlab.get("#{GitlabApi.project(repo)}/merge_requests/#{iid}")
          Telemetry.result("Edited note #{id} on merge request !#{iid} in #{repo}.", link: link(note_url(request, id)), facts: { "note_id" => id })
        end

        def review_merge_request(environment_row:, arguments:)
          repo, iid, gitlab = merge_request_target(arguments, environment_row)
          body = posted_text(arguments, "body")
          comments = line_comments(arguments)
          project = GitlabApi.project(repo)
          request = gitlab.get("#{project}/merge_requests/#{iid}")
          fail! "Merge request !#{iid} in #{repo} is #{request['state']}, so it takes no review." unless request["state"] == "opened"

          refs = version_refs(gitlab, project, iid, arguments["commit"].to_s.strip.presence, request)
          threads = comments.map do |comment|
            position = { "position_type" => "text", "base_sha" => refs["base_commit_sha"], "start_sha" => refs["start_commit_sha"], "head_sha" => refs["head_commit_sha"],
                         "new_path" => comment[:path], "old_path" => comment[:path], "new_line" => comment[:line] }
            # A line GitLab will not place is left without a thread rather than stopping the rest, and the caller places it. A
            # refusal for the token's access says the same for every line, so it stops the review with why.
            made = posting("comment on #{comment[:path]} line #{comment[:line]} of merge request !#{iid} in #{repo}") do
              gitlab.post("#{project}/merge_requests/#{iid}/discussions", { "body" => comment[:body], "position" => position })
            rescue GitlabApi::NotFound, GitlabApi::Refused
              raise
            rescue GitlabApi::Error
              nil
            end
            "#{made['id']}/#{Array(made['notes']).first&.dig('id')}" if made
          end
          note = posting("comment on merge request !#{iid} in #{repo}") { gitlab.post("#{project}/merge_requests/#{iid}/notes", { "body" => body }) }
          missed = threads.count(&:nil?)
          Telemetry.result("Reviewed merge request !#{iid} #{request['title']} in #{repo} at #{refs['head_commit_sha'].to_s[0, 12]}" \
                           "#{", with #{threads.size - missed} line #{'comment'.pluralize(threads.size - missed)}" if threads.any?}" \
                           "#{", and #{missed} GitLab would not place on its line" if missed.positive?}.",
                           link: link(note_url(request, note["id"])), facts: { "note_id" => note["id"], "threads" => threads.presence })
        end

        def reply_to_merge_request_thread(environment_row:, arguments:)
          repo, iid, gitlab = merge_request_target(arguments, environment_row)
          discussion = discussion_argument(arguments)
          body = posted_text(arguments, "body")
          note = posting("reply in thread #{discussion} on merge request !#{iid} in #{repo}") do
            gitlab.post("#{GitlabApi.project(repo)}/merge_requests/#{iid}/discussions/#{discussion}/notes", { "body" => body })
          end
          request = gitlab.get("#{GitlabApi.project(repo)}/merge_requests/#{iid}")
          Telemetry.result("Replied in thread #{discussion} on merge request !#{iid} in #{repo} as note #{note['id']}.", link: link(note_url(request, note["id"])),
                           facts: { "note_id" => "#{discussion}/#{note['id']}" })
        end

        def resolve_merge_request_thread(environment_row:, arguments:)
          repo, iid, gitlab = merge_request_target(arguments, environment_row)
          discussion = discussion_argument(arguments)
          path = "#{GitlabApi.project(repo)}/merge_requests/#{iid}/discussions/#{discussion}"
          thread = gitlab.get(path)
          first = Array(thread["notes"]).first.to_h
          own_note!(gitlab, first, discussion, what: "thread")
          posting("resolve thread #{discussion} on merge request !#{iid} in #{repo}") { gitlab.put(path, { "resolved" => true }) } unless first["resolved"]
          request = gitlab.get("#{GitlabApi.project(repo)}/merge_requests/#{iid}")
          Telemetry.result("Resolved thread #{discussion} on merge request !#{iid} in #{repo}.", link: link(note_url(request, first["id"])),
                           facts: { "note_id" => "#{discussion}/#{first['id']}" })
        end

        private

        def merge_request_target(arguments, environment_row)
          iid = Integer(arguments["iid"].to_s, exception: false)
          fail! "iid must be the merge request's number" unless iid&.positive?

          [ repo_argument(arguments), iid, api(environment_row) ]
        end

        def posted_text(arguments, key)
          text = arguments[key].to_s.strip
          fail! "#{key} is required" if text.empty?

          text
        end

        def posted_id(arguments, key)
          id = Integer(arguments[key].to_s, exception: false)
          fail! "#{key} must be a whole number" unless id&.positive?

          id
        end

        def discussion_argument(arguments)
          id = arguments["discussion_id"].to_s.strip
          fail! "discussion_id must be a thread's discussion id" unless id.match?(/\A[0-9a-f]{8,64}\z/i)

          id
        end

        def line_comments(arguments)
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

        # The base, start and head of the version whose head is the commit asked, or of the merge request as it stands.
        def version_refs(gitlab, project, iid, commit, request)
          return request["diff_refs"].to_h.transform_keys { |key| key.sub("_sha", "_commit_sha") } if commit.nil? && request["diff_refs"].present?

          versions, = gitlab.list("#{project}/merge_requests/#{iid}/versions")
          found = commit ? versions.find { |version| version["head_commit_sha"].to_s.start_with?(commit) } : versions.first
          fail! "Merge request !#{iid} has no version at #{commit}, so its lines cannot be placed." unless found

          found
        end

        def own_note!(gitlab, note, id, what: "comment")
          me = gitlab.get("/user")
          return if note.dig("author", "id").present? && note.dig("author", "id") == me["id"]

          fail_policy! "Only a #{what} Firefight started is changed here, and #{what} #{id} is #{note.dig('author', 'username').presence || 'someone else'}'s. A person changes it on GitLab."
        end

        def note_url(request, note_id) = request["web_url"].present? && note_id ? "#{request['web_url']}#note_#{note_id}" : request["web_url"]

        def posting(what)
          yield
        rescue GitlabApi::Refused => error
          fail! Sentence.join("GitLab refused to #{what}", error, after: REVIEW_NEEDS)
        end
      end
    end
  end
end
