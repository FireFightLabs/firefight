module Integrations
  module IssueTrackers
    # Linear's save_issue opens an issue when it is called without an id and changes one when it is given one. It
    # answers the issue as JSON with its key (id), title, url and statusType, one of Linear's workflow state types
    # (backlog, unstarted, started, completed, canceled, and triage for a team that triages), as Linear's hosted server
    # answers it. A change that leaves the issue completed or canceled closes it.
    #
    # Keeping an item in step uses the same server: save_issue to open and change an issue, list_issue_statuses for the
    # team's states (a state is chosen by its type, Linear's documented workflow state kinds), list_users to find the
    # person whose email matches, and get_issue to read one. Linear publishes no schema for these tools, so a parameter
    # is used by the name the connected tool reports when it reports one.
    #
    # Changes come back by Linear's webhook (https://linear.app/developers/webhooks): a POST of the data change event
    # (action create, update or remove, type Issue, data the issue, updatedFrom the previous values of what changed,
    # webhookTimestamp in milliseconds), signed in the Linear-Signature header as the hex HMAC-SHA256 of the raw body with
    # the webhook's signing secret. Linear's SDK (packages/sdk/src/webhooks/client.ts) refuses a delivery whose signed
    # webhookTimestamp is more than a minute from now, and so does this. The issue's fields are IssueWebhookPayload in the
    # SDK's schema.graphql: identifier, previousIdentifiers, title, url, updatedAt, archivedAt, trashed, state (with its
    # type) and assignee (with its email).
    class Linear < RemoteReader
      include Issues::Calls

      NAME = "Linear".freeze
      SAVE_ISSUE = "save_issue".freeze
      GET_ISSUE = "get_issue".freeze
      LIST_STATUSES = "list_issue_statuses".freeze
      LIST_USERS = "list_users".freeze
      CREATE_TOOL = SAVE_ISSUE
      CLOSED_TYPES = %w[completed canceled].freeze

      TEAM = "team".freeze
      TARGET_FIELDS = [
        Issues::TargetField.new(key: TEAM, label: "Team", placeholder: "ENG", required: true,
                                hint: "The key or name of the Linear team new issues are filed in.")
      ].freeze

      # Linear's workflow state types for each of Firefight's states, the first one a team has being used.
      STATE_TYPES = {
        Issues::STATE_OPEN => %w[unstarted backlog triage],
        Issues::STATE_STARTED => %w[started],
        Issues::STATE_DONE => %w[completed]
      }.freeze

      SIGNATURE_HEADER = "Linear-Signature".freeze
      FRESH_FOR = 60.seconds
      ISSUE_TYPE = "Issue".freeze
      ACTION_UPDATE = "update".freeze
      ACTION_REMOVE = "remove".freeze
      # updatedFrom names each changed field by its column.
      CHANGED_FIELDS = { "title" => Issues::FIELD_TITLE, "stateId" => Issues::FIELD_STATE, "assigneeId" => Issues::FIELD_ASSIGNEE }.freeze

      def report(tool_name:, arguments:, result:)
        return unless tool_name == SAVE_ISSUE

        issue = Capabilities::Answers.data(result)
        return unless issue.is_a?(Hash) && issue["url"].to_s.match?(%r{\Ahttps://\S+\z})

        change = if arguments["id"].blank? then Issues::OPENED
        elsif CLOSED_TYPES.include?(issue["statusType"]) then Issues::CLOSED
        end
        return unless change

        Issues::Report.new(change: change, key: issue["id"].presence, title: issue["title"].to_s.strip.presence, url: issue["url"])
      end

      def create(title:, description:, target:, assignee_email: nil)
        team = target.to_h[TEAM].to_s.strip
        raise Issues::Failed, "Choose the Linear team new issues are filed in under Settings, Workspace." if team.empty?

        notes = []
        arguments = { "title" => title, TEAM => team, "description" => description }
        assign(arguments, assignee_email, notes)
        issue = issue_of(data!(run!(SAVE_ISSUE, arguments, "open the issue"), "the new issue"))
        raise Issues::Failed, "Linear opened the issue but did not say where it is." unless issue

        Issues::Outcome.new(issue: issue, notes: notes)
      end

      def update(key:, target:, title: nil, state: nil, assignee_email: nil)
        notes = []
        arguments = { "id" => key }
        arguments["title"] = title if title
        assign(arguments, assignee_email, notes) if assignee_email
        if state
          found = state_id(target, state)
          found ? arguments[parameter("state", "stateId")] = found : notes << "#{key}'s team has no #{state_words(state)} state, so its status was left alone."
        end
        return Issues::Outcome.new(notes: notes) if arguments.size == 1

        result = call(SAVE_ISSUE, arguments, "change #{key}")
        return Issues::Outcome.new(notes: notes, gone: true) if missing?(result)

        answered!(SAVE_ISSUE, result, "change #{key}")
        Issues::Outcome.new(issue: issue_of(Capabilities::Answers.data(result)), notes: notes)
      end

      def read(key, target: nil)
        result = call(GET_ISSUE, { "id" => key }, "read #{key}")
        return if missing?(result)

        issue_of(data!(answered!(GET_ISSUE, result, "read #{key}"), key))
      end

      def self.setup_steps
        [
          "In Linear, open Settings, then API, and choose New webhook.",
          "Paste the address above as its URL, choose the teams Firefight files issues in, and tick Issues under data change events.",
          "Create it, then copy the signing secret from the webhook's page and paste it below."
        ]
      end

      def self.verify(raw_body:, headers:, secret:)
        return false unless Issues::Calls.signed?(secret, raw_body, headers[SIGNATURE_HEADER])

        sent = JSON.parse(raw_body.to_s)["webhookTimestamp"]
        sent.is_a?(Numeric) && (Time.current.to_f * 1000 - sent).abs <= FRESH_FOR.in_milliseconds
      rescue JSON::ParserError
        false
      end

      def self.event(payload)
        data = payload["data"]
        return unless payload["type"] == ISSUE_TYPE && data.is_a?(Hash) && data["identifier"].present?

        at = Time.iso8601(data["updatedAt"].to_s)
        keys = [ data["identifier"], *Array(data["previousIdentifiers"]).reverse ].uniq
        return Issues::Event.new(keys: keys, at: at, gone: Issues::GONE_DELETED) if payload["action"] == ACTION_REMOVE || data["trashed"]
        return Issues::Event.new(keys: keys, at: at, gone: Issues::GONE_ARCHIVED) if data["archivedAt"].present?
        return unless payload["action"] == ACTION_UPDATE

        changed = payload["updatedFrom"].to_h.keys.filter_map { |field| CHANGED_FIELDS[field] }
        return if changed.empty?

        Issues::Event.new(
          keys: keys, at: at, url: data["url"], title: data["title"], state: state_of(data.dig("state", "type")),
          assignee_email: data.dig("assignee", "email").presence, assignee_name: data.dig("assignee", "name"), changed: changed
        )
      rescue ArgumentError
        nil
      end

      def self.state_of(type)
        STATE_TYPES.find { |_state, types| types.include?(type) }&.first || (CLOSED_TYPES.include?(type) ? Issues::STATE_DONE : nil)
      end

      private

      def issue_of(data)
        return unless data.is_a?(Hash) && data["url"].to_s.match?(%r{\Ahttps://\S+\z})

        key = data["identifier"].presence || data["id"].presence
        type = data["statusType"] || data.dig("state", "type")
        email = data.dig("assignee", "email") || data["assigneeEmail"]
        Issues::Issue.new(key: key, url: data["url"], title: data["title"].to_s.strip.presence, state: self.class.state_of(type), assignee_email: email)
      end

      # The person's Linear account, found by an exact match on their email, or a note saying none was.
      def assign(arguments, email, notes)
        return if email.blank?

        users = objects_of(data!(run!(LIST_USERS, { "query" => email }, "find #{email} in Linear"), "the people"), "users", "nodes")
        found = users.find { |user| user["email"].to_s.casecmp?(email) }
        return arguments[parameter("assignee", "assigneeId")] = found["id"] if found

        notes << "Linear has nobody with the email #{email}, so the issue's assignee was left alone."
      end

      def state_id(target, state)
        team = target.to_h[TEAM].to_s.strip
        statuses = objects_of(data!(run!(LIST_STATUSES, { TEAM => team }, "list #{team}'s states"), "the team's states"), "statuses", "nodes")
        STATE_TYPES.fetch(state).lazy.filter_map { |type| statuses.find { |status| (status["type"] || status["statusType"]) == type } }.first&.dig("id")
      end

      def state_words(state) = { Issues::STATE_OPEN => "not started", Issues::STATE_STARTED => "started", Issues::STATE_DONE => "completed" }.fetch(state)

      # The name the connected tool gives a parameter, the first of names it reports, or the first name when it reports none.
      def parameter(*names)
        reported = parameters(SAVE_ISSUE)
        names.find { |name| reported.key?(name) } || names.first
      end
    end
  end
end
