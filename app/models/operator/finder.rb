module Operator
  # Finds what an operator pasted: any record's id, the start of one copied from a log, or an incident number such as
  # INC-042, which each workspace counts on its own and so can match several.
  class Finder
    KIND_INCIDENT = "incident".freeze
    KIND_RUN = "run".freeze
    KIND_CHAT = "chat".freeze
    KIND_WORKFLOW = "workflow".freeze
    KINDS = [ KIND_INCIDENT, KIND_RUN, KIND_CHAT, KIND_WORKFLOW ].freeze

    # Shorter than this, the start of an id matches too much to mean anything.
    SHORTEST_PREFIX = 6
    LIMIT = 25
    ID_START = /\A[0-9a-f-]+\z/
    INCIDENT_NUMBER = /\A[a-z]+-\d+\z/i
    # A row of a trace is named by its kind and the id of its record, as the address of an opened row shows it.
    SPAN_KEY = /\A([a-z]+)-([0-9a-f][0-9a-f-]{5,})\z/

    # label names the record, place says where it lives, via what the pasted id was when it was not the record's own,
    # and span the trace row to open at.
    Match = Data.define(:kind, :id, :label, :place, :via, :span)

    # The id read as text, so the start of one matches. Shared with WorkflowRuns, which reads the engine's table.
    def self.id_starts(table, query)
      Arel::Nodes::NamedFunction.new("CAST", [ table[:id].as("text") ]).matches("#{ActiveRecord::Base.sanitize_sql_like(query)}%", nil, true)
    end

    def initialize(query)
      @query = query.to_s.strip.downcase
      span_key = @query.match(SPAN_KEY)
      @query = span_key[2] if span_key && !@query.match?(INCIDENT_NUMBER)
    end

    def matches
      return [] if @query.empty?

      found = @query.match?(INCIDENT_NUMBER) ? incident_numbers : by_id
      found.uniq { |match| [ match.kind, match.id, match.span ] }.first(LIMIT)
    end

    private

    def incident_numbers
      Incident.where("LOWER(identifier) = ?", @query).includes(:workspace).order(declared_at: :desc).map { |incident| incident_match(incident) }
    end

    def by_id
      return [] unless @query.match?(ID_START) && @query.delete("-").length >= SHORTEST_PREFIX

      [
        *starting(Incident.includes(:workspace)).map { |incident| incident_match(incident) },
        *starting(Investigation.includes(:workspace, :subject)).map { |run| run_match(run) },
        *starting(Conversation.includes(:workspace)).map { |conversation| chat_match(conversation) },
        *WorkflowRuns.starting_with(@query, limit: LIMIT).map { |workflow| workflow_match(workflow) },
        *through_chats, *through_deliveries, *through_ledger, *through_model_calls, *through_messages, *through_steps
      ]
    end

    # The saved chat has its own id, which is what a model call's error names.
    def through_chats
      starting(Chat.includes(:owner)).filter_map do |chat|
        owner = chat.owner
        via = "Saved chat #{chat.id}"
        case owner
        when Investigation then run_match(owner, via: via)
        when Conversation then chat_match(owner, via: via)
        end
      end
    end

    def through_deliveries
      starting(WebhookDelivery.includes(incident_event: { incident: :workspace })).filter_map do |delivery|
        incident = delivery.incident_event&.incident
        incident_match(incident, via: "Webhook delivery #{delivery.id}") if incident
      end
    end

    # A tool call's ledger row, as a trace shows it, leads back to the run that made it.
    def through_ledger
      steps = Investigation::Step.where(invocation_id: starting(Ability::Invocation).select(:id)).includes(investigation: %i[workspace subject])
      steps.map { |step| run_match(step.investigation, via: "Ledger entry #{step.invocation_id}") }
    end

    # A run's model call is a ledger row of its own, and a chat's is the model's usage row.
    def through_model_calls
      runs = starting(Inference.where(inferable_type: Investigation.name).includes(inferable: %i[workspace subject])).map do |inference|
        run_match(inference.inferable, via: "Model call #{inference.id}", span: "#{Trace::KIND_MODEL}-#{inference.id}")
      end
      chats = starting(RubyLLM::ActiveRecord::Usage.where(chat_type: Chat.name)).filter_map do |usage|
        conversation = Chat.find_by(id: usage.chat_id)&.owner
        chat_match(conversation, via: "Model call #{usage.id}", span: "#{Trace::KIND_MODEL}-#{usage.id}") if conversation.is_a?(Conversation)
      end
      runs + chats
    end

    def through_messages
      starting(Chat::Message.includes(chat: :owner)).filter_map do |message|
        owner = message.chat.owner
        via = "Chat message #{message.id}"
        owner.is_a?(Investigation) ? run_match(owner, via: via) : chat_match(owner, via: via)
      end
    end

    def through_steps
      starting(Investigation::Step.includes(investigation: %i[workspace subject])).map do |step|
        run_match(step.investigation, via: "Tool call #{step.id}", span: "#{Trace::KIND_TOOL}-#{step.id}")
      end
    end

    def starting(scope)
      scope.where(Finder.id_starts(scope.arel_table, @query)).limit(LIMIT)
    end

    def incident_match(incident, via: nil)
      Match.new(kind: KIND_INCIDENT, id: incident.id, label: "#{incident.identifier} #{incident.name}", place: incident.workspace.name, via: via, span: nil)
    end

    def run_match(run, via: nil, span: nil)
      label = run.incident ? "#{run.incident.identifier} #{run.incident.name}" : run.question.to_s
      Match.new(kind: KIND_RUN, id: run.id, label: label, place: run.workspace.name, via: via, span: span)
    end

    def chat_match(conversation, via: nil, span: nil)
      Match.new(kind: KIND_CHAT, id: conversation.id, label: conversation.title.presence || Conversation::UNTITLED,
                place: conversation.workspace.name, via: via, span: span)
    end

    def workflow_match(workflow)
      subject = workflow.subject
      place = subject.respond_to?(:workspace) ? subject.workspace.name : workflow.subject_type.to_s
      Match.new(kind: KIND_WORKFLOW, id: workflow.id, label: workflow.workflow_class, place: place, via: nil, span: nil)
    end
  end
end
