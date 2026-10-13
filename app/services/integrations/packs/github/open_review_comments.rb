module Integrations
  module Packs
    class Github
      # What reviewers left open on a pull request, read for a code change that adds to it, and the answer posted on each
      # thread after the push. Only GitHub's GraphQL API says whether a review thread is resolved (PullRequestReviewThread
      # isResolved), and its comments carry fullDatabaseId, the REST id a reply goes to, since databaseId no longer fits
      # newer ids. A thread whose newest comment is Firefight's own was answered already and waits on the reviewer, and
      # a review whose words Firefight answered names its id in a comment Firefight left (ANSWERED_MARK). Every page of
      # threads, of a thread's comments, of reviews and of comments is read, since a comment on a page left unread is
      # one the change never answers. A pull request with more than MAX_PAGES pages of any is refused rather than read
      # in part.
      module OpenReviewComments
        PAGE = 100
        MAX_PAGES = 20
        AUTHOR = "author { __typename login }".freeze
        COMMENT = "fullDatabaseId body url viewerDidAuthor #{AUTHOR}".freeze
        PAGE_INFO = "pageInfo { hasNextPage endCursor }".freeze
        PULL = "query($owner: String!, $name: String!, $number: Int!, $after: String) { repository(owner: $owner, name: $name) { pullRequest(number: $number) { %s } } }".freeze
        THREADS_QUERY = format(PULL, "reviewThreads(first: #{PAGE}, after: $after) { #{PAGE_INFO} nodes { id isResolved path line originalLine " \
                                     "comments(first: #{PAGE}) { #{PAGE_INFO} nodes { #{COMMENT} } } } }").freeze
        THREAD_COMMENTS_QUERY = "query($id: ID!, $after: String) { node(id: $id) { ... on PullRequestReviewThread { " \
                                "comments(first: #{PAGE}, after: $after) { #{PAGE_INFO} nodes { #{COMMENT} } } } } }".freeze
        REVIEWS_QUERY = format(PULL, "reviews(first: #{PAGE}, after: $after) { #{PAGE_INFO} nodes { fullDatabaseId body state url viewerDidAuthor #{AUTHOR} } }").freeze
        COMMENTS_QUERY = format(PULL, "comments(first: #{PAGE}, after: $after) { #{PAGE_INFO} nodes { body viewerDidAuthor } }").freeze
        # A review in these states is not one a reviewer stands by (GraphQL PullRequestReviewState).
        PASSED_OVER = %w[PENDING DISMISSED].freeze
        PERSON = "User".freeze
        # Left, hidden, in the comment Firefight posts after an update, naming the reviews whose words it answered.
        ANSWERED_MARK = "halon-answered-reviews".freeze
        ANSWERED = /<!-- #{ANSWERED_MARK}: ([\d ]+) -->/

        # More pages than Firefight reads, said as GitHub's own refusals are, so the fix stops the same way.
        class TooMany < GithubApp::Error; end

        module_function

        # The open comments, threads first in GitHub's order, then the reviews' own words oldest first.
        def read(repo, number, token:)
          owner, name = repo.split("/", 2)
          pull = { owner: owner, name: name, number: number.to_i }
          threads = pages(THREADS_QUERY, pull, %w[repository pullRequest reviewThreads], "review threads", token).filter_map do |thread|
            open_thread(thread, token)
          end
          answered = pages(COMMENTS_QUERY, pull, %w[repository pullRequest comments], "comments", token).select { |comment| comment["viewerDidAuthor"] }
                       .flat_map { |comment| comment["body"].to_s.scan(ANSWERED).flatten.flat_map(&:split) }.map(&:to_i).to_set
          reviews = pages(REVIEWS_QUERY, pull, %w[repository pullRequest reviews], "reviews", token).filter_map { |review| open_review(review, answered) }
          threads + reviews
        end

        # The hidden line the update's comment carries for the reviews it answered.
        def answered_mark(comments)
          ids = comments.reject(&:thread?).map(&:id)
          "<!-- #{ANSWERED_MARK}: #{ids.join(' ')} -->" if ids.any?
        end

        def reply(repo, number, comment_id, body, token:)
          GithubApp.write(:post, "/repos/#{repo}/pulls/#{number}/comments/#{comment_id}/replies", { body: body }, token: token)
        end

        # Every node of a connection, page after page from its first, or the rest of one whose first page is given.
        def pages(query, variables, path, what, token, first: nil)
          connection = first
          connection ||= GithubApp.graphql(query, variables.merge(after: nil), token: token).dig(*path).to_h
          nodes = connection["nodes"].to_a
          MAX_PAGES.times do
            info = connection["pageInfo"].to_h
            return nodes unless info["hasNextPage"]

            connection = GithubApp.graphql(query, variables.merge(after: info["endCursor"]), token: token).dig(*path).to_h
            nodes += connection["nodes"].to_a
          end
          raise TooMany, "it has more than #{MAX_PAGES * PAGE} #{what}, more than Firefight reads."
        end

        def open_thread(thread, token)
          return if thread["isResolved"]

          comments = pages(THREAD_COMMENTS_QUERY, { id: thread["id"] }, %w[node comments], "comments in one review thread", token, first: thread["comments"].to_h)
          first = comments.first
          return if first.nil? || comments.last["viewerDidAuthor"]

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

        private_class_method :pages, :open_thread, :open_review, :login, :person?
      end
    end
  end
end
