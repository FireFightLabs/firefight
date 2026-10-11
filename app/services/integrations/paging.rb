module Integrations
  # A page raised in an on-call tool for a Firefight incident, and kept in step with it both ways, without the platform
  # knowing which tool it is. A provider says it pages through its definition's pager, an Integrations::Pager answering:
  #   page(title:, details:, target:, key:)   a Raised page, opened on target (what TARGET_WORDS says a page goes to)
  #   acknowledge(external_id, key:)           nil, the page stops paging further along its escalation. key is the one
  #                                            Firefight raised it with, which finds a page whose id it has not heard yet
  #   resolve(external_id, key:)               nil, the page is over
  #   knows?(external_id)                      whether the page is this connection's, for one an alert brought in
  #   on_call                                  the people on call now, each an OnCall, read as ON_CALL_TOOL
  # each raising Failed with words a person reads when the tool refused, or a tool it needs is off.
  #
  # And as constants of the pager class, which need no connection:
  #   TARGET_WORDS    what a page is raised on and how to name it, as Halon and an outside agent read it
  #   PAGES_WORDS     what a page goes to, as a person reads it on the on-call page
  #   SYNC_TOOLS      every tool raising and keeping pages in step is authorized as, which Firefight paging is granted
  #   ON_CALL_TOOL    the read that says who is on call, which the investigator holds through the connection's read pack
  #   ALERT_SOURCE    the alert source whose webhook reports what happens to the tool's pages (AlertSource::PROVIDERS)
  module Paging
    STATE_TRIGGERED = "triggered".freeze
    STATE_ACKNOWLEDGED = "acknowledged".freeze
    STATE_RESOLVED = "resolved".freeze

    # What an Event says happened to a page in its tool.
    EVENT_ACKNOWLEDGED = "acknowledged".freeze
    EVENT_ESCALATED = "escalated".freeze
    EVENT_NOTED = "noted".freeze
    EVENT_RESOLVED = "resolved".freeze

    # The tool refused, or a tool it needs is off. The words are for the person.
    class Failed < Integrations::Error; end

    # external_id is the tool's own id for the page, nil until the tool says it, reference what the tool shows for it
    # (#42) and url its page.
    Raised = Data.define(:external_id, :reference, :url)

    # Someone on call now. covers says where, such as "Platform schedule, level 1 of Checkout".
    OnCall = Data.define(:name, :email, :covers)

    # Something that happened to a page in its tool, read from the tool's webhook by the alert source's adapter. id is the
    # tool's own id for the delivery, when it gives one, so a redelivery is recorded once. external_id is the page's id
    # there and key the key Firefight raised it with, when it did. actor_email is nil when the tool gives only a name.
    # by_person is false when automation did it, such as a monitor resolving its own alert. note is what was written, or
    # who it went to for an escalation.
    Event = Data.define(:id, :external_id, :key, :kind, :actor_name, :actor_email, :by_person, :note) do
      def initialize(external_id:, kind:, id: nil, key: nil, actor_name: nil, actor_email: nil, by_person: false, note: nil) = super

      def to_job = to_h.transform_keys(&:to_s)
      def self.from_job(hash) = new(**hash.symbolize_keys)
    end

    # The key a page Firefight raises carries in its tool, which the tool sends back with every change to it, so a page
    # is known as Firefight's before its id is.
    KEY_PREFIX = "firefight-page-".freeze

    def self.key_for(page_id) = "#{KEY_PREFIX}#{page_id}"

    def self.page_id_of(key) = key.to_s.start_with?(KEY_PREFIX) ? key.to_s.delete_prefix(KEY_PREFIX).presence : nil

    def self.pages?(provider_key) = pager_of(provider_key).present?

    # The workspace's connections that can raise a page, oldest first.
    def self.connections(workspace)
      workspace.integrations.active.order(:created_at).select { |integration| pages?(integration.provider) }
    end

    def self.target_words(provider_key) = pager_of(provider_key)&.const_get(:TARGET_WORDS, false)

    def self.pages_words(provider_key) = pager_of(provider_key)&.const_get(:PAGES_WORDS, false)

    def self.sync_tools(provider_key) = pager_of(provider_key)&.const_get(:SYNC_TOOLS, false) || []

    def self.alert_source_of(provider_key) = pager_of(provider_key)&.const_get(:ALERT_SOURCE, false)

    # The connections whose pages an alert source of this kind reports on.
    def self.connections_for_source(workspace, source_provider)
      connections(workspace).select { |integration| pager_of(integration.provider)::ALERT_SOURCE == source_provider }
    end

    # Whether an alert source of this kind reports on any tool's pages.
    def self.reported_by?(source_provider)
      Provider.all.any? { |provider| provider.pager && provider.pager::ALERT_SOURCE == source_provider }
    end

    # The connection's pager. Every call is handed to the block with its tool and arguments, which authorizes it as
    # whoever is acting and yields to run it.
    def self.session(integration, &authorize)
      pager = pager_of(integration.provider)
      environment_row = integration.resolve_environment(nil)
      raise Failed, "#{integration.name} has no environment to call, so Firefight cannot reach it." unless pager && environment_row

      pager.new(integration, environment_row, integration.tools.enabled.available.index_by(&:name), &authorize)
    end

    def self.pager_of(provider_key) = Provider.for(provider_key).pager
    private_class_method :pager_of
  end
end
