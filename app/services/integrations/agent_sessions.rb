module Integrations
  # A tracker's own agent sessions. A person assigns an issue to Firefight's app at the provider, or mentions it, and Halon
  # looks into it and answers in the issue. The rest of the app never names the provider. A provider says it has them
  # through its definition's agent_sessions part, which answers on its class side for deliveries to its app's own webhook
  # (Api::V1::AppEventsController):
  #   verify(raw_body:, headers:, secret:)      whether a delivery is the provider's own, as it documents
  #   installation_of(payload, headers:)        the installation the delivery is about, kept on a connection's row
  #   installation_change(payload, headers:)    what it says changed about the installation (Installations), or nil
  #   event(payload)                            an Event, or nil for anything else, which is taken and left alone
  # and, made with the row of the connection the session came through, answers in it:
  #   say(session_id, activity)                 posts one Activity in the session
  # Each raises Integrations::Error with words a person reads when the provider refused.
  module AgentSessions
    # A session someone opened, a follow up in one, and a request to stop.
    STARTED = "started".freeze
    PROMPTED = "prompted".freeze
    STOPPED = "stopped".freeze
    KINDS = [ STARTED, PROMPTED, STOPPED ].freeze

    # What Halon says in a session: a note that it is working, a tool it reached for, its answer, why it could not answer,
    # and a question that needs a person.
    THOUGHT = "thought".freeze
    ACTION = "action".freeze
    RESPONSE = "response".freeze
    ERROR = "error".freeze
    ELICITATION = "elicitation".freeze

    # text is what the person wrote, context what the provider gathered around it (the issue, its comments, the team's
    # guidance), and asker_email and asker_name who wrote it when the provider says.
    Event = Data.define(:kind, :session_id, :text, :context, :issue_key, :issue_title, :issue_url, :asker_email, :asker_name) do
      def initialize(kind:, session_id:, text: nil, context: nil, issue_key: nil, issue_title: nil, issue_url: nil, asker_email: nil, asker_name: nil) = super

      def to_job = to_h.transform_keys(&:to_s)
      def self.from_job(hash) = new(**hash.symbolize_keys)
    end

    # One thing said in a session. An action names the tool in words (action), what it was asked (parameter) and, once it
    # answered, how it went (result). An ephemeral one is replaced by whatever is said next. An elicitation may offer
    # choices, each a word the person can pick, which comes back as a follow up saying it.
    Activity = Data.define(:kind, :body, :action, :parameter, :result, :ephemeral, :choices) do
      def initialize(kind:, body: nil, action: nil, parameter: nil, result: nil, ephemeral: false, choices: []) = super
    end

    module_function

    def source_of(provider_key) = Provider.for(provider_key).agent_sessions

    # A delivery about a session reaches the connection made through the installation it names. One installation may
    # be connected in more than one Firefight workspace, and the session is the latest connection's, the one whose
    # token the provider last handed out.
    def delivered!(provider_key, rows, payload)
      event = source_of(provider_key)&.event(payload)
      return if event.nil?

      row = rows.max_by(&:updated_at)
      return Rails.logger.info({ event: "agent_sessions.no_connection", provider: provider_key.to_s }.to_json) unless row

      AgentSessionEventJob.perform_later(row, event.to_job)
    end

    # What answers in a session that came through this row.
    def for(row) = source_of(row.integration.provider).new(row)
  end
end
