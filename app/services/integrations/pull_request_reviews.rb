module Integrations
  # The write side of the review host contract, and what a code host says about the pull requests Halon reviews, in one
  # shape whichever host that is. A code host's event source answers review_signals(payload, headers:) with Signals, from
  # the deliveries its webhook already sends. Its pack answers review_identity(environment_row) with who Firefight is on
  # that host and review_visibility(environment_row, repository:) with whether a repository is public, and on its class
  # side REVIEW_TOOLS, REVIEW_ATOMIC (whether one review call posts every line comment or none), review_markup (what its
  # markdown renders), review_call(operation, **) and review_posted(operation, facts), so the app posts through the
  # connection's own tools, each authorized by the gateway and in the activity log like any other call. Nothing here
  # names a host.
  module PullRequestReviews
    # What a delivery says happened to a pull request.
    REQUESTED = "requested".freeze
    OPENED = "opened".freeze
    PUSHED = "pushed".freeze
    MERGED = "merged".freeze
    CLOSED = "closed".freeze
    COMMENTED = "commented".freeze
    KINDS = [ REQUESTED, OPENED, PUSHED, MERGED, CLOSED, COMMENTED ].freeze

    # What Firefight does on a host. A comment in the conversation, an edit of one Firefight wrote (a line comment when
    # line is true), one review with its line comments, a reply in a thread and a thread marked resolved.
    COMMENT = :comment
    EDIT = :edit
    REVIEW = :review
    REPLY = :reply
    RESOLVE = :resolve
    # What Firefight reads to check a fix or answer a reply: what a push changed, and a file at a commit.
    CHANGES = :changes
    FILE = :file
    READS = [ CHANGES, FILE ].freeze
    OPERATIONS = [ COMMENT, EDIT, REVIEW, REPLY, RESOLVE, *READS ].freeze

    # How a person asks for a review in a comment: Firefight's handle, or Halon's or Firefight's name, then review.
    ASK = "review".freeze
    NAMES = %w[firefight halon].freeze

    # Whether a repository anyone can read holds the pull request. Unknown is read as public.
    VISIBILITY_PUBLIC = "public".freeze
    VISIBILITY_PRIVATE = "private".freeze
    VISIBILITY_KEPT = 10.minutes

    # A host's answer that a comment cannot sit on the line given, as a line the diff does not show gets.
    UNPLACEABLE = [ 400, 422 ].freeze

    # One thing a delivery said. reviewers is who was asked to review it, by every name the host gives them, for
    # REQUESTED. author is who did it and person false for a bot. For COMMENTED, comment is the host's id of the new
    # comment, thread the id of the thread it answers (nil for a comment in the conversation) and body what it says.
    # reference names the delivery's news, the same however often it is sent.
    Signal = Data.define(:kind, :repository, :number, :reference, :head_sha, :author, :person, :reviewers, :comment, :thread, :body, :draft) do
      def initialize(head_sha: nil, author: nil, person: true, reviewers: [], comment: nil, thread: nil, body: nil, draft: false, **) = super

      def reply? = kind == COMMENTED && thread.present?
    end

    # Who Firefight is on one connection: every handle a person could @-mention or pick as a reviewer, and the host's
    # own ids for it. pickable is false where the host does not let a person pick Firefight as a reviewer, such as an app's
    # bot, so asking there is a comment.
    Identity = Data.define(:handles, :ids, :pickable) do
      def initialize(handles: [], ids: [], pickable: true, **) = super(handles: handles.compact_blank.map(&:to_s), ids: ids.compact_blank.map(&:to_s), pickable: pickable)

      def named?(names) = Array(names).compact_blank.map(&:to_s).any? { |name| matches?(name) }

      def matches?(name)
        bare = name.to_s.delete_prefix("@")
        handles.any? { |handle| handle.casecmp?(bare) } || ids.include?(name.to_s)
      end

      # A comment that @-mentions Firefight, by its handle on the host or by name, and asks it to review.
      def asks?(text)
        named = (handles + NAMES).uniq.map { |handle| Regexp.escape(handle.delete_suffix("[bot]")) }.join("|")
        text.to_s.match?(/(?:\A|[\s(])@(?:#{named})(?:\[bot\])?\b[^\n]*\b#{ASK}\b/i)
      end
    end

    # A line comment as a review posts it.
    LineComment = Data.define(:path, :line, :body)

    # A line comment a review posted, read back: the host's reference to it, its page and its words.
    PostedComment = Data.define(:reference, :url, :body)

    # What a review posted: the host's reference to the review and its page, and one reference and page per line comment in
    # the order given, nil for a line the host would not place.
    # unread is true when the line comments went up but the host would not say which is which, so none can be followed.
    Posted = Data.define(:reference, :comments, :urls, :url, :unread) do
      def initialize(urls: [], url: nil, unread: false, **) = super
    end

    class Refused < Integrations::Error; end

    module_function

    def source_of(provider_key) = MapEvents.source_of(provider_key)

    def pack_of(integration) = NativePack.for(integration.provider)

    # A code host whose pack can post a review and whose event source says when one is asked for.
    def hosts?(integration)
      pack = pack_of(integration)
      pack.present? && pack.respond_to?(:review_call) && source_of(integration.provider).respond_to?(:review_signals)
    end

    # The tools Firefight reviews through on a connection of this provider, which its review agent is granted.
    def tools(provider_key)
      pack = Provider.for(provider_key).pack
      pack.respond_to?(:review_call) ? pack::REVIEW_TOOLS.values.uniq : []
    end

    # The providers a review can be asked for on, by name, for a workspace that has connected none yet.
    def provider_names
      IntegrationProvider.all.select { |entry| Provider.for(entry.key).pack.respond_to?(:review_call) && source_of(entry.key).respond_to?(:review_signals) }.map(&:name)
    end

    # The workspace's code host connections Halon reviews through, each with what a person writes in a comment to ask it,
    # the handle they pick as a reviewer where the host allows one, and the connection's id.
    def host_names(workspace)
      workspace.integrations.active.includes(:integration_environments).select { |integration| integration.holds_code? && hosts?(integration) }.map do |integration|
        row = integration.integration_environments.select(&:enabled).min_by(&:created_at)
        found = begin
          identity(row) if row
        rescue Integrations::Error
          nil
        end
        handle = found&.handles&.last
        { id: integration.id, name: integration.display_name, ask: "@#{handle || NAMES.first} #{ASK}", reviewer: (handle if found&.pickable) }
      end
    end

    # Whether a repository is public, read once in a while. A host that cannot say, or a read that fails, counts as public,
    # since posting less is the safe side.
    def public?(environment_row, repository)
      visibility = Rails.cache.fetch([ "pull_request_reviews.visibility", environment_row.id, repository.to_s.downcase ], expires_in: VISIBILITY_KEPT) do
        NativePack.fetch!(environment_row.integration).review_visibility(environment_row, repository: repository) || VISIBILITY_PUBLIC
      end
      visibility != VISIBILITY_PRIVATE
    rescue StandardError => error
      Rails.logger.warn({ event: "pull_request_reviews.visibility_unread", integration_environment_id: environment_row.id, error: error.class.name }.to_json)
      true
    end

    # The line comments a review posted, read back from the host, or nil when the read failed or the host cannot read
    # them back. A host whose review is several calls always says each comment's id as it posts, so only a host that posts
    # a review whole answers this.
    def posted_comments(environment_row, repository:, number:, review:)
      pack = NativePack.fetch!(environment_row.integration)
      return unless pack.respond_to?(:review_comments_of)

      pack.review_comments_of(environment_row, repository: repository, number: number, review: review)
    rescue Integrations::Error => error
      Rails.logger.warn({ event: "pull_request_reviews.comments_unread", integration_environment_id: environment_row.id, error: error.class.name }.to_json)
      nil
    end

    # Whether one review call posts every line comment or none, so a refusal leaves nothing behind.
    def atomic?(integration) = pack_of(integration)::REVIEW_ATOMIC == true

    # What the host's markdown renders: a collapsed block and an HTML comment kept out of sight.
    def markup(integration) = pack_of(integration).review_markup

    # What a delivery to a connection says about pull requests, through its provider's event source, or none.
    def signals(provider_key, payload, headers:)
      source = source_of(provider_key)
      return [] unless source.respond_to?(:review_signals)

      Array(source.review_signals(payload, headers: headers))
    rescue StandardError => error
      Rails.logger.warn({ event: "pull_request_reviews.signals_unread", provider: provider_key, error: error.class.name }.to_json)
      []
    end

    # Who Firefight is on a connection, read once a day.
    def identity(environment_row)
      Rails.cache.fetch([ "pull_request_reviews.identity", environment_row.id ], expires_in: 1.day) do
        NativePack.fetch!(environment_row.integration).review_identity(environment_row)
      end
    end

    # Whether a signal asks Firefight itself to review: it was picked as a reviewer, or a comment asks it.
    def asked?(environment_row, signal)
      case signal.kind
      when REQUESTED then identity(environment_row).named?(signal.reviewers)
      when COMMENTED then !signal.reply? && signal.person && identity(environment_row).asks?(signal.body)
      else false
      end
    end

    # Whether Firefight itself wrote what a signal is about, so it never answers its own words.
    def own?(environment_row, signal) = identity(environment_row).named?([ signal.author ])

    # Whether a thread a reply names is one of the comments in a finding's thread, the first Firefight posted or one said
    # on it since.
    def same_thread?(integration, references, thread)
      thread.present? && Array(references).compact_blank.any? { |reference| pack_of(integration).review_thread_of(reference.to_s) == thread.to_s }
    end

    # The tool and its arguments for one operation, and the call made through it. authorize runs the call through the
    # gateway as whoever acts, with the tool and its arguments, and yields to run it. A read answers what the tool said,
    # a post what it posted, and with_link the page it links to beside it.
    def call!(environment_row, operation, authorize:, with_link: false, **given)
      raise ArgumentError, "unknown operation #{operation}" unless OPERATIONS.include?(operation)

      integration = environment_row.integration
      pack = pack_of(integration)
      name, arguments = pack.review_call(operation, **given)
      tool = integration.tools.available.find_by(name: name)
      raise Refused, "#{integration.display_name}'s #{name} is not available, so Halon cannot review there." unless tool
      raise Refused, "#{integration.display_name}'s #{name} is switched off under Integrations, so Halon cannot review there." unless tool.enabled?

      result = authorize.call(tool, arguments) { NativeExecutor.call(tool: tool, environment_row: environment_row, arguments: arguments) }
      raise Refused, Sentence.ended(answer_text(result).presence || "#{name} failed") if result.is_a?(Hash) && result["isError"]

      return answer_text(result.is_a?(Hash) ? result : { "content" => [ { "text" => result.to_s } ] }) if READS.include?(operation)

      posted = pack.review_posted(operation, result.to_h.dig(Telemetry::STRUCTURED, Telemetry::FACTS).to_h)
      posted = posted.with(url: link_of(result)) if posted.is_a?(Posted)
      with_link ? [ posted, link_of(result) ] : posted
    end

    # The page a tool's answer links to, as Telemetry.result wrote it.
    def link_of(result)
      line = Array(result.to_h["content"]).map { |part| part["text"].to_s }.find { |text| Telemetry.link_line?(text) }
      line&.split(": ")&.last&.strip.presence
    end

    # The host said a comment cannot sit on the line given, which leaves that one line comment out. Any other failure,
    # such as a rate limit or the host being down, stops the review so it is retried.
    def unplaceable?(error) = UNPLACEABLE.include?(error.try(:http_status))

    def answer_text(result) = Array(result.to_h["content"]).filter_map { |part| part["text"] }.join("\n").strip
    private_class_method :answer_text
  end
end
