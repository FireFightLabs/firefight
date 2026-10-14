module Integrations
  # Labels someone added to an issue at a connected provider, in one shape whichever provider sent them, which start the
  # issue_assigned workflow trigger. A provider reports them from deliveries it already sends: its agent_sessions part
  # answers labelled(payload) for its app's own webhook (Integrations::AgentSessions), and its event source answers
  # labelled(payload, headers:) for its map events (Integrations::MapEvents). Either answers a Labelled, a list of them or
  # nil. Nothing here names a provider.
  module IssueLabels
    # An issue that gained labels, each by its name. reference names the issue, the labels and when, the same however
    # often it is delivered. text is the issue's description, and asker_email and asker_name who added them.
    Labelled = Data.define(:reference, :labels, :issue_key, :issue_title, :issue_url, :text, :asker_email, :asker_name) do
      def initialize(text: nil, asker_email: nil, asker_name: nil, **) = super
    end

    module_function

    # The providers that say when someone adds a label to an issue.
    def providers
      IntegrationProvider.all.select do |entry|
        AgentSessions.source_of(entry.key).respond_to?(:labelled) || MapEvents.source_of(entry.key).respond_to?(:labelled)
      end
    end

    # What a delivery to a connection's event source says was labelled, or none.
    def of(provider_key, payload, headers:)
      source = MapEvents.source_of(provider_key)
      return [] unless source.respond_to?(:labelled)

      Array(source.labelled(payload, headers: headers))
    rescue StandardError => error
      Rails.logger.warn({ event: "issue_labels.unread", provider: provider_key, error: error.class.name }.to_json)
      []
    end

    # Labels added to an issue reach the workflows of each workspace these connections belong to, once each, as the
    # connection that told Firefight. Only a workflow whose trigger names one of them starts (Workflow::Listening). It
    # opens no session, since nobody asked Firefight anything.
    def report!(rows, labelled)
      return if labelled.empty?

      rows.uniq { |row| row.integration.workspace_id }.each do |row|
        integration = row.integration
        labelled.each do |found|
          issue = { "provider" => integration.display_name, "key" => found.issue_key, "title" => found.issue_title, "url" => found.issue_url,
                    "text" => found.text, "asked_by" => found.asker_name, "asked_by_email" => found.asker_email,
                    Workflow::Trigger::Fields::HOW => Workflow::TriggerPayloads::ISSUE_LABELLED, Workflow::Trigger::Fields::LABELS => found.labels }
          Workflow::Trigger::Events.fire!(integration.workspace, Workflow::Trigger::KIND_ISSUE_ASSIGNED, key: "#{integration.id}:label:#{found.reference}",
                                                                                                      subject: row, details: issue)
        end
      end
    end
  end
end
