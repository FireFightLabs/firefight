module Integrations
  module Packs
    class Github
      # What reviewers left open on a pull request, read for a code change that adds to it, and the answer posted on each
      # thread after the push. Only GitHub's GraphQL API says whether a review thread is resolved (PullRequestReviewThread
      # isResolved), and its comments carry fullDatabaseId, the REST id a reply goes to, since databaseId no longer fits
      # newer ids. A thread whose newest comment is Firefight's own was answered already and waits on the reviewer, and
      # a review whose words Firefight answered names its id in a comment Firefight left (ANSWERED_MARK).
      module OpenReviewComments
        THREADS = 100
        THREAD_COMMENTS = 50
        REVIEWS = 100
        COMMENTS = 100
        QUERY = <<~GRAPHQL.freeze
          query($owner: String!, $name: String!, $number: Int!) {
            repository(owner: $owner, name: $name) {
              pullRequest(number: $number) {
                reviewThreads(first: #{THREADS}) {
                  pageInfo { hasNextPage }
                  nodes {
                    isResolved path line originalLine
                    comments(first: #{THREAD_COMMENTS}) { nodes { fullDatabaseId body url viewerDidAuthor author { __typename login } } }
                  }
                }
                reviews(last: #{REVIEWS}) {
                  nodes { fullDatabaseId body state url viewerDidAuthor author { __typename login } }
                }
                comments(last: #{COMMENTS}) { nodes { body viewerDidAuthor } }
              }
            }
          }
        GRAPHQL
        # A review in these states is not one a reviewer stands by (GraphQL PullRequestReviewState).
        PASSED_OVER = %w[PENDING DISMISSED].freeze
        PERSON = "User".freeze
        # Left, hidden, in the comment Firefight posts after an update, naming the reviews whose words it answered.
        ANSWERED_MARK = "halon-answered-reviews".freeze
        ANSWERED = /<!-- #{ANSWERED_MARK}: ([\d ]+) -->/

        Read = Data.define(:comments, :more)

        module_function

        # The open comments, threads first in GitHub's order, then the reviews' own words oldest first.
        def read(repo, number, token:)
          owner, name = repo.split("/", 2)
          pull = GithubApp.graphql(QUERY, { owner: owner, name: name, number: number.to_i }, token: token).dig("repository", "pullRequest").to_h
          threads = pull.dig("reviewThreads", "nodes").to_a.filter_map { |thread| open_thread(thread) }
          answered = pull.dig("comments", "nodes").to_a.select { |comment| comment["viewerDidAuthor"] }
                         .flat_map { |comment| comment["body"].to_s.scan(ANSWERED).flatten.flat_map(&:split) }.map(&:to_i).to_set
          reviews = pull.dig("reviews", "nodes").to_a.filter_map { |review| open_review(review, answered) }
          Read.new(comments: threads + reviews, more: pull.dig("reviewThreads", "pageInfo", "hasNextPage") == true)
        end

        # The hidden line the update's comment carries for the reviews it answered.
        def answered_mark(comments)
          ids = comments.reject(&:thread?).map(&:id)
          "<!-- #{ANSWERED_MARK}: #{ids.join(' ')} -->" if ids.any?
        end

        def reply(repo, number, comment_id, body, token:)
          GithubApp.write(:post, "/repos/#{repo}/pulls/#{number}/comments/#{comment_id}/replies", { body: body }, token: token)
        end

        def open_thread(thread)
          comments = thread.dig("comments", "nodes").to_a
          first = comments.first
          return if thread["isResolved"] || first.nil? || comments.last["viewerDidAuthor"]

          replies = comments.drop(1).map { |reply| ReviewComments::Reply.new(author: login(reply), person: person?(reply), body: reply["body"].to_s) }
          ReviewComments::Comment.new(id: first["fullDatabaseId"].to_i, kind: ReviewComments::THREAD, author: login(first), person: person?(first), body: first["body"].to_s,
                                      path: thread["path"], line: thread["line"] || thread["originalLine"], url: first["url"], replies: replies)
        end

        def open_review(review, answered)
          id = review["fullDatabaseId"].to_i
          return if review["viewerDidAuthor"] || review["body"].to_s.strip.empty? || PASSED_OVER.include?(review["state"]) || answered.include?(id)

          ReviewComments::Comment.new(id: id, kind: ReviewComments::REVIEW, author: login(review), person: person?(review), body: review["body"].to_s, url: review["url"])
        end

        def login(node) = node.dig("author", "login")

        def person?(node) = node.dig("author", "__typename") == PERSON

        private_class_method :open_thread, :open_review, :login, :person?
      end
    end
  end
end
