module Integrations
  # An issue in a tracker, kept in step with an incident's items without the platform knowing which tracker it is. A
  # provider says so through its definition's issue_tracker, a RemoteReader that answers two things.
  #
  # What a tool call did, for issues Halon opens and closes in a chat (report):
  #   report(tool_name:, arguments:, result:)   an Issues::Report, or nil when the call did neither
  #
  # Keeping an item and its issue in step, for the workspace's chosen tracker (Issues.session):
  #   create(title:, description:, target:, assignee_email:)  an Outcome whose issue is the new one
  #   update(key:, target:, title: nil, state: nil, assignee_email: nil)  an Outcome, changing only what is given, gone
  #                                              when the issue is no longer there
  #   read(key, target:)                         the Issue, or nil when the tracker no longer has it
  # each raising Failed with words a person reads when the tracker refused or a tool it needs is off.
  #
  # And, as class methods, what needs no connection:
  #   CREATE_TOOL                                the tool that opens an issue, which must be switched on
  #   TARGET_FIELDS                              where new issues go, as TargetFields the settings page asks
  #   setup_steps                                sentences saying how to send the tracker's webhook to Firefight's address
  #   verify(raw_body:, headers:, secret:)       whether a webhook delivery is the tracker's own, as it documents
  #   event(payload)                             an Event for a change to an issue, or nil for anything else
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

    # A field the settings page asks for where new issues go, such as a Linear team or a Jira project.
    TargetField = Data.define(:key, :label, :placeholder, :hint, :required)

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

    def self.target_fields(provider_key) = tracker_of(provider_key)&.const_get(:TARGET_FIELDS, false) || []

    def self.setup_steps(provider_key) = tracker_of(provider_key)&.setup_steps || []

    # Whether a webhook delivery is the provider's own. A provider that does not sync accepts none.
    def self.verify(provider_key, raw_body:, headers:, secret:)
      tracker = tracker_of(provider_key)
      return false if tracker.nil? || secret.blank?

      tracker.verify(raw_body: raw_body, headers: headers, secret: secret)
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
    private_class_method :tracker_of, :connected
  end
end
