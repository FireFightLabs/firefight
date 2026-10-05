module Integrations
  module IssueTrackers
    # Atlassian's server opens an issue with createjiraissue, whose answer names the new key, and moves one with
    # transitionjiraissue, whose answer does not say where it moved. So a transition is followed by Firefight's own read
    # of the issue with getjiraissue, and the issue is closed when its status is in Jira's done category (statusCategory
    # key done, which every Jira workflow's finished statuses carry). The page is https://<site>/browse/<KEY>, the
    # address Atlassian's agent skills give (see SourceLinks::Jira). The site is the call's cloudId when it names the
    # site, or else the address getaccessibleatlassianresources gives for that cloud id.
    #
    # Keeping an item in step uses the same server with the site's address as cloudId: createjiraissue (projectKey,
    # issueType, summary, description and assignee, an account id, as atlassian/atlassian-mcp-server's skills/README.md
    # gives them for its v2 server), editjiraissue (fields) for the summary and assignee, listjiraissuetransitions and
    # transitionjiraissue (transition, its id) for the status, chosen by the status category the transition leads to,
    # lookupjiraaccountid to find the person whose email matches, and getjiraissue to read one.
    #
    # Changes come back by Jira's admin webhook (https://developer.atlassian.com/cloud/jira/platform/webhooks/): a POST
    # whose webhookEvent is jira:issue_updated or jira:issue_deleted, with timestamp in milliseconds, the issue (key and
    # fields summary, status with its statusCategory, assignee) and, for an update, changelog items naming each changed
    # field. A webhook made with a secret signs the raw body in X-Hub-Signature as sha256=<hex HMAC-SHA256>.
    class Jira < RemoteReader
      include Issues::Calls

      NAME = "Jira".freeze
      PROVIDER_KEY = "jira".freeze
      CREATE_ISSUE = SourceLinks::Jira::CREATE_ISSUE
      CREATE_TOOL = CREATE_ISSUE
      EDIT_ISSUE = "editjiraissue".freeze
      TRANSITION_ISSUE = "transitionjiraissue".freeze
      LIST_TRANSITIONS = "listjiraissuetransitions".freeze
      LOOKUP_ACCOUNT = "lookupjiraaccountid".freeze
      GET_ISSUE = "getjiraissue".freeze
      SYNC_TOOLS = [ CREATE_ISSUE, EDIT_ISSUE, TRANSITION_ISSUE, LIST_TRANSITIONS, LOOKUP_ACCOUNT, GET_ISSUE ].freeze
      RESOURCES = "getaccessibleatlassianresources".freeze
      DONE = "done".freeze
      READ_FIELDS = %w[summary status].freeze
      OPENS = [ CREATE_ISSUE ].freeze
      SYNC_FIELDS = %w[summary status assignee].freeze

      SITE = "site".freeze
      PROJECT = "project".freeze
      ISSUE_TYPE = "issue_type".freeze
      DEFAULT_ISSUE_TYPE = "Task".freeze
      TARGET_FIELDS = [
        Issues::TargetField.new(key: SITE, label: "Site", placeholder: "acme.atlassian.net", required: true,
                                hint: "The address of the Jira site new issues are filed on."),
        Issues::TargetField.new(key: PROJECT, label: "Project key", placeholder: "OPS", required: true,
                                hint: "The key of the project new issues are filed in."),
        Issues::TargetField.new(key: ISSUE_TYPE, label: "Issue type", placeholder: DEFAULT_ISSUE_TYPE, required: false,
                                hint: "The type new issues are given. Task when left empty.")
      ].freeze

      # Jira's status category keys (StatusCategory in Jira's REST API) for each of Firefight's states.
      CATEGORIES = { Issues::STATE_OPEN => "new", Issues::STATE_STARTED => "indeterminate", Issues::STATE_DONE => DONE }.freeze

      SIGNATURE_HEADER = "X-Hub-Signature".freeze
      SIGNATURE_METHOD = "sha256=".freeze
      UPDATED = "jira:issue_updated".freeze
      DELETED = "jira:issue_deleted".freeze
      # Changelog items name a field by its name.
      CHANGED_FIELDS = { "summary" => Issues::FIELD_TITLE, "status" => Issues::FIELD_STATE, "assignee" => Issues::FIELD_ASSIGNEE }.freeze
      MOVED = "key".freeze

      def report(tool_name:, arguments:, result:)
        case tool_name
        when CREATE_ISSUE then opened(arguments, result)
        when TRANSITION_ISSUE then closed(arguments)
        end
      end

      def create(title:, description:, target:, assignee_email: nil)
        site, project = place!(target)
        notes = []
        arguments = { SourceLinks::Jira::CLOUD_ID => site, "projectKey" => project, "issueType" => issue_type(target), "summary" => title,
                      "description" => description }
        account = account_of(site, assignee_email, notes)
        arguments["assignee"] = account if account
        result = run!(CREATE_ISSUE, arguments, "open the issue")
        key = Capabilities::Answers.text(result)[SourceLinks::Jira::CREATED_KEY, 1]
        raise Issues::Failed, "Jira opened the issue but did not say its key." unless key

        Issues::Outcome.new(issue: Issues::Issue.new(key: key, url: "https://#{site}/browse/#{key}", title: title, state: Issues::STATE_OPEN),
                            notes: notes)
      end

      def update(key:, target:, title: nil, state: nil, assignee_email: nil, unassign: false)
        site, = place!(target)
        notes = []
        fields = {}
        fields["summary"] = title if title
        account = assignee_email && account_of(site, assignee_email, notes)
        fields["assignee"] = { "accountId" => account } if account
        # Jira's REST API unassigns an issue whose assignee is set to null.
        fields["assignee"] = nil if unassign
        if fields.any?
          result = call(EDIT_ISSUE, issue_arguments(site, key).merge("fields" => fields), "change #{key}")
          return Issues::Outcome.new(notes: notes, gone: true) if missing?(result)

          answered!(EDIT_ISSUE, result, "change #{key}")
        end
        return Issues::Outcome.new(notes: notes, gone: true) if state && transition(site, key, state, notes) == :gone

        Issues::Outcome.new(notes: notes)
      end

      def read(key, target:)
        site, = place!(target)
        asked = issue_arguments(site, key)
        fields = parameters(GET_ISSUE)["fields"]
        asked["fields"] = fields.to_h["type"] == "string" ? SYNC_FIELDS.join(",") : SYNC_FIELDS if fields
        result = call(GET_ISSUE, asked, "read #{key}")
        return if missing?(result)

        data = data!(answered!(GET_ISSUE, result, "read #{key}"), key)
        Issues::Issue.new(
          key: data["key"].presence || key, url: "https://#{site}/browse/#{data['key'].presence || key}", title: data.dig("fields", "summary"),
          state: self.class.state_of(data.dig("fields", "status", "statusCategory", "key")),
          assignee_email: data.dig("fields", "assignee", "emailAddress")
        )
      end

      def self.setup_steps
        [
          "In Jira, open Settings, then System, then WebHooks, and choose Create a WebHook.",
          "Paste the address above as its URL, and tick updated and deleted under Issue related events.",
          "Choose Generate secret, copy the secret and paste it below, then create the webhook."
        ]
      end

      # A webhook an admin made carries the secret's signature. One Firefight registered through its own app carries a
      # bearer token Atlassian signs with the app's client secret ("Webhooks for OAuth 2.0 apps are secured by bearer
      # authentication", developer.atlassian.com/cloud/jira/platform/webhooks), and names the webhooks it matched in
      # matchedWebhookIds, which must hold the one Firefight registered for this workspace.
      def self.verify(raw_body:, headers:, secret:, webhook_id: nil)
        given = headers[SIGNATURE_HEADER].to_s
        return secret.present? && Issues::Calls.signed?(secret, raw_body, given.delete_prefix(SIGNATURE_METHOD)) if given.start_with?(SIGNATURE_METHOD)

        webhook_id.present? && app_signed?(headers["Authorization"].to_s.delete_prefix("Bearer ")) &&
          Array(JSON.parse(raw_body.to_s)["matchedWebhookIds"]).map(&:to_s).include?(webhook_id.to_s)
      rescue JSON::ParserError
        false
      end

      def self.app_signed?(token)
        secret = IntegrationProvider.app_client(PROVIDER_KEY)[:client_secret]
        return false if token.blank? || secret.blank?

        JWT.decode(token, secret, true, algorithm: "HS256")
        true
      rescue JWT::DecodeError
        false
      end

      def self.event(payload)
        issue = payload["issue"]
        return unless issue.is_a?(Hash) && issue["key"].present? && payload["timestamp"].is_a?(Numeric)

        at = Time.at(payload["timestamp"] / 1000.0).utc
        items = Array(payload.dig("changelog", "items")).grep(Hash)
        keys = [ issue["key"], *items.filter_map { |item| item["fromString"] if item["field"].to_s.casecmp?(MOVED) } ].uniq
        return Issues::Event.new(keys: keys, at: at, gone: Issues::GONE_DELETED) if payload["webhookEvent"] == DELETED
        return unless payload["webhookEvent"] == UPDATED

        changed = items.filter_map { |item| CHANGED_FIELDS[item["field"].to_s.downcase] }.uniq
        return if changed.empty?

        fields = issue["fields"].to_h
        Issues::Event.new(
          keys: keys, at: at, title: fields["summary"], state: state_of(fields.dig("status", "statusCategory", "key")),
          assignee_email: fields.dig("assignee", "emailAddress").presence, assignee_name: fields.dig("assignee", "displayName"),
          changed: changed
        )
      end

      def self.state_of(category) = CATEGORIES.key(category)

      private

      def opened(arguments, result)
        key = Capabilities::Answers.text(result)[SourceLinks::Jira::CREATED_KEY, 1]
        url = key && page(arguments[SourceLinks::Jira::CLOUD_ID], key)
        return unless url

        Issues::Report.new(change: Issues::OPENED, key: key, title: arguments["summary"].to_s.strip.presence, url: url)
      end

      def closed(arguments)
        key = arguments[SourceLinks::Jira::ISSUE].to_s.strip
        return unless key.match?(SourceLinks::Jira::ISSUE_KEY)

        issue = read_issue(arguments[SourceLinks::Jira::CLOUD_ID], key)
        return unless issue&.dig("fields", "status", "statusCategory", "key") == DONE

        url = page(arguments[SourceLinks::Jira::CLOUD_ID], key)
        url && Issues::Report.new(change: Issues::CLOSED, key: key, title: issue.dig("fields", "summary").presence, url: url)
      end

      def read_issue(cloud_id, key)
        asked = { SourceLinks::Jira::CLOUD_ID => cloud_id, SourceLinks::Jira::ISSUE => key }
        fields = parameters(GET_ISSUE)["fields"]
        asked["fields"] = fields.to_h["type"] == "string" ? READ_FIELDS.join(",") : READ_FIELDS if fields
        result = call(GET_ISSUE, asked, "the status of #{key}")
        data = result && !result["isError"] ? Capabilities::Answers.data(result) : nil
        data.is_a?(Hash) ? data : nil
      end

      def page(cloud_id, key)
        site = SourceLinks::Jira.site_of(cloud_id) || site_of_resource(cloud_id)
        site && "https://#{site}/browse/#{key}"
      end

      def site_of_resource(cloud_id)
        return if cloud_id.blank?

        result = call(RESOURCES, {}, "the address of the Jira site")
        resources = result && !result["isError"] ? Capabilities::Answers.data(result) : nil
        found = Array(resources).find { |resource| resource.is_a?(Hash) && resource["id"] == cloud_id.to_s }
        found && SourceLinks::Jira.site_of(found["url"])
      end

      def place!(target)
        site = SourceLinks::Jira.site_of(target.to_h[SITE])
        project = target.to_h[PROJECT].to_s.strip.upcase
        raise Issues::Failed, "Choose the Jira site and project new issues are filed in under Settings, Workspace." if site.nil? || project.empty?

        [ site, project ]
      end

      def issue_type(target) = target.to_h[ISSUE_TYPE].to_s.strip.presence || DEFAULT_ISSUE_TYPE

      def issue_arguments(site, key) = { SourceLinks::Jira::CLOUD_ID => site, SourceLinks::Jira::ISSUE => key }

      # The person's Jira account, found by an exact match on their email, or a note saying none was. Jira leaves an
      # account's email out where the person's profile hides it, which counts as no match.
      def account_of(site, email, notes)
        return if email.blank?

        reported = parameters(LOOKUP_ACCOUNT)
        query = %w[query searchString].find { |name| reported.key?(name) } || "query"
        listing = data!(run!(LOOKUP_ACCOUNT, { SourceLinks::Jira::CLOUD_ID => site, query => email }, "find #{email} in Jira"), "the people")
        found = objects_of(listing, "users", "values", "accounts").find { |user| user["emailAddress"].to_s.casecmp?(email) }
        return found["accountId"] if found

        notes << "Jira has nobody whose email shows as #{email}, so the issue's assignee was left alone."
        nil
      end

      # Moves the issue through the first transition that leads to a status in the state's category. Answers :gone when
      # the issue is no longer there.
      def transition(site, key, state, notes)
        result = call(LIST_TRANSITIONS, issue_arguments(site, key), "list #{key}'s transitions")
        return :gone if missing?(result)

        listing = data!(answered!(LIST_TRANSITIONS, result, "list #{key}'s transitions"), "the transitions")
        found = objects_of(listing, "transitions").find { |each| each.dig("to", "statusCategory", "key") == CATEGORIES.fetch(state) }
        return notes << "No transition from #{key}'s status leads to a #{state_words(state)} status, so its status was left alone." unless found

        run!(TRANSITION_ISSUE, issue_arguments(site, key).merge("transition" => { "id" => found["id"].to_s }), "move #{key}")
      end

      def state_words(state) = { Issues::STATE_OPEN => "to do", Issues::STATE_STARTED => "in progress", Issues::STATE_DONE => "done" }.fetch(state)
    end
  end
end
