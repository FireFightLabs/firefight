module Integrations
  # An issue in a tracker, kept in step with an incident's items without the platform knowing which tracker it is. A
  # provider says so through its definition's issue_tracker, a RemoteReader that answers two things.
  #
  # What a tool call did, for issues Halon opens and closes in a chat (report):
  #   report(tool_name:, arguments:, result:)   an Issues::Report, or nil when the call did neither
  #
  # Keeping an item and its issue in step, for the workspace's chosen tracker (Issues.session):
  #   create(title:, description:, target:, assignee_email:)  an Outcome whose issue is the new one
  #   update(key:, target:, title: nil, state: nil, assignee_email: nil, unassign: false)  an Outcome, changing only
  #                                              what is given, gone when the issue is no longer there
  #   read(key, target:)                         the Issue, or nil when the tracker no longer has it
  # each raising Failed with words a person reads when the tracker refused or a tool it needs is off.
  #
  # And, as class methods, what needs no connection:
  #   CREATE_TOOL                                the tool that opens an issue
  #   SYNC_TOOLS                                 every tool keeping items in step calls, which sync is granted
  #   TARGET_FIELDS                              where new issues go, as TargetFields the settings page asks
  #   setup_steps                                sentences saying how to send the tracker's webhook to Firefight's address
  #   verify(raw_body:, headers:, secret:, webhook_id:)  whether a webhook delivery is the tracker's own, as it documents
  #
  # A provider whose own app connects it natively (IntegrationProvider::App) has a pack that registers the webhook
  # itself: register_issue_webhook(environment_row, url:, target:) answering a Webhook, remove_issue_webhook(
  # environment_row, id) and, where webhooks expire, refresh_issue_webhook(environment_row, id) answering when it now does.
  #   event(payload)                             an Event for a change to an issue, or nil for anything else
  #   OPENS                                      the tools that can open an issue, which a chat asks how to keep
  module Issues
    OPENED = :opened
    CLOSED = :closed
    CHANGES = [ OPENED, CLOSED ].freeze

    # Where an issue is in its workflow, in Firefight's words. Each tracker maps its own documented state kinds here.
    STATE_OPEN = "open".freeze
    STATE_STARTED = "started".freeze
    STATE_DONE = "done".freeze
    STATES = [ STATE_OPEN, STATE_STARTED, STATE_DONE ].freeze

    # What an Event says changed.
    FIELD_TITLE = "title".freeze
    FIELD_STATE = "state".freeze
    FIELD_ASSIGNEE = "assignee".freeze
    FIELDS = [ FIELD_TITLE, FIELD_STATE, FIELD_ASSIGNEE ].freeze

    # Why an issue stopped being there.
    GONE_DELETED = "deleted".freeze
    GONE_ARCHIVED = "archived".freeze

    # A tracker refused, or a tool it needs is off. The words are for the person.
    class Failed < Integrations::Error; end

    # key is the tracker's own name for the issue, such as FIR-105, and url its page.
    Report = Data.define(:change, :key, :title, :url) do
      def opened? = change == OPENED
      def closed? = change == CLOSED
    end

    Issue = Data.define(:key, :url, :title, :state, :assignee_email) do
      def initialize(key:, url:, title: nil, state: nil, assignee_email: nil) = super
    end

    # What a create or an update did, and sentences about what it left alone, such as an assignee the tracker has no
    # account for. gone is true when the issue to change is no longer there.
    Outcome = Data.define(:issue, :notes, :gone) do
      def initialize(issue: nil, notes: [], gone: false) = super
    end

    # A change the tracker sent. keys are every key the issue has had, newest first, so an issue moved to another team
    # or project is still found. changed names the FIELDS this change touched, and at is when it was made. assignee_email
    # is nil when the issue has nobody, and assignee_name is the tracker's name for whoever it is. gone is set when the
    # issue was deleted or archived.
    Event = Data.define(:keys, :url, :title, :state, :assignee_email, :assignee_name, :changed, :at, :gone) do
      def initialize(keys:, at:, url: nil, title: nil, state: nil, assignee_email: nil, assignee_name: nil, changed: [], gone: nil) = super

      def key = keys.first
      def changed?(field) = changed.include?(field)

      def to_job = to_h.transform_keys(&:to_s).merge("at" => at.iso8601(6))
      def self.from_job(hash) = new(**hash.symbolize_keys.merge(at: Time.iso8601(hash["at"])))
    end

    # A webhook Firefight registered with a tracker. secret is what it signs with, nil when the tracker signs with
    # Firefight's app instead, and expires_at when it lapses unless refreshed.
    Webhook = Data.define(:id, :secret, :expires_at) do
      def initialize(id:, secret: nil, expires_at: nil) = super
    end

    # A field the settings page asks for where new issues go, such as a Linear team or a Jira project.
    TargetField = Data.define(:key, :label, :placeholder, :hint, :required)

    # Whether the tool can open an issue, so whoever offers it can ask how the new issue is to be kept.
    def self.opens?(tool)
      tracker = Provider.for(tool.integration.provider).issue_tracker
      tracker.present? && tracker::OPENS.include?(tool.name)
    end

    # What a tool call that succeeded did to an issue, or nil. A tracker whose answer leaves out what it needs reads
    # through the same connection. The block is handed the switched on tool and its arguments, authorizes the read as
    # whoever made the call and yields to run it, answering the tool's result or nil when it may not.
    def self.report(tool:, environment_row:, arguments:, result:, &authorize)
      tracker = Provider.for(tool.integration.provider).issue_tracker
      return if tracker.nil? || environment_row.nil? || !result.is_a?(Hash) || result["isError"]

      reader = connected(tracker, tool.integration, environment_row, &authorize)
      reader.report(tool_name: tool.name, arguments: arguments.to_h.stringify_keys, result: result)
    rescue Integrations::Error => error
      Rails.logger.warn({ event: "issues.unread", provider: tool.integration.provider, error: error.message.truncate(200) }.to_json)
      nil
    end

    # Whether the provider keeps items and issues in step, so a connection to it can be the workspace's tracker.
    def self.syncs?(provider_key) = tracker_of(provider_key).present?

    def self.create_tool(provider_key) = tracker_of(provider_key)&.const_get(:CREATE_TOOL, false)

    # Every tool keeping items in step calls, which Firefight's issue sync is granted and nothing more.
    def self.sync_tools(provider_key) = tracker_of(provider_key)&.const_get(:SYNC_TOOLS, false) || []

    def self.target_fields(provider_key) = tracker_of(provider_key)&.const_get(:TARGET_FIELDS, false) || []

    def self.setup_steps(provider_key) = tracker_of(provider_key)&.setup_steps || []

    # Whether a webhook delivery is the provider's own, signed with the secret saved for it or, for one Firefight
    # registered, as the tracker signs those. A provider that does not sync accepts none.
    def self.verify(provider_key, raw_body:, headers:, secret:, webhook_id: nil)
      tracker = tracker_of(provider_key)
      return false if tracker.nil? || (secret.blank? && webhook_id.blank?)

      tracker.verify(raw_body: raw_body, headers: headers, secret: secret, webhook_id: webhook_id)
    end

    # Whether Firefight registers the connection's webhook itself, which a connection made with its own app does.
    def self.registers_webhooks?(integration)
      pack = integration.native? && NativePack.for(integration.provider)
      pack.present? && pack.method_defined?(:register_issue_webhook)
    end

    def self.register_webhook(integration, url:, target:)
      row = environment_of(integration)
      NativePack.fetch!(integration).register_issue_webhook(row, url: url, target: target)
    end

    def self.remove_webhook(integration, id) = NativePack.fetch!(integration).remove_issue_webhook(environment_of(integration), id)

    # When the webhook now lapses, or nil for a tracker whose webhooks do not.
    def self.refresh_webhook(integration, id)
      pack = NativePack.fetch!(integration)
      pack.respond_to?(:refresh_issue_webhook) ? pack.refresh_issue_webhook(environment_of(integration), id) : nil
    end

    def self.environment_of(integration)
      integration.resolve_environment(nil) || raise(Failed, "#{integration.name} has no environment to call, so Firefight cannot reach it.")
    end

    def self.event(provider_key, payload) = payload.is_a?(Hash) ? tracker_of(provider_key)&.event(payload) : nil

    # The connection's tracker, to create, update and read issues. Every call is handed to the block with its tool and
    # arguments, which authorizes it as whoever is acting and yields to run it.
    def self.session(integration, &authorize)
      tracker = tracker_of(integration.provider)
      environment_row = integration.resolve_environment(nil)
      raise Failed, "#{integration.name} has no environment to call, so Firefight cannot reach it." unless tracker && environment_row

      connected(tracker, integration, environment_row, &authorize)
    end

    def self.tracker_of(provider_key)
      tracker = Provider.for(provider_key).issue_tracker
      tracker if tracker&.const_defined?(:CREATE_TOOL, false)
    end

    def self.connected(tracker, integration, environment_row, &authorize)
      tools = integration.tools.enabled.available.index_by(&:name)
      tracker.new(ConnectionSettings.of(environment_row), tools) do |name, arguments, _reads|
        tool = tools[name]
        next nil unless tool

        authorize.call(tool, arguments) do
          integration.executor.call(tool: tool, environment_row: environment_row, arguments: arguments)
        end
      end
    end
    private_class_method :tracker_of, :connected, :environment_of
  end
end
